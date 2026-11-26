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
    const val MAC_NOTIFICATION_PORT = 8081

    // NSD / mDNS Discovery
    const val NSD_SERVICE_TYPE = "_droidlink._tcp."
    const val NSD_SERVICE_NAME = "DroidLink-Companion"

    // Notification Channel IDs
    const val CHANNEL_ID_CONNECTION = "droidlink_channel_connection"

    // Notification IDs
    const val NOTIFICATION_ID_CONNECTION = 1002

    // Intent Actions - Connection Service
    const val ACTION_CONNECT = "com.droidlink.companion.action.CONNECT"
    const val ACTION_DISCONNECT = "com.droidlink.companion.action.DISCONNECT"
    const val ACTION_START_SERVER = "com.droidlink.companion.action.START_SERVER"
    const val EXTRA_TARGET_IP = "extra_target_ip"
    const val EXTRA_TARGET_PORT = "extra_target_port"

    // Shared Preferences Keys
    const val PREFS_NAME = "droidlink_preferences"
    const val PREF_KEY_AUTO_CONNECT = "auto_connect"
    const val PREF_KEY_PREFERRED_MODE = "preferred_mode"
    const val PREF_KEY_PORT = "port"
    const val PREF_KEY_LAST_MAC_IP = "last_mac_ip"

    // Connection Modes
    const val MODE_AUTO = "Auto"
    const val MODE_WIFI = "Wi-Fi"
    const val MODE_USB = "USB"

    // Timing & Heartbeat (60s reduces Wi-Fi radio & CPU wakeups while backgrounded)
    const val HEARTBEAT_INTERVAL_MS = 60000L
    const val HEARTBEAT_TIMEOUT_MS = 60000L
}
