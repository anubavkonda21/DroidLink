# DroidLink Setup Guide

## Prerequisites

### macOS Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 or later) recommended for best performance
- Xcode 15.0+ (for building from source)

### Android Requirements
- Android 10 (API level 29) or later
- USB debugging enabled
- For audio forwarding: Android 11 (API level 30) or later

---

## Enable USB Debugging

USB debugging is required for DroidLink to communicate with your Android device.

### Steps:

1. **Open Settings** on your Android device
2. **Go to "About Phone"** (or "About Tablet")
   - On some devices: Settings → System → About Phone
3. **Tap "Build Number" 7 times** to enable Developer Options
   - You'll see a toast message: "You are now a developer!"
4. **Go back to Settings → System → Developer Options**
   - On some devices it's directly under Settings
5. **Enable "USB Debugging"**
6. **Connect your Android to your Mac via USB**
7. **Tap "Allow" on the USB debugging prompt** on your Android
   - Check "Always allow from this computer" for convenience

### Troubleshooting USB Debugging

- **Can't find Build Number?** Try searching "Build number" in Settings
- **No USB debugging prompt?** Try a different USB cable (use the one that came with your phone)
- **Device not recognized?** Install Android platform tools: `brew install android-platform-tools`
- **Multiple prompts?** Some devices show the prompt repeatedly — always tap "Allow"

---

## Wi-Fi Setup

For wireless mirroring without a USB cable:

### Option A: ADB Wi-Fi (recommended)
1. First connect via USB
2. DroidLink will offer to enable Wi-Fi mode
3. Accept — you can then disconnect the cable

### Option B: Manual Wi-Fi
1. Ensure both devices are on the **same Wi-Fi network**
2. On Android, open DroidLink companion app
3. Note the displayed IP address
4. On Mac, enter the IP address in DroidLink's connection dialog

---

## Android Companion App Permissions

The companion app requests permissions based on features you want to use:

| Permission | Feature | Required? |
|-----------|---------|-----------|
| Screen Capture | Screen mirroring | Yes |
| Notification Access | Notification sync | Optional |
| Contacts | SMS & Calls | Optional |
| Phone | Call bridging | Optional |
| SMS | SMS from Mac | Optional |
| Storage/Media | File transfer | Optional |
| Camera | Camera as webcam | Optional |
| Microphone | Audio features | Optional |

**You can grant permissions selectively** — only enable what you need.

### Granting Notification Access

Notification access requires a special system setting:

1. Open the DroidLink companion app
2. Tap "Enable Notification Sync"
3. You'll be taken to Settings → Notification Access
4. Find "DroidLink" and toggle it ON
5. Confirm the security warning

---

## First Run

1. Install DroidLink on your Mac
2. Install the companion app on your Android
3. Connect via USB (first time)
4. Launch DroidLink on Mac — your device should appear automatically
5. Grant the screen capture permission on Android when prompted
6. Start mirroring! 🎉

For subsequent connections, DroidLink will remember your device and can auto-connect.
