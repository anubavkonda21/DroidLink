/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Sealed class hierarchy defining the protocol messages exchanged between
 * Android companion device and macOS host app for notification syncing.
 */

package com.droidlink.companion.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
sealed class ProtocolMessage {

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

    @Serializable
    @SerialName("handshake_ack")
    data class HandshakeAck(
        val status: String,
        val macHostname: String,
        val sessionId: String
    ) : ProtocolMessage()

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

    @Serializable
    @SerialName("notification_reply")
    data class NotificationReply(
        val key: String,
        val replyText: String
    ) : ProtocolMessage()

    @Serializable
    @SerialName("heartbeat")
    data class Heartbeat(
        val timestamp: Long = System.currentTimeMillis()
    ) : ProtocolMessage()

    @Serializable
    @SerialName("heartbeat_ack")
    data class HeartbeatAck(
        val originalTimestamp: Long,
        val receivedTimestamp: Long = System.currentTimeMillis()
    ) : ProtocolMessage()

    companion object {
        val jsonConfig = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
            classDiscriminator = "type"
        }

        fun toJson(message: ProtocolMessage): String {
            return jsonConfig.encodeToString(message)
        }

        fun fromJson(jsonString: String): ProtocolMessage? {
            return runCatching {
                jsonConfig.decodeFromString<ProtocolMessage>(jsonString)
            }.getOrNull()
        }
    }
}
