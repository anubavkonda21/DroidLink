package com.droidlink.companion.models

import android.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.io.DataInputStream
import java.io.DataOutputStream
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Wire format the macOS app speaks (see mac/DroidLink/Models/ProtocolMessages.swift):
 * 4-byte big-endian length + JSON {"type", "timestamp" (seconds), "payloadData" (base64 of payload JSON)}.
 */
object MacWire {

    data class Envelope(val type: String, val timestamp: Double, val payload: JsonObject?)

    private val json = Json { ignoreUnknownKeys = true }

    /** Maps an internal message to the Mac's type + payload. Returns null for messages the Mac has no type for. */
    fun encode(message: ProtocolMessage, nowMs: Long = System.currentTimeMillis()): ByteArray? {
        val (type, payload) = when (message) {
            is ProtocolMessage.Heartbeat -> "heartbeat" to null
            is ProtocolMessage.ClipboardSync -> "clipboard_sync" to buildJsonObject {
                put("text", message.text)
                put("isHtml", false)
                put("timestamp", message.timestamp / 1000.0)
            }
            is ProtocolMessage.NotificationForward -> "notification_post" to buildJsonObject {
                put("id", message.key.ifEmpty { "${message.packageName}|${message.id}" })
                put("appName", message.appName)
                put("appPackage", message.packageName)
                message.iconBase64?.let { put("appIcon", it) }
                put("title", message.title)
                put("body", message.text)
                // Swift's .iso8601 decoder rejects fractional seconds
                put("timestamp", Instant.ofEpochMilli(message.timestamp).truncatedTo(ChronoUnit.SECONDS).toString())
                put("isRead", false)
                put("canReply", message.hasReplyAction && !message.isCall)
                if (message.isCall) put("isSilent", true) // caller ID only: no sound, no answer button
                putJsonArray("actions") {
                    if (message.hasReplyAction && !message.isCall) addJsonObject {
                        put("id", "reply"); put("title", "Reply"); put("isQuickReply", true)
                    }
                }
            }
            is ProtocolMessage.CallEvent -> "call_event" to buildJsonObject {
                put("callState", when (message.callState) {
                    "RINGING" -> "incoming"
                    "OFFHOOK" -> "answered"
                    else -> "ended"
                })
                message.callerName?.let { put("callerName", it) }
                put("callerNumber", message.phoneNumber)
            }
            is ProtocolMessage.FileTransferOffer -> "file_transfer_init" to buildJsonObject {
                put("transferId", message.fileId)
                put("fileName", message.fileName)
                put("fileSize", message.fileSize)
                put("mimeType", "application/octet-stream")
                put("destinationFolder", "/sdcard/Download/DroidLink")
            }
            is ProtocolMessage.MacCommand -> "mac_command" to buildJsonObject { put("action", message.action) }
            else -> return null
        }
        val envelope = buildJsonObject {
            put("type", type)
            put("timestamp", nowMs / 1000.0)
            payload?.let { put("payloadData", Base64.encodeToString(it.toString().toByteArray(), Base64.NO_WRAP)) }
        }
        return envelope.toString().toByteArray()
    }

    fun decode(bytes: ByteArray): Envelope? = runCatching {
        val obj = json.parseToJsonElement(String(bytes)).jsonObject
        val payload = obj["payloadData"]?.jsonPrimitive?.content?.let {
            json.parseToJsonElement(String(Base64.decode(it, Base64.DEFAULT))).jsonObject
        }
        Envelope(
            type = obj.getValue("type").jsonPrimitive.content,
            timestamp = obj["timestamp"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
            payload = payload
        )
    }.getOrNull()

    fun writeFrame(out: DataOutputStream, body: ByteArray) {
        synchronized(out) {
            out.writeInt(body.size)
            out.write(body)
            out.flush()
        }
    }

    /** Returns null on clean end of stream. */
    fun readFrame(input: DataInputStream): ByteArray? {
        val length = runCatching { input.readInt() }.getOrNull() ?: return null
        require(length in 0..MAX_FRAME) { "Bad frame length $length" }
        return ByteArray(length).also { input.readFully(it) }
    }

    private const val MAX_FRAME = 16 * 1024 * 1024
}
