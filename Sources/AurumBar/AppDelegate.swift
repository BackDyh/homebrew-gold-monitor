import AppKit
import AurumBarCore

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
    private var apiKey = ""
    private var currentQuote: GoldQuote?
    private var lastError: String?
    private var quoteUnavailable = false
    private var lastNotifiedPrice: String?
    private var lastErrorMessage: String?
    private var lastErrorNotificationDate: Date?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard RuntimeControl.claimCurrentProcess() else {
            fputs("AurumBar: 已有一个实例在运行\n", stderr)
            NSApp.terminate(nil)
            return
        }
        configureRuntimeControl()
        configureApplicationMenu()
        configureStatusItem()
        restoreCachedQuote()
        guard configureAPIKey() else { return }
        scheduleRefresh()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RuntimeControl.clearCurrentProcess()
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
        // 菜单栏后台应用默认没有“编辑”菜单，导致 NSTextField 收不到 ⌘V。
        // 即使应用菜单不可见，标准 action 仍会沿响应链发送给当前输入框。
        let mainMenu = NSMenu()
        let editRootItem = NSMenuItem(
            title: "编辑",
            action: nil,
            keyEquivalent: ""
        )
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
            button.title = "Au —"
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            button.toolTip = "AurumBar 正在启动"
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
    }

    private func restoreCachedQuote() {
        guard let quote = quoteCache.load() else { return }
        currentQuote = quote
        lastNotifiedPrice = quote.price
        statusItem.button?.title = formatMenuPrice(quote.price)
        statusItem.button?.toolTip = "上次有效行情：\(quote.price) 元/克（\(quote.sourceTime)）"
        infoItem.title = "\(quote.price) 元/克（上次有效行情）"
    }

    private func configureAPIKey() -> Bool {
        if let storedKey = keychain.load(), !storedKey.isEmpty {
            apiKey = storedKey
            return true
        }

        switch prompt.prompt(existingKey: nil, firstRun: true) {
        case let .save(key):
            return persistAPIKey(key)
        case .cancel, .quit:
            NSApp.terminate(nil)
            return false
        }
    }

    private func persistAPIKey(_ key: String) -> Bool {
        do {
            try keychain.save(key)
            apiKey = key
            return true
        } catch {
            prompt.showError(error.localizedDescription)
            return false
        }
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard !apiKey.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        refreshItem.title = "刷新中…"
        refreshItem.isEnabled = false

        client.fetch(apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            self.refreshItem.title = "立即刷新"
            self.refreshItem.isEnabled = true

            switch result {
            case let .success(quote):
                self.handleSuccess(quote)
            case let .failure(error):
                self.handleFailure(error)
            }
        }
    }

    private func handleSuccess(_ quote: GoldQuote) {
        currentQuote = quote
        lastError = nil
        quoteUnavailable = false
        quoteCache.save(quote)

        let menuPrice = formatMenuPrice(quote.price)
        statusItem.button?.title = menuPrice
        statusItem.button?.toolTip = "\(quote.name)：\(quote.price) 元/克（\(quote.changePercent)）"
        infoItem.title = "\(quote.price) 元/克  \(quote.changePercent)"

        guard quote.price != lastNotifiedPrice else { return }
        let title = lastNotifiedPrice == nil ? "黄金价格" : "黄金价格更新"
        notifier.send(
            title: title,
            message: "\(quote.name)：\(quote.price) 元/克（\(quote.changePercent)）"
        )
        lastNotifiedPrice = quote.price
    }

    private func handleFailure(_ error: Error) {
        if let apiError = error as? GoldAPIError {
            if apiError == .quoteUnavailable || apiError == .missingMarketData {
                handleQuoteUnavailable(apiError.localizedDescription)
                return
            }
        }

        let message = error.localizedDescription
        fputs("AurumBar: 行情请求失败：\(message)\n", stderr)
        lastError = message
        quoteUnavailable = false
        if currentQuote == nil {
            statusItem.button?.title = "Au —"
            infoItem.title = "获取失败：\(message)"
        } else {
            infoItem.title = "最近一次刷新失败"
        }

        let now = Date()
        let cooldownElapsed = lastErrorNotificationDate.map {
            now.timeIntervalSince($0) >= Self.errorNotificationInterval
        } ?? true
        if message != lastErrorMessage || cooldownElapsed {
            notifier.send(title: "黄金价格获取失败", message: message)
            lastErrorMessage = message
            lastErrorNotificationDate = now
        }
    }

    private func handleQuoteUnavailable(_ reason: String) {
        fputs("AurumBar: \(reason)\n", stderr)
        lastError = nil
        quoteUnavailable = true

        if let quote = currentQuote {
            statusItem.button?.toolTip = "暂无新行情，显示上次有效价格：\(quote.price) 元/克"
            infoItem.title = "\(quote.price) 元/克（上次有效行情）"
        } else {
            statusItem.button?.title = "Au —"
            statusItem.button?.toolTip = "接口暂时没有返回有效行情"
            infoItem.title = "暂时没有可用行情"
        }
    }

    private func formatMenuPrice(_ price: String) -> String {
        guard let number = Double(price) else { return "Au —" }
        return String(format: "%.1f", number)
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func showDetails() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AurumBar 黄金监控"
        alert.alertStyle = lastError == nil ? .informational : .warning

        if let quote = currentQuote {
            var lines = [
                "\(quote.name)：\(quote.price) 元/克",
                "涨跌幅：\(quote.changePercent)",
                "行情时间：\(quote.sourceTime)",
                "自动刷新：每 30 分钟",
            ]
            if let lastError {
                lines.append("最近错误：\(lastError)")
            } else if quoteUnavailable {
                lines.append("当前状态：暂无新行情，显示上次有效价格")
            } else {
                lines.append("当前状态：正常")
            }
            alert.informativeText = lines.joined(separator: "\n")
        } else {
            alert.informativeText = quoteUnavailable
                ? "接口暂时没有返回有效行情"
                : lastError ?? "尚未获取到有效行情"
        }
        alert.runModal()
    }

    @objc private func changeAPIKey() {
        switch prompt.prompt(existingKey: apiKey, firstRun: false) {
        case let .save(key):
            if persistAPIKey(key) {
                refresh()
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
        NSApp.terminate(nil)
    }
}
