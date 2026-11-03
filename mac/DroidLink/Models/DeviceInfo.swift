//
//  DeviceInfo.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Represents the status and specifications of a connected Android device.
public struct DeviceInfo: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Properties

    /// Unique identifier for the device (e.g. ADB serial or UUID)
    public var id: String

    /// Friendly user-facing name for the device (e.g., "Pixel 8 Pro")
    public var name: String

    /// Device hardware model identifier (e.g., "Google Pixel 8 Pro", "SM-S928B")
    public var model: String

    /// Android OS version (e.g., "14.0", "15.0")
    public var androidVersion: String

    /// Current battery level as an integer percentage (0 to 100)
    public var batteryLevel: Int

    /// Total storage capacity on `/data` in bytes
    public var storageTotal: Int64

    /// Free storage available on `/data` in bytes
    public var storageFree: Int64

    /// Indicates whether the device is currently plugged in and charging
    public var isCharging: Bool

    /// Currently connected Wi-Fi network SSID (if applicable)
    public var wifiName: String?

    /// Local IP address of the Android device on the LAN
    public var ipAddress: String?

    /// Device screen resolution width in physical pixels
    public var screenWidth: Int

    /// Device screen resolution height in physical pixels
    public var screenHeight: Int

    /// Device screen density DPI
    public var screenDpi: Int

    /// Connection transport type
    public var connectionType: ConnectionType

    // MARK: - Nested Types

    public enum ConnectionType: String, Codable, CaseIterable, Sendable {
        case usb = "USB"
        case wifi = "Wi-Fi"
        case wirelessAdb = "Wireless ADB"

        public var iconName: String {
            switch self {
            case .usb:
                return "cable.connector"
            case .wifi, .wirelessAdb:
                return "wifi"
            }
        }
    }

    // MARK: - Initializer

    public init(
        id: String,
        name: String,
        model: String,
        androidVersion: String,
        batteryLevel: Int = 100,
        storageTotal: Int64 = 128_000_000_000,
        storageFree: Int64 = 64_000_000_000,
        isCharging: Bool = false,
        wifiName: String? = nil,
        ipAddress: String? = nil,
        screenWidth: Int = 1080,
        screenHeight: Int = 2400,
        screenDpi: Int = 420,
        connectionType: ConnectionType = .usb
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.androidVersion = androidVersion
        self.batteryLevel = max(0, min(100, batteryLevel))
        self.storageTotal = storageTotal
        self.storageFree = storageFree
        self.isCharging = isCharging
        self.wifiName = wifiName
        self.ipAddress = ipAddress
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.screenDpi = screenDpi
        self.connectionType = connectionType
    }

    // MARK: - Computed Formatters

    /// Formatted battery percentage string (e.g. "85%")
    public var batteryFormatted: String {
        "\(batteryLevel)%"
    }

    /// SF Symbol name representing current battery level and charging status
    public var batterySymbolName: String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        switch batteryLevel {
        case 0..<20:
            return "battery.0percent"
        case 20..<50:
            return "battery.25percent"
        case 50..<80:
            return "battery.50percent"
        case 80..<95:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }

    /// Storage used in bytes
    public var storageUsed: Int64 {
        max(0, storageTotal - storageFree)
    }

    /// Storage used percentage (0.0 to 1.0)
    public var storageUsedFraction: Double {
        guard storageTotal > 0 else { return 0 }
        return Double(storageUsed) / Double(storageTotal)
    }

    /// Human-readable storage summary (e.g., "64 GB of 128 GB used")
    public var storageFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        let usedStr = formatter.string(fromByteCount: storageUsed)
        let totalStr = formatter.string(fromByteCount: storageTotal)
        return "\(usedStr) of \(totalStr) used"
    }

    /// Formatted aspect ratio string (e.g., "20:9")
    public var aspectRatioFormatted: String {
        let gcdValue = gcd(screenWidth, screenHeight)
        let w = screenWidth / gcdValue
        let h = screenHeight / gcdValue
        return "\(w):\(h)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let temp = y
            y = x % y
            x = temp
        }
        return x
    }
}
