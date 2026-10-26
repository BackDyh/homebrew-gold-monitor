import AppKit
import AurumBarCore
import AurumBarRuntime

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let errorNotificationInterval: TimeInterval = 60 * 60
    private static let wakeRefreshDelay: UInt64 = 5_000_000_000
    private static let nextRefreshFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private let client = GoldAPIClient()
    private let keyStore = AppKeyStore()
    private let prompt = AppKeyPrompt()
    private let notifier = AppleScriptNotifier()
    private let quoteCache = QuoteCache()
    private let refreshIntervalStore = RefreshIntervalStore()
    private let refreshIntervalPrompt = RefreshIntervalPrompt()
    private let schedule = TradingSchedule.shanghaiGold
    private let requestCounter = DailyRequestCounter()

    private var statusItem: NSStatusItem!
    private var infoItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var refreshIntervalItem: NSMenuItem!
    private var timer: Timer?
    private var nextRefreshDate: Date?
    private var lastSuccessDate: Date?
    private var quotaPausedUntil: Date?
    private var wakeRefreshTask: Task<Void, Never>?
    private var coordinator: QuoteRefreshCoordinator?
    private var currentQuote: GoldQuote?
    private var viewState: QuoteViewState = .starting(previous: nil)
    private var refreshInterval = RefreshInterval.defaultValue
    private var lastNotifiedPrice: String?
    private var errorNotificationPolicy = ErrorNotificationPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureRuntimeControl()
        configureApplicationMenu()
        refreshInterval = refreshIntervalStore.load()
        configureStatusItem()
        restoreCachedQuote()
        guard configureAPIKey() else { return }
        configureWakeObserver()
        scheduleRefresh()
        coordinator?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        wakeRefreshTask?.cancel()
        coordinator?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake(_ notification: Notification) {
        wakeRefreshTask?.cancel()
        wakeRefreshTask = Task { @MainActor [weak self] in
            // 刚唤醒时网络往往尚未就绪，立即请求容易 TLS 握手失败。
            try? await Task.sleep(nanoseconds: Self.wakeRefreshDelay)
            guard !Task.isCancelled, let self, self.coordinator != nil else { return }
            self.scheduleRefresh()
            let now = Date()
            guard !self.isQuotaPaused(at: now),
                  self.requestCounter.remainingAutomatic(on: now) > 0
            else {
                AurumBarLog.write("系统已唤醒，今日接口额度已用完，跳过刷新")
                return
            }
            guard RefreshPlanner.shouldRefreshOnResume(
                at: now,
                lastSuccess: self.lastSuccessDate,
                schedule: self.schedule
            ) else {
                AurumBarLog.write("系统已唤醒，休市中，跳过刷新")
                return
            }
            AurumBarLog.write("系统已唤醒，刷新行情")
            self.coordinator?.refresh()
        }
    }

    private func isQuotaPaused(at date: Date) -> Bool {
        quotaPausedUntil.map { date < $0 } ?? false
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

        refreshIntervalItem = NSMenuItem(
            title: refreshIntervalMenuTitle,
            action: #selector(changeRefreshInterval),
            keyEquivalent: ""
        )
        refreshIntervalItem.target = self
        menu.addItem(refreshIntervalItem)

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
            if let storedKey = try keyStore.load(), !storedKey.isEmpty {
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
            try keyStore.save(key)
            return true
        } catch {
            prompt.showError(error.localizedDescription)
            return false
        }
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        let now = Date()
        let fireDate: Date
        if let pausedUntil = quotaPausedUntil, now < pausedUntil {
            fireDate = RefreshPlanner.firstRefresh(atOrAfter: pausedUntil, schedule: schedule)
        } else {
            fireDate = RefreshPlanner.nextRefresh(
                after: now,
                interval: refreshInterval,
                remainingRequests: requestCounter.remainingAutomatic(on: now),
                schedule: schedule
            )
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.requestCounter.remainingAutomatic() > 0 {
                    self.coordinator?.refresh()
                }
                self.scheduleRefresh()
            }
        }
        timer.tolerance = min(60, refreshInterval.timeInterval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        nextRefreshDate = fireDate
        if let nextRefreshText {
            AurumBarLog.write("下次自动刷新：\(nextRefreshText)")
        }
        render()
    }

    private func pauseForQuota() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        )!
        guard quotaPausedUntil != tomorrow else { return }
        quotaPausedUntil = tomorrow
        scheduleRefresh()
    }

    private func handle(_ event: QuoteRefreshCoordinator.Event) {
        switch event {
        case .started:
            requestCounter.record()
            viewState = .starting(previous: currentQuote)
        case let .succeeded(quote):
            currentQuote = quote
            quoteCache.save(quote)
            viewState = .available(quote)
            lastSuccessDate = Date()
            errorNotificationPolicy.reset()
            notifyPriceChange(quote)
            if quotaPausedUntil != nil {
                quotaPausedUntil = nil
                scheduleRefresh()
            }
        case let .failed(error):
            if error as? GoldAPIError == .quotaExceeded {
                handleFailure(error)
                pauseForQuota()
            } else if let apiError = error as? GoldAPIError,
               apiError == .quoteUnavailable || apiError == .missingMarketData
            {
                AurumBarLog.write(apiError.localizedDescription)
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
        AurumBarLog.write("行情请求失败：\(message)")
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
        let presentation = StatusPresentation.make(
            for: viewState,
            refreshInterval: refreshInterval,
            nextRefreshText: nextRefreshText,
            usageText: "\(requestCounter.count())/\(requestCounter.dailyLimit) 次"
        )
        statusItem.button?.title = presentation.statusTitle
        statusItem.button?.toolTip = presentation.toolTip
        infoItem.title = presentation.infoTitle
        refreshItem.title = coordinator?.isRefreshing == true ? "刷新中…" : "立即刷新"
        refreshItem.isEnabled = coordinator?.isRefreshing != true
        refreshIntervalItem.title = refreshIntervalMenuTitle
    }

    private var nextRefreshText: String? {
        guard let nextRefreshDate else { return nil }
        let time = Self.nextRefreshFormatter.string(from: nextRefreshDate)
        if isQuotaPaused(at: Date()) || requestCounter.remainingAutomatic() == 0 {
            return "\(time)（今日接口额度已用完）"
        }
        return schedule.isOpen(at: Date()) ? time : "\(time)（休市中）"
    }

    private var refreshIntervalMenuTitle: String {
        "刷新间隔：\(refreshInterval.displayText)…"
    }

    @objc private func refreshFromMenu() {
        coordinator?.refresh()
    }

    @objc private func showDetails() {
        NSApp.activate(ignoringOtherApps: true)
        let presentation = StatusPresentation.make(
            for: viewState,
            refreshInterval: refreshInterval
        )
        let alert = NSAlert()
        alert.messageText = "AurumBar 黄金监控"
        alert.alertStyle = presentation.isWarning ? .warning : .informational
        alert.informativeText = presentation.detailsText
        alert.runModal()
    }

    @objc private func changeRefreshInterval() {
        guard case let .save(interval) = refreshIntervalPrompt.prompt(
            current: refreshInterval
        ) else {
            return
        }

        refreshInterval = interval
        refreshIntervalStore.save(interval)
        if coordinator != nil {
            scheduleRefresh()
        }
        render()
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
        wakeRefreshTask?.cancel()
        coordinator?.cancel()
        NSApp.terminate(nil)
    }
}
