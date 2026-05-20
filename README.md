# Superpaste

[中文](#中文) | [English](#english)

## 中文

Superpaste 是一款轻量、纯本地运行的 macOS 剪贴板历史工具。它使用 SwiftUI + AppKit 构建，面向 macOS 14+，仅发布 Apple Silicon (`arm64`) 版本。

按下 `Shift-Command-V` 即可唤起底部剪贴板面板，用方向键切换最近记录，按 `Enter` 或数字键快速粘贴到刚才的输入框。

### 下载

- 最新版本：`v1.0.0`
- 安装包：[`Superpaste-v1.0.0-macOS-arm64.dmg`](https://github.com/ShuTianLe/superpaste/releases/download/v1.0.0/Superpaste-v1.0.0-macOS-arm64.dmg)
- 系统要求：macOS 14 或更新版本
- 芯片要求：Apple Silicon / arm64

### 1.0 功能

- 菜单栏常驻应用，无主窗口。
- 全局快捷键 `Shift-Command-V`。
- 全屏宽度底部候选面板，默认聚焦卡片，可用键盘切换。
- 支持文本、链接、富文本、HTML、文件、PDF、图片、颜色和通用剪贴板 payload。
- 可通过辅助功能权限直接粘贴到之前的输入框。
- 未开启辅助功能时自动退化为复制到剪贴板。
- 支持搜索、类型过滤、来源信息、删除、固定、Pinboard 和纯文本粘贴。
- 内置简体中文和英文界面，可在设置中切换。
- 图片内容使用 Apple Vision 做本地 OCR 索引。
- SQLite 保存元数据，payload 使用 AES-GCM 加密保存。
- 主密钥保存在本机 Keychain。
- 支持忽略应用、敏感正则规则、跳过 transient/concealed 剪贴板类型。
- 无账号、无同步、无遥测、无联网 SDK、无网络 entitlement。

### 安装与权限

1. 下载 DMG。
2. 将 `ClipShelf.app` 拖入 `/Applications`。
3. 从 `/Applications/ClipShelf.app` 启动。
4. 如需直接粘贴，请在系统设置中允许辅助功能权限。

如果刚刚打开辅助功能开关，请退出并重新启动应用，让 macOS 刷新权限状态。

### 开发构建

```bash
swift build -c release --arch arm64
```

构建 `.app`：

```bash
Scripts/build_app.sh
```

创建 DMG：

```bash
Scripts/make_dmg.sh
```

### 回归检查

```bash
swift build
swift build -c release --arch arm64
swift run ClipShelfCoreSmokeTests
Scripts/build_app.sh
Scripts/make_dmg.sh
Scripts/security_check.sh
codesign --verify --deep --strict --verbose=4 dist/ClipShelf.app
```

### 隐私

Superpaste 只在本机运行：

- 剪贴板数据保存在 `~/Library/Application Support/ClipShelf`。
- payload 文件使用 AES-GCM 加密。
- 主密钥保存在本机 Keychain。
- 应用不请求网络 entitlement。
- `Scripts/security_check.sh` 会检查是否误引入网络 API、framework 或 entitlement。

### 签名

默认构建脚本使用 ad-hoc 签名，方便本地测试。正式分发可传入 Developer ID 证书：

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" Scripts/build_app.sh
```

之后可使用 Apple `notarytool` 对 DMG 做 notarization。

### 版本

当前 1.0 版本对应 tag：`v1.0.0`。

### 许可证

暂未指定开源许可证。除非后续添加 LICENSE 文件，否则保留所有权利。

## English

Superpaste is a lightweight, local-only clipboard history app for macOS. It is built with SwiftUI + AppKit, targets macOS 14+, and ships Apple Silicon (`arm64`) builds only.

Press `Shift-Command-V` to open the bottom clipboard panel, browse recent clips with the arrow keys, then press `Enter` or a number key to paste the selected item into the previous input field.

### Download

- Latest version: `v1.0.0`
- Installer: [`Superpaste-v1.0.0-macOS-arm64.dmg`](https://github.com/ShuTianLe/superpaste/releases/download/v1.0.0/Superpaste-v1.0.0-macOS-arm64.dmg)
- System requirement: macOS 14 or newer
- Architecture: Apple Silicon / arm64

### 1.0 Highlights

- Menu bar app with no main window.
- Global `Shift-Command-V` hotkey.
- Full-width bottom clipboard panel with keyboard-first card selection.
- Recent clipboard history for text, links, rich text, HTML, files, PDFs, images, colors, and generic pasteboard payloads.
- Direct paste into the previous input field using macOS Accessibility permission.
- Copy-only fallback when Accessibility permission is not enabled.
- Search, type filters, source metadata, delete, pin, pinboard, and plain-text paste actions.
- Simplified Chinese and English UI, with an in-app language switch.
- Local OCR indexing for images through Apple Vision.
- SQLite metadata plus AES-GCM encrypted payload blobs.
- Keychain-backed encryption key.
- Ignored apps, sensitive regex rules, and transient/concealed pasteboard skipping.
- No account, no sync, no telemetry, no networking SDK, and no network entitlement.

### Installation and Permission

1. Download the DMG.
2. Drag `ClipShelf.app` into `/Applications`.
3. Launch `/Applications/ClipShelf.app`.
4. Enable Accessibility permission if you want direct paste.

If you just enabled the Accessibility switch, quit and relaunch the app so macOS refreshes the permission state.

### Build

```bash
swift build -c release --arch arm64
```

Build the `.app` bundle:

```bash
Scripts/build_app.sh
```

Create a DMG:

```bash
Scripts/make_dmg.sh
```

### Development Checks

```bash
swift build
swift build -c release --arch arm64
swift run ClipShelfCoreSmokeTests
Scripts/build_app.sh
Scripts/make_dmg.sh
Scripts/security_check.sh
codesign --verify --deep --strict --verbose=4 dist/ClipShelf.app
```

### Privacy

Superpaste is designed to run locally:

- Clipboard data is stored under `~/Library/Application Support/ClipShelf`.
- Payload files are encrypted with AES-GCM.
- The master key is stored in the local Keychain.
- The app does not request network entitlements.
- `Scripts/security_check.sh` guards against accidental networking APIs, frameworks, or entitlements.

### Signing

By default, `Scripts/build_app.sh` uses ad-hoc signing for local builds. For distribution, pass a Developer ID identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" Scripts/build_app.sh
```

Then notarize the DMG with Apple's `notarytool`.

### Version

The 1.0 release is tagged as `v1.0.0`.

### License

No open-source license has been specified yet. All rights reserved unless a LICENSE file is added.
