//
//  MacStatus.swift
//  DroidLink
//
//  The Mac's own status for the phone's "MacBook" card, and the Mac actions the phone can trigger.
//

import AppKit
import IOKit.ps

/// Sent to the phone as `mac_status`.
struct MacStatusPayload: Codable, Equatable {
    var name: String
    var batteryLevel: Int?        // nil on a Mac without a battery
    var isCharging: Bool
    var onPower: Bool
    var minutesRemaining: Int?    // to empty, or to full while charging; nil while macOS is still estimating
    var storageFreeGB: Int
    var storageTotalGB: Int
    var volume: Int
    var muted: Bool
}

/// Received from the phone as `mac_command`.
struct MacCommandPayload: Codable {
    var action: String
}

enum MacStatus {
    static func current() -> MacStatusPayload {
        var status = MacStatusPayload(name: Host.current().localizedName ?? "Mac", batteryLevel: nil, isCharging: false,
                                      onPower: true, minutesRemaining: nil, storageFreeGB: 0, storageTotalGB: 0,
                                      volume: 0, muted: false)

        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            status.batteryLevel = max > 0 ? cur * 100 / max : cur
            status.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            status.onPower = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = (status.isCharging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            status.minutesRemaining = minutes > 0 ? minutes : nil
        }

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            status.storageFreeGB = Int((v.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000)
            status.storageTotalGB = (v.volumeTotalCapacity ?? 0) / 1_000_000_000
        }

        if let result = runAppleScript("get volume settings") {
            // record order: output volume, input volume, alert volume, output muted
            status.volume = Int(result.atIndex(1)?.int32Value ?? 0)
            status.muted = result.atIndex(4)?.booleanValue ?? false
        }
        return status
    }

    /// Runs a phone-requested action. Unknown actions are ignored.
    static func perform(_ action: String) {
        switch action {
        case "lock": lockScreen()
        case "sleep": run("/usr/bin/pmset", ["sleepnow"])
        case "volume_up": runAppleScript("set volume output volume ((output volume of (get volume settings)) + 10) without output muted")
        case "volume_down": runAppleScript("set volume output volume ((output volume of (get volume settings)) - 10)")
        case "mute": runAppleScript("set volume output muted (not (output muted of (get volume settings)))")
        case "play_pause": pressMediaKey(16) // NX_KEYTYPE_PLAY
        case "next": pressMediaKey(17)       // NX_KEYTYPE_NEXT
        case "previous": pressMediaKey(18)   // NX_KEYTYPE_PREVIOUS
        default: break
        }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// Same as Control-Command-Q. Falls back to sleeping the display, which locks when a password is required.
    private static func lockScreen() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias Lock = @convention(c) () -> Int32
            _ = unsafeBitCast(sym, to: Lock.self)()
        } else {
            run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    /// Posts a hardware media key (needs Accessibility permission; macOS asks the first time).
    private static func pressMediaKey(_ key: Int32) {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else { return }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
