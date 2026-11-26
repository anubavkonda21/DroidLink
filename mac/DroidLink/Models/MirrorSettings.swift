//
//  MirrorSettings.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// App settings and UserDefaults storage keys.
public struct MirrorSettings: Codable, Equatable, Sendable {
    public var autoConnect: Bool
    public var launchAtLogin: Bool
    public var preferredConnectionType: DeviceInfo.ConnectionType

    public init(
        autoConnect: Bool = true,
        launchAtLogin: Bool = false,
        preferredConnectionType: DeviceInfo.ConnectionType = .usb
    ) {
        self.autoConnect = autoConnect
        self.launchAtLogin = launchAtLogin
        self.preferredConnectionType = preferredConnectionType
    }

    public static let `default` = MirrorSettings()

    // MARK: - Storage Keys

    public enum StorageKeys {
        public static let autoConnect = "general_auto_connect"
        public static let launchAtLogin = "general_launch_at_login"
        public static let preferredConnection = "general_preferred_connection"
        public static let enableNotifications = "notifications_enabled"
        public static let notificationSound = "notifications_sound"
    }
}
