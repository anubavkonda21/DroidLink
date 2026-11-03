# DroidLink Architecture

## Overview

DroidLink is a two-part application:
1. **macOS Desktop App** (Swift/SwiftUI) — the main UI and control center
2. **Android Companion App** (Kotlin/Compose) — runs on the phone, captures and streams data

Communication happens over USB (via ADB port forwarding) or Wi-Fi (direct TCP/WebSocket).

---

## Communication Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Transport Layer                     │
│                                                       │
│  ┌──────────────────┐     ┌──────────────────┐       │
│  │   USB Mode        │     │   Wi-Fi Mode      │       │
│  │                  │     │                  │       │
│  │  ADB Forward     │     │  mDNS Discovery  │       │
│  │  localhost:27183  │     │  Direct TCP/WS   │       │
│  │  localhost:27184  │     │  TLS 1.3         │       │
│  │  localhost:27185  │     │                  │       │
│  └──────────────────┘     └──────────────────┘       │
└─────────────────────────────────────────────────────┘
                          │
            ┌─────────────┼─────────────┐
            ▼             ▼             ▼
     ┌────────────┐ ┌────────────┐ ┌────────────┐
     │   Video    │ │   Audio    │ │  Control   │
     │  Channel   │ │  Channel   │ │  Channel   │
     │            │ │            │ │            │
     │ Port 27183 │ │ Port 27184 │ │ Port 27185 │
     │ TCP/Raw    │ │ TCP/Raw    │ │ WebSocket  │
     │ H.264/265  │ │ Opus       │ │ JSON/Proto │
     │ One-way →  │ │ One-way →  │ │ Bidir ↔    │
     └────────────┘ └────────────┘ └────────────┘
```

## Data Flow

### Screen Mirroring Pipeline

```
Android                              macOS
┌──────────────────┐                ┌──────────────────┐
│ Screen Surface    │                │ MTKView (Metal)   │
│       │          │                │       ▲          │
│       ▼          │                │       │          │
│ VirtualDisplay    │                │ Metal Renderer    │
│       │          │                │ (YUV → RGB)       │
│       ▼          │                │       ▲          │
│ MediaCodec        │   TCP/27183   │       │          │
│ (H.265 Encoder)  │ ─────────────►│ VideoToolbox      │
│       │          │  NAL units    │ (H.265 Decoder)   │
│       ▼          │                │       ▲          │
│ Socket Output     │                │ Socket Input      │
└──────────────────┘                └──────────────────┘
```

### Input Pipeline (Reverse Direction)

```
macOS                                Android
┌──────────────────┐                ┌──────────────────┐
│ NSEvent           │                │ Input Injection   │
│ (mouse/keyboard)  │                │       ▲          │
│       │          │                │       │          │
│       ▼          │                │ Coordinate Map    │
│ InputForwarder    │   WS/27185    │       ▲          │
│ (coord mapping)  │ ─────────────►│       │          │
│       │          │  JSON events  │ WebSocket Server  │
│       ▼          │                │                  │
│ WebSocket Client  │                │                  │
└──────────────────┘                └──────────────────┘
```

## macOS App Architecture

```
DroidLinkApp (SwiftUI)
├── ContentView (NavigationSplitView)
│   ├── MirrorView (MTKView + InputForwarder)
│   ├── DashboardView
│   ├── NotificationPanel
│   ├── FileTransferView
│   ├── MessagesView
│   └── SettingsView
│
├── Services (singletons, @Observable)
│   ├── ConnectionManager      ← orchestrates everything
│   │   ├── DeviceDiscovery    ← mDNS + ADB device detection
│   │   ├── ADBService         ← ADB binary interaction
│   │   └── WebSocket client   ← control channel
│   │
│   ├── VideoDecoder           ← VideoToolbox H.264/265
│   ├── MetalRenderer          ← GPU frame rendering
│   ├── AudioPlayer            ← Opus decode + AVAudioEngine
│   ├── InputForwarder         ← mouse/key → touch/key mapping
│   ├── ClipboardSync          ← NSPasteboard ↔ Android
│   ├── NotificationBridge     ← UNUserNotificationCenter
│   └── FileTransferService    ← TCP file transfer + ADB push/pull
│
└── Models
    ├── DeviceInfo
    ├── AndroidNotification
    ├── FileTransferItem
    ├── Message / Conversation
    ├── MirrorSettings
    └── ProtocolMessages
```

## Android App Architecture

```
DroidLink Companion (Kotlin/Compose)
├── MainActivity (Compose Navigation)
│   ├── HomeScreen
│   ├── StatusScreen
│   └── SettingsScreen
│
├── Services (Foreground + Background)
│   ├── ConnectionService      ← manages lifecycle, mDNS, WebSocket server
│   ├── ScreenCaptureService   ← MediaProjection + MediaCodec encoder
│   ├── NotificationListener   ← NotificationListenerService
│   ├── ClipboardService       ← ClipboardManager monitoring
│   ├── FileServerService      ← TCP file send/receive
│   └── CallBridgeService      ← TelephonyManager + call state
│
├── Receivers
│   └── BootReceiver           ← auto-start on boot
│
├── Models
│   ├── ConnectionState
│   ├── ProtocolMessage
│   └── MirrorConfig
│
└── Utils
    ├── PermissionHelper
    ├── DeviceInfo
    └── Constants
```

## Security Model

1. **USB connections** — inherently secure (physical access required)
2. **Wi-Fi connections** — TLS 1.3 encrypted
3. **Pairing** — first connection requires explicit approval on Android
4. **Authentication** — optional PIN code for additional security
5. **Permissions** — granular; users choose which features to enable
