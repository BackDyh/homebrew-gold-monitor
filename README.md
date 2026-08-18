# AurumBar

AurumBar 是一个原生 macOS 菜单栏 Au99.99 黄金价格监控工具。名字来自拉丁语 `Aurum`（黄金）和 macOS 菜单栏 `Bar`。

## 特性

- 原生 Swift/AppKit 实现。
- 菜单栏清晰显示价格并自动适配明暗外观。
- 默认每 30 分钟刷新，价格变化时发送系统通知。
- 网络异常时进行有限重试，不对空行情重复消耗 API 次数。
- 跨启动保留最后一次有效价格。
- AppKey 保存在 macOS 钥匙串，不写入源码、行情缓存或日志。

## 通过 Homebrew 安装

添加 Homebrew Tap 并安装当前稳定版：

```bash
brew tap BackDyh/gold-monitor
brew install aurumbar
brew services start aurumbar
```

如果只想静默地在后台运行、不设置登录启动：

```bash
aurumbar start
```

第一次启动会弹出 AppKey 引导。点击“打开申请页面”，申请聚合数据的“黄金数据”（接口 ID 29），复制个人 AppKey 后保存即可。

## 常用命令

```bash
# 查看版本
aurumbar --version

# 删除钥匙串中的 AppKey，下次启动重新提示
aurumbar --reset-key

# 启动、停止当前运行的监控
aurumbar start
aurumbar stop

# 查看 aurumbar start 的后台日志
tail -f ~/Library/Logs/AurumBar/aurumbar.log

# 启动、停止登录项
brew services start aurumbar
brew services stop aurumbar

# 查看 brew services 的日志
tail -f "$(brew --prefix)/var/log/aurumbar.log"

# 卸载
brew uninstall aurumbar
```

日志以追加方式写入，目前不会自动轮转。AurumBar 不主动记录 AppKey 或完整请求 URL；分享日志前仍建议人工检查内容。

## 从源码开发

要求 macOS 13 或更高版本。构建应用可使用 Xcode Command Line Tools；运行 Swift Testing 测试套件需要完整 Xcode（CI 也使用完整 Xcode）。

```bash
# 完整 Xcode 环境
swift test

# 仅构建/运行应用时，Command Line Tools 即可
swift run aurumbar run
```

生成未签名的 arm64/x86_64 通用候选包：

```bash
scripts/build-release.sh 0.1.3 --allow-dirty --signing unsigned
```

脚本会在 `.build/release-artifacts/` 下生成 tarball、SHA-256 和 manifest，并自动运行 `scripts/verify-release.sh`。它不会创建 tag、GitHub Release 或修改 Formula。

`developer-id` 模式是显式可选项，需要设置 `AURUMBAR_CODESIGN_IDENTITY` 和已配置的 `AURUMBAR_NOTARY_PROFILE`。带 Apple 时间戳的签名产物不承诺逐字节可复现；裸 tarball 也不宣称已 staple 公证票据。

## 隐私与本地数据

- AppKey 保存在 macOS Keychain，service 为 `com.back.aurumbar`。
- 请求上游行情时，AppKey 会按聚合数据接口要求作为 HTTPS query 参数发送；服务方仍可看到请求所需的 AppKey、IP 和请求时间。
- 最近一次有效行情保存在本机 `com.back.aurumbar` UserDefaults，不包含 AppKey。
- `aurumbar start` 会创建 `~/Library/Application Support/AurumBar/aurumbar.lock` 和本地日志。
- 系统通知由本机 `/usr/bin/osascript` 发送。
- AurumBar 没有自建账户、分析遥测或崩溃上报。
- `aurumbar --reset-key` 只删除 Keychain 中的 AppKey，不会清理行情缓存或日志。

## 发布流程

源码版本可以在发布准备期间领先于 Homebrew 稳定版。当前 Formula 必须持续指向已经公开且可下载的版本，不能提前引用不存在的 Release：

1. 合并代码并让测试、universal candidate 和稳定 Formula CI 全部通过。
2. 通过 `release-candidate` workflow 或本地脚本生成候选包，审核架构、manifest、SHA 和签名状态。
3. 人工创建并推送版本 tag，创建 GitHub Release，上传审核过的同一份候选资产。
4. 从公开 Release URL 重新下载资产并再次验证 SHA。
5. 使用远端资产的实际 SHA 单独更新 Formula URL、checksum 和预编译安装逻辑。
6. 在 Apple Silicon 和 Intel 环境执行 `brew fetch`、`brew install` 和 `brew test` 后再发布 Formula 更新。

## 数据说明

行情来自聚合数据黄金接口，仅供个人学习和参考，不构成投资建议。
