import AppKit

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--version") {
    print("AurumBar 0.1.0")
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    AurumBar - macOS 菜单栏 Au99.99 黄金价格监控

    用法：
      aurumbar              启动菜单栏监控
      aurumbar --version    显示版本
      aurumbar --reset-key  删除钥匙串中的 AppKey
    """)
    exit(0)
}

if arguments.contains("--reset-key") {
    KeychainStore().delete()
    print("已删除 AurumBar AppKey，下次启动会重新提示。")
    exit(0)
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
