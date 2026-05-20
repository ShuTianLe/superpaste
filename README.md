# Superpaste

[中文](#中文) | [English](#english)

## 中文

Superpaste 是一款轻量、纯本地运行的 macOS 剪贴板历史工具。它使用 SwiftUI + AppKit 构建，面向 macOS 14+，仅支持 Apple Silicon (`arm64`)。

按 `Shift-Command-V` 唤起底部剪贴板面板，用方向键切换记录，按 `Enter` 或数字键粘贴到刚才的输入框。

### 功能

- 菜单栏常驻，无主窗口。
- 全局快捷键 `Shift-Command-V`。
- 全屏宽度底部候选面板，默认聚焦卡片。
- 支持文本、链接、富文本、HTML、文件、PDF、图片、颜色和通用剪贴板 payload。
- 支持搜索、类型过滤、来源信息、删除、固定、Pinboard 和纯文本粘贴。
- 支持辅助功能权限下的直接粘贴；未授权时退化为复制到剪贴板。
- 简体中文和英文界面，可在设置中切换。
- 图片内容使用 Apple Vision 做本地 OCR 索引。
- SQLite 元数据，AES-GCM 加密 payload，本机 Keychain 保存主密钥。
- 可忽略应用、匹配敏感正则，并跳过 transient/concealed 剪贴板类型。
- 无账号、无同步、无遥测、无联网 SDK、无网络 entitlement。

### 要求

- macOS 14 或更新版本
- Apple Silicon Mac
- 直接粘贴需要辅助功能权限

### 构建

```bash
swift build -c release --arch arm64
Scripts/build_app.sh
Scripts/make_dmg.sh
```

### 检查

```bash
swift build
swift build -c release --arch arm64
swift run ClipShelfCoreSmokeTests
Scripts/security_check.sh
```

### 权限

直接粘贴需要 macOS 辅助功能权限。开启权限后如果状态没有立即刷新，请退出并重新启动应用。

### 隐私

剪贴板数据保存在 `~/Library/Application Support/ClipShelf`。payload 使用 AES-GCM 加密，主密钥保存在本机 Keychain。应用不请求网络 entitlement。

### 签名

默认构建脚本使用 ad-hoc 签名。正式分发可传入 Developer ID 证书：

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" Scripts/build_app.sh
```

## English

Superpaste is a lightweight, local-only clipboard history app for macOS. It is built with SwiftUI + AppKit, targets macOS 14+, and supports Apple Silicon (`arm64`) only.

Press `Shift-Command-V` to open the bottom clipboard panel, switch clips with the arrow keys, then press `Enter` or a number key to paste into the previous input field.

### Features

- Menu bar app with no main window.
- Global `Shift-Command-V` hotkey.
- Full-width bottom clipboard panel with card-first focus.
- Clipboard history for text, links, rich text, HTML, files, PDFs, images, colors, and generic pasteboard payloads.
- Search, type filters, source metadata, delete, pin, Pinboard, and plain-text paste actions.
- Direct paste with Accessibility permission; copy-only fallback without permission.
- Simplified Chinese and English UI with an in-app language switch.
- Local OCR indexing for images through Apple Vision.
- SQLite metadata, AES-GCM encrypted payloads, and a Keychain-backed master key.
- Ignored apps, sensitive regex rules, and transient/concealed pasteboard skipping.
- No account, no sync, no telemetry, no networking SDK, and no network entitlement.

### Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Accessibility permission for direct paste

### Build

```bash
swift build -c release --arch arm64
Scripts/build_app.sh
Scripts/make_dmg.sh
```

### Checks

```bash
swift build
swift build -c release --arch arm64
swift run ClipShelfCoreSmokeTests
Scripts/security_check.sh
```

### Permission

Direct paste requires macOS Accessibility permission. If the permission state does not refresh immediately after enabling it, quit and relaunch the app.

### Privacy

Clipboard data is stored under `~/Library/Application Support/ClipShelf`. Payloads are encrypted with AES-GCM, and the master key is stored in the local Keychain. The app does not request network entitlements.

### Signing

Local builds use ad-hoc signing by default. For distribution, pass a Developer ID identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" Scripts/build_app.sh
```
