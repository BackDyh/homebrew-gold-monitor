# AurumBar

AurumBar 是一个原生 macOS 菜单栏 Au99.99 黄金价格监控工具。名字来自拉丁语 `Aurum`（黄金）和 macOS 菜单栏 `Bar`。

## 特性

- 原生 Swift/AppKit 实现。
- 菜单栏清晰显示价格并自动适配明暗外观。
- 默认每 30 分钟刷新，价格变化时发送系统通知。
- AppKey 只保存在 macOS 钥匙串，不写入源码或配置文件。

## 通过 Homebrew 安装

添加 Homebrew Tap 并安装 AurumBar：

```bash
brew tap BackDyh/gold-monitor
brew install aurumbar
brew services start aurumbar
```

如果只想本次运行、不设置登录启动：

```bash
aurumbar
```

第一次启动会弹出 AppKey 引导。点击“打开申请页面”，申请聚合数据的“黄金数据”（接口 ID 29），复制个人 AppKey 后保存即可。

## 常用命令

```bash
# 查看版本
aurumbar --version

# 删除钥匙串中的 AppKey，下次启动重新提示
aurumbar --reset-key

# 启动、停止登录项
brew services start aurumbar
brew services stop aurumbar

# 卸载
brew uninstall aurumbar
```

## 从源码开发

要求 macOS 13 或更高版本，并安装 Xcode Command Line Tools。

```bash
swift run aurumbar-checks
swift run aurumbar
```

## 数据说明

行情来自聚合数据黄金接口，仅供个人学习和参考，不构成投资建议。
