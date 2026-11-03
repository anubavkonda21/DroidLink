//
//  MirrorSettings.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Video codec options for stream decoding and hardware acceleration.
public enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264 = "H.264 (AVC)"
    case h265 = "H.265 (HEVC)"
    case av1 = "AV1"

    public var id: String { rawValue }

    public var scrcpyCodecName: String {
        switch self {
        case .h264:
            return "h264"
        case .h265:
            return "h265"
        case .av1:
            return "av1"
        }
    }
}

/// Screen mirror resolution preference.
public enum ResolutionOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case native = "Native"
    case r1080p = "1080p (FHD)"
    case r720p = "720p (HD)"
    case r540p = "540p (SD)"

    public var id: String { rawValue }

    public var maxDimension: Int? {
        switch self {
        case .native:
            return nil
        case .r1080p:
            return 1920
        case .r720p:
            return 1280
        case .r540p:
            return 960
        }
    }
}

/// App settings and stream parameters for screen mirroring.
public struct MirrorSettings: Codable, Equatable, Sendable {
    // MARK: - Properties

    public var maxResolution: ResolutionOption
    public var maxFps: Int
    public var codec: VideoCodec
    public var bitrateMbps: Int
    public var audioEnabled: Bool
    public var showTouches: Bool
    public var stayAwake: Bool
    public var turnScreenOff: Bool
    public var autoConnect: Bool
    public var launchAtLogin: Bool
    public var preferredConnectionType: DeviceInfo.ConnectionType

    // MARK: - Initializer

    public init(
        maxResolution: ResolutionOption = .native,
        maxFps: Int = 60,
        codec: VideoCodec = .h264,
        bitrateMbps: Int = 12,
        audioEnabled: Bool = true,
        showTouches: Bool = false,
        stayAwake: Bool = true,
        turnScreenOff: Bool = false,
        autoConnect: Bool = true,
        launchAtLogin: Bool = false,
        preferredConnectionType: DeviceInfo.ConnectionType = .usb
    ) {
        self.maxResolution = maxResolution
        self.maxFps = maxFps
        self.codec = codec
        self.bitrateMbps = bitrateMbps
        self.audioEnabled = audioEnabled
        self.showTouches = showTouches
        self.stayAwake = stayAwake
        self.turnScreenOff = turnScreenOff
        self.autoConnect = autoConnect
        self.launchAtLogin = launchAtLogin
        self.preferredConnectionType = preferredConnectionType
    }

    public static let `default` = MirrorSettings()

    // MARK: - AppStorage Keys

    public enum StorageKeys {
        public static let maxResolution = "mirror_max_resolution"
        public static let maxFps = "mirror_max_fps"
        public static let codec = "mirror_codec"
        public static let bitrateMbps = "mirror_bitrate_mbps"
        public static let audioEnabled = "mirror_audio_enabled"
        public static let showTouches = "mirror_show_touches"
        public static let stayAwake = "mirror_stay_awake"
        public static let turnScreenOff = "mirror_turn_screen_off"
        public static let autoConnect = "general_auto_connect"
        public static let launchAtLogin = "general_launch_at_login"
        public static let preferredConnection = "general_preferred_connection"
        public static let autoSyncClipboard = "clipboard_auto_sync"
        public static let otpAutoForward = "clipboard_otp_auto_forward"
        public static let clipboardHistoryCount = "clipboard_history_count"
        public static let enableNotifications = "notifications_enabled"
        public static let notificationSound = "notifications_sound"
        public static let syncDnd = "notifications_sync_dnd"
        public static let downloadDirectory = "files_download_directory"
        public static let autoOrganizeFiles = "files_auto_organize"
    }
}
