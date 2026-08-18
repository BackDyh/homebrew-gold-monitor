import AppKit
import AurumBarCore
import AurumBarRuntime

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let refreshInterval: TimeInterval = 30 * 60
    private static let errorNotificationInterval: TimeInterval = 60 * 60

    private let client = GoldAPIClient()
    private let keychain = KeychainStore()
    private let prompt = AppKeyPrompt()
    private let notifier = AppleScriptNotifier()
    private let quoteCache = QuoteCache()

    private var statusItem: NSStatusItem!
    private var infoItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var timer: Timer?
    private var coordinator: QuoteRefreshCoordinator?
    private var currentQuote: GoldQuote?
    private var viewState: QuoteViewState = .starting(previous: nil)
    private var lastNotifiedPrice: String?
    private var errorNotificationPolicy = ErrorNotificationPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureRuntimeControl()
        configureApplicationMenu()
        configureStatusItem()
        restoreCachedQuote()
        guard configureAPIKey() else { return }
        scheduleRefresh()
        coordinator?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        coordinator?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureRuntimeControl() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(stopRequested),
            name: RuntimeControl.stopNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func configureApplicationMenu() {
        // 菜单栏后台应用默认没有“编辑”菜单，导致输入框收不到 ⌘V。
        let mainMenu = NSMenu()
        let editRootItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")

        for (title, action, key) in [
            ("剪切", "cut:", "x"),
            ("复制", "copy:", "c"),
            ("粘贴", "paste:", "v"),
            ("全选", "selectAll:", "a"),
        ] {
            editMenu.addItem(
                withTitle: title,
                action: Selector(action),
                keyEquivalent: key
            )
        }
        editRootItem.submenu = editMenu
        mainMenu.addItem(editRootItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
        }

        let menu = NSMenu()
        infoItem = NSMenuItem(title: "尚未获取行情", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refreshFromMenu),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let detailsItem = NSMenuItem(
            title: "查看详情",
            action: #selector(showDetails),
            keyEquivalent: "d"
        )
        detailsItem.target = self
        menu.addItem(detailsItem)
        menu.addItem(.separator())

        let keyItem = NSMenuItem(
            title: "设置个人 AppKey…",
            action: #selector(changeAPIKey),
            keyEquivalent: "k"
        )
        keyItem.target = self
        menu.addItem(keyItem)

        let platformItem = NSMenuItem(
            title: "打开 AppKey 申请页面",
            action: #selector(openApplicationPage),
            keyEquivalent: ""
        )
        platformItem.target = self
        menu.addItem(platformItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 AurumBar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        render()
    }

    private func restoreCachedQuote() {
        guard let quote = quoteCache.load() else { return }
        currentQuote = quote
        lastNotifiedPrice = quote.price
        viewState = .starting(previous: quote)
        render()
    }

    private func configureAPIKey() -> Bool {
        do {
            if let storedKey = try keychain.load(), !storedKey.isEmpty {
                configureCoordinator(apiKey: storedKey)
                return true
            }
        } catch {
            prompt.showError(error.localizedDescription)
            NSApp.terminate(nil)
            return false
        }

        while true {
            switch prompt.prompt(hasExistingKey: false, firstRun: true) {
            case let .save(key):
                if persistAPIKey(key) {
                    configureCoordinator(apiKey: key)
                    return true
                }
            case .cancel, .quit:
                NSApp.terminate(nil)
                return false
            }
        }
    }

    private func configureCoordinator(apiKey: String) {
        let coordinator = QuoteRefreshCoordinator(apiKey: apiKey, fetcher: client)
        coordinator.onEvent = { [weak self] event in
            self?.handle(event)
        }
        self.coordinator = coordinator
    }

    private func persistAPIKey(_ key: String) -> Bool {
        do {
            try keychain.save(key)
            return true
        } catch {
            prompt.showError(error.localizedDescription)
            return false
        }
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator?.refresh()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handle(_ event: QuoteRefreshCoordinator.Event) {
        switch event {
        case .started:
            viewState = .starting(previous: currentQuote)
        case let .succeeded(quote):
            currentQuote = quote
            quoteCache.save(quote)
            viewState = .available(quote)
            errorNotificationPolicy.reset()
            notifyPriceChange(quote)
        case let .failed(error):
            if let apiError = error as? GoldAPIError,
               apiError == .quoteUnavailable || apiError == .missingMarketData
            {
                fputs("AurumBar: \(apiError.localizedDescription)\n", stderr)
                viewState = .unavailable(previous: currentQuote)
                errorNotificationPolicy.reset()
            } else {
                handleFailure(error)
            }
        }
        render()
    }

    private func notifyPriceChange(_ quote: GoldQuote) {
        guard quote.price != lastNotifiedPrice else { return }
        let title = lastNotifiedPrice == nil ? "黄金价格" : "黄金价格更新"
        notifier.send(
            title: title,
            message: "\(quote.name)：\(quote.price) 元/克（\(quote.changePercent)）"
        )
        lastNotifiedPrice = quote.price
    }

    private func handleFailure(_ error: Error) {
        let message = error.localizedDescription
        fputs("AurumBar: 行情请求失败：\(message)\n", stderr)
        viewState = .failed(message: message, previous: currentQuote)

        if errorNotificationPolicy.shouldNotify(
            message: message,
            at: Date(),
            cooldown: Self.errorNotificationInterval
        ) {
            notifier.send(title: "黄金价格获取失败", message: message)
        }
    }

    private func render() {
        guard statusItem != nil else { return }
        let presentation = StatusPresentation.make(for: viewState)
        statusItem.button?.title = presentation.statusTitle
        statusItem.button?.toolTip = presentation.toolTip
        infoItem.title = presentation.infoTitle
        refreshItem.title = coordinator?.isRefreshing == true ? "刷新中…" : "立即刷新"
        refreshItem.isEnabled = coordinator?.isRefreshing != true
    }

    @objc private func refreshFromMenu() {
        coordinator?.refresh()
    }

    @objc private func showDetails() {
        NSApp.activate(ignoringOtherApps: true)
        let presentation = StatusPresentation.make(for: viewState)
        let alert = NSAlert()
        alert.messageText = "AurumBar 黄金监控"
        alert.alertStyle = presentation.isWarning ? .warning : .informational
        alert.informativeText = presentation.detailsText
        alert.runModal()
    }

    @objc private func changeAPIKey() {
        switch prompt.prompt(hasExistingKey: true, firstRun: false) {
        case let .save(key):
            if persistAPIKey(key) {
                coordinator?.replaceAPIKey(key)
            }
        case .cancel, .quit:
            break
        }
    }

    @objc private func openApplicationPage() {
        NSWorkspace.shared.open(AppKeyPrompt.applicationURL)
    }

    @objc private func stopRequested(_ notification: Notification) {
        quit()
    }

    @objc private func quit() {
        timer?.invalidate()
        coordinator?.cancel()
        NSApp.terminate(nil)
    }
}
