<div align="center">
  <h1>IINA+</h1>

  <p>
    <strong>基于 IINA 的 Fork，新增 DLNA 投屏功能</strong>
  </p>

  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2010.15%2B-blue" alt="平台">
    <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
    <img src="https://img.shields.io/badge/license-GPL--3.0-green" alt="许可证">
  </p>

  <p>
    <a href="./README.md">English</a> · <strong>中文</strong>
  </p>
</div>

---

### 简介

**IINA+** 是 [IINA](https://github.com/iina/iina) 的 Fork 版本。IINA 是一款现代化的 macOS 视频播放器。本 Fork 在原版基础上新增了 **DLNA 投屏功能**，让你可以将 Mac 上正在播放的本地媒体文件，通过局域网推流到任意 DLNA/UPnP 兼容设备（智能电视、音响等）。

原版 IINA 的所有功能完整保留，仅在此之上新增了 DLNA 投屏能力。

---

### 新增功能

#### DLNA 投屏

![IINA+ 截图](https://i.imgur.com/YoFNUtD.png)

| 功能 | 说明 |
|------|------|
| **设备发现** | 通过 SSDP 协议自动扫描局域网中的 DLNA/UPnP 媒体渲染设备 |
| **媒体投屏** | 将当前播放的本地文件推流到所选设备，从当前播放位置无缝开始 |
| **播放控制** | 直接通过 IINA+ 控制 DLNA 设备：播放/暂停、进度跳转、音量调节、静音 |
| **音轨切换** | 投屏时支持切换音轨 —— IINA+ 在后台使用 FFmpeg 无损重封装（不重新编码），切换完成后自动恢复到当前播放位置 |
| **投屏界面** | 侧边栏设备选择面板 + 投屏时的全屏覆盖层，显示目标设备名称 |
| **偏好设置** | 在**偏好设置 → 网络**中可配置本地 HTTP 服务端口（默认 8765）和设备扫描超时（默认 10 秒） |

---

### 系统要求

- macOS 10.15（Catalina）或更高版本
- 与 Mac 处于同一局域网的 DLNA/UPnP 媒体渲染设备（智能电视、音响、Kodi 等）

---

### 使用方法

1. 在 IINA+ 中打开一个媒体文件。
2. 点击工具栏（或侧边栏）中的**投屏按钮**，打开设备选择面板。
3. 等待设备列表出现后，点击目标设备开始投屏。
4. 使用播放器的常规控制按钮即可控制 DLNA 设备。
5. 如需切换音轨，通过音频菜单正常操作 —— IINA+ 会自动在后台完成重封装。
6. 点击侧边栏中的**停止投屏**即可回到本地播放模式。

---

### 配置说明

进入**偏好设置 → 网络 → 投屏**：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| 本地 HTTP 端口 | `8765` | 内置 HTTP 服务器的端口，用于向 DLNA 设备提供媒体文件访问 |
| 设备扫描超时 | `10 秒` | 扫描局域网设备时的等待时长 |

---

### 构建

请参照原版 IINA 的构建步骤：

```bash
./other/download_libs.sh   # 下载预编译的 mpv/FFmpeg 动态库
# 在 Xcode 中打开 iina.xcodeproj 并构建
```

完整说明请参考 [IINA 原项目 README](https://github.com/iina/iina#build)。

---

### 致谢与原项目

IINA+ 基于 **IINA** 开发，IINA 由 [@lhc70000](https://github.com/lhc70000) 及 IINA 社区创建。

- 原项目地址：[https://github.com/iina/iina](https://github.com/iina/iina)
- 开源协议：[GPL-3.0](LICENSE)

核心播放器的所有功劳归属于 IINA 团队。
