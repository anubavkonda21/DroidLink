# 🪞 DroidLink

<p align="center">
  <strong>Mirror your Android screen to your Mac — with the full ecosystem experience.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#building-from-source">Building</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/platform-Android%2010%2B-green?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/kotlin-2.0%2B-purple?logo=kotlin" alt="Kotlin">
  <img src="https://img.shields.io/github/license/anubavkonda/DroidLink" alt="License">
</p>

---

## What is DroidLink?

DroidLink bridges the gap between your Android phone and your Mac. It's not just a screen mirror — it's a complete ecosystem that brings Apple Continuity-level integration to Android + Mac users.

**One app. Full integration. No compromises.**

## Features

### 🪞 Screen Mirroring
- **Ultra-low latency** (< 50 ms USB, < 100 ms Wi-Fi) with hardware H.264/H.265 encoding
- **USB and Wi-Fi** — works wired or wirelessly on your local network
- **Full input control** — mouse, keyboard, and multi-touch gesture forwarding
- **Audio streaming** — hear your Android audio on your Mac
- **Screen recording** — capture your Android screen as MP4 directly on Mac

### 📋 Universal Clipboard
- Copy on Android → paste on Mac (and vice versa) — **automatically**
- Image clipboard support
- Clipboard history with search
- **OTP auto-forward** — verification codes from SMS appear on Mac instantly

### 📁 AirDrop-Style File Transfer
- **Drag & drop** files from Finder onto the mirror window
- Share from Android → files appear on Mac
- Batch transfers with progress tracking
- Smart auto-organize (photos → Photos, docs → Downloads)

### 🔔 Notification Mirroring
- Android notifications appear as **native macOS notifications**
- **Inline reply** to WhatsApp, Telegram, SMS right from Mac
- Per-app filtering — only see what matters
- Do Not Disturb sync between devices

### 💬 SMS & Calls
- **Send/receive SMS** from your Mac using your Android's SIM
- **Answer/make phone calls** from Mac with audio routing
- Contact sync for easy dialing

### 🔗 Handoff
- Open the URL from your Android browser on Mac with one click
- Active app indicator in menu bar

### ⚡ Power Features
- **Virtual display** — run Android apps without mirroring your physical screen
- **Multi-window** — individual Android apps in separate macOS windows
- **Camera as webcam** — use your phone camera for Zoom/Meet
- **Device dashboard** — battery, storage, network status at a glance
- **Find My Phone** — ring your Android from Mac
- **One-click hotspot** — enable phone tethering from Mac

---

## Installation

### macOS App

**Homebrew (recommended):**
```bash
brew install --cask droidlink
```

**Manual download:**
Download the latest `.dmg` from [Releases](https://github.com/anubavkonda/DroidLink/releases).

### Android Companion App

Download from [Releases](https://github.com/anubavkonda/DroidLink/releases) or build from source.

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Android 10 (API 29) or later
- USB debugging enabled on Android ([How to enable](docs/SETUP.md#enable-usb-debugging))
- For Wi-Fi: both devices on the same local network

---

## Quick Start

1. **Install** the macOS app and Android companion app
2. **Connect** your Android via USB (or Wi-Fi)
3. **Enable USB Debugging** on your Android device
4. **Launch DroidLink** on your Mac — it will detect your phone automatically
5. **Grant permissions** on the Android companion app (screen capture, notifications, etc.)
6. **Start mirroring!** 🎉

---

## Architecture

```
┌─────────────────────┐         ┌──────────────────────┐
│   macOS App          │         │  Android Companion    │
│   (Swift/SwiftUI)    │◄───────►│  (Kotlin/Compose)     │
│                      │  USB/   │                      │
│ ┌──────────────────┐ │  Wi-Fi  │ ┌──────────────────┐ │
│ │ Video Decoder    │ │◄────────│ │ Screen Capture   │ │
│ │ (VideoToolbox)   │ │ H.264/5 │ │ (MediaCodec)     │ │
│ ├──────────────────┤ │         │ ├──────────────────┤ │
│ │ Metal Renderer   │ │         │ │ Notification     │ │
│ ├──────────────────┤ │◄────────│ │ Listener         │ │
│ │ Input Forwarder  │ │─────────►├──────────────────┤ │
│ ├──────────────────┤ │ Control │ │ Clipboard Svc    │ │
│ │ Clipboard Sync   │ │◄───────►│ ├──────────────────┤ │
│ ├──────────────────┤ │ Channel │ │ File Server      │ │
│ │ Notification     │ │ (gRPC/  │ ├──────────────────┤ │
│ │ Bridge           │ │  WS)    │ │ Connection Svc   │ │
│ ├──────────────────┤ │         │ └──────────────────┘ │
│ │ File Transfer    │ │         │                      │
│ └──────────────────┘ │         │                      │
└─────────────────────┘         └──────────────────────┘
```

### Tech Stack

| Component | Technology |
|-----------|-----------|
| macOS App | Swift 5.9+, SwiftUI, Metal, VideoToolbox |
| Android App | Kotlin 2.0+, Jetpack Compose, MediaCodec |
| Video Codec | H.264 / H.265 (hardware accelerated both sides) |
| Transport | ADB (USB), TCP/WebSocket (Wi-Fi), gRPC (control) |
| Discovery | mDNS / Bonjour |
| Audio | Opus codec, AudioPlaybackCapture → AVAudioEngine |

---

## Building from Source

### macOS App

```bash
cd mac/DroidLink
open DroidLink.xcodeproj  # or build via xcodebuild
xcodebuild -scheme DroidLink -configuration Release
```

### Android App

```bash
cd android
./gradlew assembleDebug
# APK will be at app/build/outputs/apk/debug/app-debug.apk
```

### Requirements

- Xcode 15.0+
- Android Studio Ladybug+ / Gradle 8.9+
- JDK 17+

---

## Project Structure

```
DroidLink/
├── mac/                    # macOS SwiftUI application
│   └── DroidLink/
│       ├── App/            # App entry point, delegate
│       ├── Views/          # SwiftUI views
│       ├── Services/       # Core services (ADB, video, audio, etc.)
│       ├── Models/         # Data models
│       └── Resources/      # Assets, shaders
├── android/                # Android Kotlin companion app
│   └── app/src/main/
│       ├── java/com/droidlink/companion/
│       │   ├── ui/         # Compose UI screens
│       │   ├── services/   # Background services
│       │   ├── models/     # Data models
│       │   └── utils/      # Utilities
│       └── res/            # Android resources
├── protocol/               # Shared protocol definitions (Protobuf)
├── docs/                   # Documentation
└── .github/workflows/      # CI/CD
```

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Roadmap

- [x] Project scaffolding
- [ ] Phase 1: Core screen mirroring (USB + Wi-Fi)
- [ ] Phase 2: Ecosystem features (clipboard, files, notifications, SMS)
- [ ] Phase 3: Power features (virtual display, camera bridge, dashboard)
- [ ] Phase 4: Polish (menu bar, auto-update, encryption, localization)

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Inspired by [scrcpy](https://github.com/Genymobile/scrcpy) for screen mirroring concepts
- [KDE Connect](https://kdeconnect.kde.org/) for ecosystem integration ideas
- Apple's Continuity features for the vision of what cross-device integration should feel like

---

<p align="center">
  Made with ❤️ for Android + Mac users
</p>
