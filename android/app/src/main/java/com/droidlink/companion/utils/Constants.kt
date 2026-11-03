/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * App-wide constants, protocol configurations, and intent action identifiers.
 */

package com.droidlink.companion.utils

/**
 * Global constant values used across the DroidLink companion application.
 */
object Constants {

    // App Information
    const val APP_NAME = "DroidLink"
    const val PROTOCOL_VERSION = "1.0.0"

    // Network & Ports
    const val DEFAULT_CONTROL_PORT = 8080
    const val DEFAULT_VIDEO_PORT = 8081
    const val DEFAULT_FILE_PORT = 8082
    const val DEFAULT_AUDIO_PORT = 8083

    // NSD / mDNS Discovery
    const val NSD_SERVICE_TYPE = "_droidlink._tcp."
    const val NSD_SERVICE_NAME = "DroidLink-Companion"

    // Supported Video Codecs
    const val CODEC_H264 = "video/avc"
    const val CODEC_H265 = "video/hevc"
    const val DEFAULT_CODEC = CODEC_H264

    // Video Streaming Defaults
    const val DEFAULT_VIDEO_WIDTH = 1920
    const val DEFAULT_VIDEO_HEIGHT = 1080
    const val DEFAULT_VIDEO_FPS = 60
    const val DEFAULT_VIDEO_BITRATE = 8_000_000 // 8 Mbps
    const val DEFAULT_I_FRAME_INTERVAL = 1 // 1 second keyframe interval

    // Notification Channel IDs
    const val CHANNEL_ID_SCREEN_CAPTURE = "droidlink_channel_screen_capture"
    const val CHANNEL_ID_CONNECTION = "droidlink_channel_connection"
    const val CHANNEL_ID_FILE_TRANSFER = "droidlink_channel_file_transfer"

    // Notification IDs
    const val NOTIFICATION_ID_SCREEN_CAPTURE = 1001
    const val NOTIFICATION_ID_CONNECTION = 1002
    const val NOTIFICATION_ID_FILE_TRANSFER = 1003

    // Intent Actions - Screen Capture
    const val ACTION_START_SCREEN_CAPTURE = "com.droidlink.companion.action.START_SCREEN_CAPTURE"
    const val ACTION_STOP_SCREEN_CAPTURE = "com.droidlink.companion.action.STOP_SCREEN_CAPTURE"
    const val EXTRA_MEDIA_PROJECTION_DATA = "extra_media_projection_data"
    const val EXTRA_MEDIA_PROJECTION_RESULT_CODE = "extra_media_projection_result_code"
    const val EXTRA_MIRROR_CONFIG = "extra_mirror_config"

    // Intent Actions - Connection Service
    const val ACTION_CONNECT = "com.droidlink.companion.action.CONNECT"
    const val ACTION_DISCONNECT = "com.droidlink.companion.action.DISCONNECT"
    const val ACTION_START_SERVER = "com.droidlink.companion.action.START_SERVER"
    const val EXTRA_TARGET_IP = "extra_target_ip"
    const val EXTRA_TARGET_PORT = "extra_target_port"

    // Intent Actions - File Transfer
    const val ACTION_SEND_FILE = "com.droidlink.companion.action.SEND_FILE"
    const val EXTRA_FILE_URI = "extra_file_uri"
    const val EXTRA_FILE_PATH = "extra_file_path"

    // Shared Preferences / DataStore Keys
    const val PREFS_NAME = "droidlink_preferences"
    const val PREF_KEY_AUTO_CONNECT = "auto_connect"
    const val PREF_KEY_PREFERRED_MODE = "preferred_mode"
    const val PREF_KEY_PORT = "port"
    const val PREF_KEY_RESOLUTION_WIDTH = "video_width"
    const val PREF_KEY_RESOLUTION_HEIGHT = "video_height"
    const val PREF_KEY_FPS = "video_fps"
    const val PREF_KEY_BITRATE = "video_bitrate"
    const val PREF_KEY_CODEC = "video_codec"
    const val PREF_KEY_CLIPBOARD_SYNC = "clipboard_sync"
    const val PREF_KEY_OTP_FORWARDING = "otp_forwarding"
    const val PREF_KEY_AUTO_ACCEPT_FILES = "auto_accept_files"
    const val PREF_KEY_REQUIRE_PIN = "require_pin"
    const val PREF_KEY_PIN_CODE = "pin_code"
    const val PREF_KEY_ENCRYPTION_ENABLED = "encryption_enabled"

    // Connection Modes
    const val MODE_AUTO = "Auto"
    const val MODE_WIFI = "Wi-Fi"
    const val MODE_USB = "USB"

    // Timing & Heartbeat
    const val HEARTBEAT_INTERVAL_MS = 5000L
    const val HEARTBEAT_TIMEOUT_MS = 15000L
    const val CLIPBOARD_DEBOUNCE_MS = 800L
}
