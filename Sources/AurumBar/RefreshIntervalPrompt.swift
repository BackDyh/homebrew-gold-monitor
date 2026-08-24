import AppKit
import AurumBarRuntime

enum RefreshIntervalPromptResult {
    case save(RefreshInterval)
    case cancel
}

final class RefreshIntervalPrompt {
    func prompt(current: RefreshInterval) -> RefreshIntervalPromptResult {
        while true {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "设置刷新间隔"
            alert.informativeText = "输入 1–1440 之间的整数，单位为分钟。保存后会重新计算下一次自动刷新时间；较短的间隔会更快消耗接口调用额度。"

            let field = NSTextField(
                frame: NSRect(x: 0, y: 0, width: 260, height: 24)
            )
            field.stringValue = String(current.minutes)
            field.placeholderString = "分钟"
            field.alignment = .right
            field.isEditable = true
            field.isSelectable = true
            alert.accessoryView = field
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "取消")
            alert.window.initialFirstResponder = field
            alert.window.makeFirstResponder(field)
            field.selectText(nil)

            guard alert.runModal() == .alertFirstButtonReturn else {
                return .cancel
            }
            guard let interval = RefreshInterval(minutesText: field.stringValue) else {
                showError("请输入 1–1440 之间的整数分钟数。")
                continue
            }
            return .save(interval)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "刷新间隔无效"
        alert.informativeText = message
        alert.runModal()
    }
}
