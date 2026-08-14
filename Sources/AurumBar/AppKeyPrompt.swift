import AppKit

enum AppKeyPromptResult {
    case save(String)
    case cancel
    case quit
}

final class AppKeyPrompt {
    static let applicationURL = URL(
        string: "https://www.juhe.cn/docs/api/id/29"
    )!

    func prompt(existingKey: String?, firstRun: Bool) -> AppKeyPromptResult {
        while true {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = firstRun ? "欢迎使用 AurumBar" : "设置个人 AppKey"
            alert.informativeText = firstRun
                ? "首次启动需要你自己的聚合数据 AppKey。点击“打开申请页面”申请黄金数据（接口 ID 29），复制 AppKey 后粘贴到下方。Key 只保存在本机钥匙串。"
                : "粘贴新的聚合数据黄金接口 AppKey。保存后会立即刷新。"

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
            field.placeholderString = "粘贴个人 AppKey"
            field.stringValue = existingKey ?? ""
            alert.accessoryView = field
            alert.addButton(withTitle: "保存并启动")
            alert.addButton(withTitle: "打开申请页面")
            alert.addButton(withTitle: firstRun ? "退出" : "取消")
            alert.window.initialFirstResponder = field

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let key = field.stringValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !key.isEmpty else {
                    showError("请先粘贴个人 AppKey。")
                    continue
                }
                return .save(key)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(Self.applicationURL)
                continue
            default:
                return firstRun ? .quit : .cancel
            }
        }
    }

    func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AurumBar"
        alert.informativeText = message
        alert.runModal()
    }
}
