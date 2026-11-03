/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Sealed class hierarchy defining the network protocol messages exchanged between
 * Android companion device and macOS host app over WebSockets and TCP control sockets.
 */

package com.droidlink.companion.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Top-level sealed hierarchy for all JSON protocol control messages.
 */
@Serializable
sealed class ProtocolMessage {

    /**
     * Handshake initiated by Android companion when connecting to Mac.
     */
    @Serializable
    @SerialName("handshake")
    data class Handshake(
        val version: String,
        val deviceName: String,
        val deviceModel: String,
        val osVersion: String,
        val screenWidth: Int,
        val screenHeight: Int
    ) : ProtocolMessage()

    /**
     * Handshake acknowledgement returned by Mac client.
     */
    @Serializable
    @SerialName("handshake_ack")
    data class HandshakeAck(
        val status: String,
        val macHostname: String,
        val sessionId: String
    ) : ProtocolMessage()

    /**
     * Video stream negotiation and configuration message.
     */
    @Serializable
    @SerialName("video_config")
    data class VideoConfig(
        val width: Int,
        val height: Int,
        val fps: Int,
        val bitrate: Int,
        val codec: String
    ) : ProtocolMessage()

    /**
     * Request to start video capture and streaming.
     */
    @Serializable
    @SerialName("start_mirroring")
    data class StartMirroring(
        val config: MirrorConfig? = null
    ) : ProtocolMessage()

    /**
     * Request to stop active video streaming.
     */
    @Serializable
    @SerialName("stop_mirroring")
    data class StopMirroring(
        val reason: String = "User requested stop"
    ) : ProtocolMessage()

    /**
     * Bi-directional clipboard content synchronization.
     */
    @Serializable
    @SerialName("clipboard_sync")
    data class ClipboardSync(
        val text: String,
        val mimeType: String = "text/plain",
        val timestamp: Long = System.currentTimeMillis(),
        val isOtp: Boolean = false
    ) : ProtocolMessage()

    /**
     * Forwarded notification event from Android to Mac.
     */
    @Serializable
    @SerialName("notification_forward")
    data class NotificationForward(
        val id: Int,
        val packageName: String,
        val appName: String,
        val title: String,
        val text: String,
        val timestamp: Long = System.currentTimeMillis(),
        val hasReplyAction: Boolean = false,
        val key: String = "",
        val iconBase64: String? = null,
        val isCall: Boolean = false
    ) : ProtocolMessage()

    /**
     * Inline notification reply from Mac back to Android app.
     */
    @Serializable
    @SerialName("notification_reply")
    data class NotificationReply(
        val key: String,
        val replyText: String
    ) : ProtocolMessage()

    /**
     * Negotiation / announcement of a file to be transferred.
     */
    @Serializable
    @SerialName("file_transfer_offer")
    data class FileTransferOffer(
        val fileId: String,
        val fileName: String,
        val fileSize: Long,
        val checksumCrc32: Long
    ) : ProtocolMessage()

    /**
     * Acknowledgement or status of a file transfer.
     */
    @Serializable
    @SerialName("file_transfer_ack")
    data class FileTransferAck(
        val fileId: String,
        val success: Boolean,
        val message: String = ""
    ) : ProtocolMessage()

    /**
     * Input event injected from Mac trackpad/mouse/keyboard onto Android screen.
     */
    @Serializable
    @SerialName("input_event")
    data class InputEvent(
        val action: String, // DOWN, MOVE, UP, KEY_DOWN, KEY_UP, SCROLL
        val x: Float = 0f,
        val y: Float = 0f,
        val keyCode: Int = 0,
        val metaState: Int = 0,
        val scrollDeltaX: Float = 0f,
        val scrollDeltaY: Float = 0f
    ) : ProtocolMessage()

    /**
     * Real-time device telemetry sent periodically to Mac menu bar / dashboard.
     */
    @Serializable
    @SerialName("device_status")
    data class DeviceStatus(
        val batteryLevel: Int,
        val isCharging: Boolean,
        val thermalStatus: String,
        val wifiSsid: String,
        val freeStorageBytes: Long,
        val totalStorageBytes: Long
    ) : ProtocolMessage()

    /**
     * Liveness ping sent over control channel.
     */
    @Serializable
    @SerialName("heartbeat")
    data class Heartbeat(
        val timestamp: Long = System.currentTimeMillis()
    ) : ProtocolMessage()

    /**
     * Response to liveness ping to calculate RTT latency.
     */
    @Serializable
    @SerialName("heartbeat_ack")
    data class HeartbeatAck(
        val originalTimestamp: Long,
        val receivedTimestamp: Long = System.currentTimeMillis()
    ) : ProtocolMessage()

    /**
     * Incoming telephony call alert sent from Android to Mac.
     */
    @Serializable
    @SerialName("call_event")
    data class CallEvent(
        val callState: String, // RINGING, OFFHOOK, IDLE
        val phoneNumber: String,
        val callerName: String? = null
    ) : ProtocolMessage()

    /**
     * Call control instruction from Mac to Android.
     */
    @Serializable
    @SerialName("call_control")
    data class CallControl(
        val action: String, // ANSWER, REJECT, SILENCE
        val phoneNumber: String = ""
    ) : ProtocolMessage()

    /** Android -> Mac: lock, sleep, volume_up/down, mute, play_pause, next, previous, refresh. */
    @Serializable
    @SerialName("mac_command")
    data class MacCommand(val action: String) : ProtocolMessage()

    companion object {
        val jsonConfig = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
            classDiscriminator = "type"
        }

        /**
         * Serializes any ProtocolMessage subclass to JSON string.
         */
        fun toJson(message: ProtocolMessage): String {
            return jsonConfig.encodeToString(message)
        }

        /**
         * Deserializes a JSON string into a concrete ProtocolMessage subclass.
         */
        fun fromJson(jsonString: String): ProtocolMessage? {
            return runCatching {
                jsonConfig.decodeFromString<ProtocolMessage>(jsonString)
            }.getOrNull()
        }
    }
}
