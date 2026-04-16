<div align="center">
  <h1>IINA+</h1>

  <p>
    <strong>A fork of IINA with DLNA casting support</strong>
  </p>

  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2010.15%2B-blue" alt="Platform">
    <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
    <img src="https://img.shields.io/badge/license-GPL--3.0-green" alt="License">
  </p>

  <p>
    <strong>English</strong> · <a href="./README.zh-CN.md">中文</a>
  </p>
</div>

---

### Introduction

**IINA+** is a fork of [IINA](https://github.com/iina/iina) — the modern video player for macOS. This fork adds **DLNA casting support**, allowing you to stream local media from your Mac to any DLNA/UPnP compatible device on your local network (smart TVs, speakers, etc.).

All original IINA features are preserved. Only DLNA casting has been added on top.

---

### New Features

#### DLNA Casting

![IINA+ Screenshot](https://i.imgur.com/YoFNUtD.png)

| Feature | Description |
|---------|-------------|
| **Device Discovery** | Automatically scans for DLNA/UPnP MediaRenderer devices on your local network via SSDP |
| **Media Casting** | Streams the currently playing local file to the selected device, resuming from the current position |
| **Playback Control** | Control the DLNA device directly from IINA+: play/pause, seek, volume, and mute |
| **Audio Track Switching** | Switch audio tracks while casting — IINA+ remuxes the file in the background using FFmpeg (lossless, no re-encoding) and resumes playback at the same position |
| **Casting UI** | A sidebar device picker and a fullscreen overlay showing the target device name |
| **Preferences** | Configure the local HTTP server port (default: 8765) and device discovery timeout (default: 10s) under **Preferences → Network** |

---

### Requirements

- macOS 10.15 (Catalina) or later
- A DLNA/UPnP MediaRenderer device on the same local network (smart TV, speaker, Kodi, etc.)

---

### Usage

1. Open a media file in IINA+.
2. Click the **Cast** button in the toolbar (or sidebar) to open the device picker.
3. Wait for devices to appear, then click a device to start casting.
4. Use the standard playback controls to control the DLNA device.
5. To switch audio tracks, use the Audio menu as usual — IINA+ handles the remux automatically.
6. Click **Stop Casting** in the sidebar to return to local playback.

---

### Configuration

Go to **Preferences → Network → Casting**:

| Setting | Default | Description |
|---------|---------|-------------|
| Local HTTP Port | `8765` | Port used by the built-in HTTP server that serves media files to the DLNA device |
| Discovery Timeout | `10s` | How long IINA+ scans for devices on the network |

---

### Building

Follow the original IINA build instructions:

```bash
./other/download_libs.sh   # Download pre-compiled mpv/FFmpeg dylibs
# Open iina.xcodeproj in Xcode and build
```

See the [original IINA README](https://github.com/iina/iina#build) for full details.

---

### Credits & Original Project

IINA+ is built on top of **IINA**, created by [@lhc70000](https://github.com/lhc70000) and the IINA community.

- Original project: [https://github.com/iina/iina](https://github.com/iina/iina)
- License: [GPL-3.0](LICENSE)

All credit for the core player goes to the IINA team.
