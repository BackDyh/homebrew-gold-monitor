import AppKit

public enum AppKeyPromptResult {
    case save(String)
    case cancel
    case quit
}

public final class AppKeyPrompt {
    public static let applicationURL = URL(
        string: "https://www.juhe.cn/docs/api/id/29"
    )!

    public init() {}

    public func prompt(hasExistingKey: Bool, firstRun: Bool) -> AppKeyPromptResult {
        while true {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = firstRun ? "欢迎使用 AurumBar" : "设置个人 AppKey"
            alert.informativeText = firstRun
                ? "首次启动需要你自己的聚合数据 AppKey。点击“打开申请页面”申请黄金数据（接口 ID 29），复制 AppKey 后粘贴到下方。Key 只保存在本机钥匙串。"
                : "输入新的聚合数据黄金接口 AppKey。取消会保留当前 AppKey，保存后会立即刷新。"

            let field = NSSecureTextField(
                frame: NSRect(x: 0, y: 0, width: 360, height: 24)
            )
            field.placeholderString = hasExistingKey ? "输入新的 AppKey" : "粘贴个人 AppKey"
            field.isEditable = true
            field.isSelectable = true

            let fieldMenu = NSMenu()
            fieldMenu.addItem(
                withTitle: "粘贴",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: ""
            )
            field.menu = fieldMenu
            alert.accessoryView = field
            alert.addButton(withTitle: firstRun ? "保存并启动" : "保存并刷新")
            alert.addButton(withTitle: "打开申请页面")
            alert.addButton(withTitle: firstRun ? "退出" : "取消")
            alert.window.initialFirstResponder = field
            alert.window.makeFirstResponder(field)

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let key = field.stringValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !key.isEmpty else {
                    showError("请先粘贴个人 AppKey。")
                    continue
                }
                guard key.count <= 512,
                      key.rangeOfCharacter(from: .controlCharacters) == nil
                else {
                    showError("AppKey 格式无效，请检查后重试。")
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

    public func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AurumBar"
        alert.informativeText = message
        alert.runModal()
    }
}
