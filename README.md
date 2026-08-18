# AurumBar

<p align="center">
  <strong>在 macOS 菜单栏中，安静地关注 Au99.99 黄金价格。</strong>
</p>

<p align="center">
  <a href="https://github.com/BackDyh/homebrew-gold-monitor/actions/workflows/swift.yml"><img src="https://github.com/BackDyh/homebrew-gold-monitor/actions/workflows/swift.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

AurumBar 是一个轻量的原生 macOS 菜单栏应用，用于查看上海黄金交易所 **Au99.99** 的最新价格。它由 Swift 和 AppKit 构建，没有第三方运行时依赖，不占用 Dock，也不会加入额外的分析或遥测服务。

> 名字来自拉丁语 *Aurum*（黄金）与 macOS 菜单栏 *Bar*。

## 功能

- 在菜单栏直接显示最新价格
- 每 30 分钟自动刷新，也可随时手动刷新
- 价格变化时发送 macOS 系统通知
- 网络临时异常时进行有限重试
- 无新行情时继续显示最后一次有效价格
- 自动适配 macOS 明暗外观
- AppKey 存储在 macOS 钥匙串中
- 支持 Apple Silicon 与 Intel Mac

## 系统要求

- macOS 13 Ventura 或更高版本
- 一个聚合数据的个人 AppKey
  - 数据接口：[黄金数据（接口 ID 29）](https://www.juhe.cn/docs/api/id/29)

## 安装

### Homebrew

```bash
brew tap BackDyh/gold-monitor
brew install aurumbar
brew services start aurumbar
```

`brew services start` 会让 AurumBar 在登录后自动启动。

如果不需要登录启动，可以手动运行：

```bash
aurumbar start
```

### 从源码运行

```bash
git clone https://github.com/BackDyh/homebrew-gold-monitor.git
cd homebrew-gold-monitor
swift run aurumbar run
```

构建项目需要 Xcode Command Line Tools：

```bash
xcode-select --install
```

## 首次使用

首次启动时，AurumBar 会提示输入聚合数据 AppKey：

1. 打开[黄金数据接口页面](https://www.juhe.cn/docs/api/id/29)并申请 AppKey。
2. 将 AppKey 粘贴到 AurumBar 的安全输入框中。
3. 保存后，AurumBar 会立即获取行情并显示在菜单栏。

之后可以从菜单栏选择“设置个人 AppKey…”来更换凭据。已有 AppKey 不会显示在输入框中。

## 使用

点击菜单栏价格可以：

- 查看价格、涨跌幅和行情时间
- 立即刷新行情
- 查看当前状态和最近一次错误
- 更换 AppKey
- 打开 AppKey 申请页面
- 退出 AurumBar

常用命令：

```bash
# 查看版本
aurumbar --version

# 启动或停止手动后台实例
aurumbar start
aurumbar stop

# 删除钥匙串中的 AppKey
aurumbar --reset-key

# 管理登录启动服务
brew services start aurumbar
brew services stop aurumbar
```

## 日志与故障排查

手动运行 `aurumbar start` 时：

```bash
tail -f ~/Library/Logs/AurumBar/aurumbar.log
```

通过 Homebrew Services 运行时：

```bash
tail -f "$(brew --prefix)/var/log/aurumbar.log"
```

如果菜单栏没有出现：

```bash
aurumbar stop
aurumbar start
```

如果 AppKey 失效或需要重新配置：

```bash
aurumbar --reset-key
aurumbar start
```

AurumBar 不会主动将 AppKey 或完整请求 URL 写入日志。提交 issue 前仍建议检查日志中是否包含不希望公开的信息。

## 隐私

- AppKey 保存在 macOS Keychain 中，不写入源码、行情缓存或应用日志。
- 请求行情时，AppKey 会按照上游接口要求，通过 HTTPS 发送给聚合数据服务。
- 最后一次有效行情仅保存在本机，用于离线或接口暂时无数据时继续展示。
- 项目不包含自建账号系统、使用分析、广告 SDK 或崩溃上报服务。
- `aurumbar --reset-key` 只删除 AppKey，不会删除本地行情缓存和日志。

## 开发

克隆仓库并构建：

```bash
git clone https://github.com/BackDyh/homebrew-gold-monitor.git
cd homebrew-gold-monitor
swift build
```

运行应用：

```bash
swift run aurumbar run
```

运行测试需要完整 Xcode：

```bash
swift test
```

主要模块：

```text
Sources/AurumBarCore      行情模型、响应解析和 API 客户端
Sources/AurumBarRuntime   刷新协调、状态呈现、Keychain 和单实例控制
Sources/AurumBar          AppKit 菜单栏应用与命令行入口
Tests                     核心逻辑和运行时测试
```

## 参与贡献

欢迎提交 issue 和 pull request。

提交修复或功能前，请尽量：

1. 说明问题、预期行为和复现方式。
2. 为新增逻辑补充测试。
3. 运行 `swift test` 和 `swift build -c release --product aurumbar`。
4. 不要在代码、日志、截图或测试数据中提交真实 AppKey。

对于较大的功能，建议先创建 issue 讨论设计方向。

## 数据与免责声明

行情数据来自[聚合数据黄金接口](https://www.juhe.cn/docs/api/id/29)。本项目提供的信息仅供个人学习与参考，不保证实时性、准确性或完整性，也不构成投资建议。

## License

AurumBar 使用 [MIT License](LICENSE) 开源。
