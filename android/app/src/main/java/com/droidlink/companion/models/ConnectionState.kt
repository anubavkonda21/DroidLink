/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Represents the connection states of the Android companion device with macOS host.
 */

package com.droidlink.companion.models

/**
 * Sealed class modeling all possible connection and streaming states of DroidLink.
 */
sealed class ConnectionState {

    /**
     * Initial state when the companion is disconnected from any Mac client.
     */
    data object Disconnected : ConnectionState()

    /**
     * State while discovering peer Mac devices via mDNS / NSD or scanning Wi-Fi network.
     */
    data object Discovering : ConnectionState()

    /**
     * State while establishing handshake, pairing, or opening WebSocket / TCP channels.
     * @param targetHost IP or hostname being connected to.
     */
    data class Connecting(val targetHost: String = "") : ConnectionState()

    /**
     * State when successfully authenticated and control channel is active.
     * @param deviceName Name of the connected Mac (e.g., "MacBook Pro").
     * @param hostAddress IPv4 / IPv6 address or USB connection identifier.
     */
    data class Connected(
        val deviceName: String,
        val hostAddress: String
    ) : ConnectionState()

    /**
     * State when screen mirroring stream is actively encoding and transmitting frames.
     * @param deviceName Name of the connected Mac.
     * @param fps Current active frames per second.
     * @param bitrate Current active bitrate in bits per second.
     */
    data class Mirroring(
        val deviceName: String,
        val fps: Int,
        val bitrate: Int
    ) : ConnectionState()

    /**
     * Returns true if there is an active control or streaming connection.
     */
    val isConnected: Boolean
        get() = this is Connected || this is Mirroring

    /**
     * Returns true if screen capture is actively streaming.
     */
    val isMirroring: Boolean
        get() = this is Mirroring

    /**
     * Formatted user-facing display label for status indicators.
     */
    val displayStatus: String
        get() = when (this) {
            is Disconnected -> "Not Connected"
            is Discovering -> "Searching for Mac…"
            is Connecting -> "Connecting…"
            is Connected -> "Connected to $deviceName"
            is Mirroring -> "Mirroring to $deviceName ($fps fps)"
        }
}
