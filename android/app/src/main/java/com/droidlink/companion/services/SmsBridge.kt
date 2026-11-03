/*
 * DroidLink Android Companion Application
 *
 * SMS sync for the Mac's Messages page: reads conversations from the phone's SMS store,
 * sends texts the Mac writes, and pushes a fresh list whenever an SMS arrives or is sent.
 */

package com.droidlink.companion.services

import android.Manifest
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import com.droidlink.companion.utils.PermissionHelper
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

object SmsBridge {
    private const val TAG = "SmsBridge"
    private const val MAX_ROWS = 4000          // newest SMS rows scanned per sync
    private const val MAX_THREADS = 80
    private const val MAX_PER_THREAD = 100

    private var observer: ContentObserver? = null
    private val handler = Handler(Looper.getMainLooper())
    private val pushLater = Runnable { ConnectionService.instance?.pushSmsList() }

    fun canRead(ctx: Context) = PermissionHelper.isPermissionGranted(ctx, Manifest.permission.READ_SMS)
    fun canSend(ctx: Context) = PermissionHelper.isPermissionGranted(ctx, Manifest.permission.SEND_SMS)

    /** Sends the conversation list to the Mac (type "sms_list"). */
    fun pushList(service: ConnectionService) {
        val payload = runCatching { buildList(service) }.getOrElse {
            Log.e(TAG, "Reading SMS failed", it)
            buildJsonObject { put("permissionMissing", !canRead(service)); putJsonArray("conversations") {} }
        }
        service.sendRaw("sms_list", payload)
        watch(service)
    }

    /** Re-sends the list a moment after the SMS store changes (new text in, text sent). */
    fun watch(ctx: Context) {
        if (observer != null || !canRead(ctx)) return
        val obs = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                handler.removeCallbacks(pushLater)
                handler.postDelayed(pushLater, 1200)
            }
        }
        runCatching {
            ctx.contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, obs)
            observer = obs
        }.onFailure { Log.w(TAG, "Can't watch SMS store", it) }
    }

    fun unwatch(ctx: Context) {
        observer?.let { runCatching { ctx.contentResolver.unregisterContentObserver(it) } }
        observer = null
        handler.removeCallbacks(pushLater)
    }

    /** Sends a text from the phone's default SIM. Android saves it to the Sent box for us. */
    fun send(ctx: Context, to: String, body: String): Boolean {
        if (to.isBlank() || body.isBlank()) return false
        if (!canSend(ctx)) { Log.w(TAG, "SEND_SMS not granted"); return false }
        return runCatching {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ctx.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION") SmsManager.getDefault()
            }
            val parts = sms.divideMessage(body)
            if (parts.size > 1) sms.sendMultipartTextMessage(to, null, parts, null, null)
            else sms.sendTextMessage(to, null, body, null, null)
            true
        }.getOrElse { Log.e(TAG, "Sending SMS failed", it); false }
    }

    private data class Row(val id: Long, val address: String, val body: String, val date: Long, val type: Int, val read: Boolean)

    private fun buildList(ctx: Context): JsonObject {
        if (!canRead(ctx)) {
            return buildJsonObject { put("permissionMissing", true); putJsonArray("conversations") {} }
        }
        val threads = LinkedHashMap<Long, MutableList<Row>>()
        val projection = arrayOf(
            Telephony.Sms._ID, Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ
        )
        ctx.contentResolver.query(Telephony.Sms.CONTENT_URI, projection, null, null, "${Telephony.Sms.DATE} DESC")?.use { c ->
            var n = 0
            while (c.moveToNext() && n < MAX_ROWS) {
                n++
                val type = c.getInt(5)
                if (type == Telephony.Sms.MESSAGE_TYPE_DRAFT) continue
                val threadId = c.getLong(1)
                val list = threads[threadId]
                if (list == null && threads.size >= MAX_THREADS) continue
                val rows = list ?: mutableListOf<Row>().also { threads[threadId] = it }
                if (rows.size >= MAX_PER_THREAD) continue
                rows += Row(c.getLong(0), c.getString(2) ?: "", c.getString(3) ?: "", c.getLong(4), type, c.getInt(6) != 0)
            }
        }

        val names = HashMap<String, String?>()
        return buildJsonObject {
            put("permissionMissing", false)
            put("canSend", canSend(ctx))
            putJsonArray("conversations") {
                for ((threadId, rows) in threads) {
                    val number = rows.firstOrNull { it.address.isNotBlank() }?.address ?: continue
                    val name = names.getOrPut(number) { lookupName(ctx, number) }
                    addJsonObject {
                        put("threadId", threadId.toString())
                        put("contactNumber", number)
                        name?.let { put("contactName", it) }
                        put("unreadCount", rows.count { it.type == Telephony.Sms.MESSAGE_TYPE_INBOX && !it.read })
                        putJsonArray("messages") {
                            for (r in rows.asReversed()) addJsonObject { // oldest first
                                put("id", r.id.toString())
                                put("body", r.body)
                                put("timestamp", r.date / 1000.0)
                                put("isIncoming", r.type == Telephony.Sms.MESSAGE_TYPE_INBOX)
                                put("isRead", r.read)
                                put("status", when (r.type) {
                                    Telephony.Sms.MESSAGE_TYPE_FAILED -> "failed"
                                    Telephony.Sms.MESSAGE_TYPE_OUTBOX, Telephony.Sms.MESSAGE_TYPE_QUEUED -> "pending"
                                    else -> "delivered"
                                })
                            }
                        }
                    }
                }
            }
        }
    }

    private fun lookupName(ctx: Context, number: String): String? {
        if (!PermissionHelper.isPermissionGranted(ctx, Manifest.permission.READ_CONTACTS)) return null
        return runCatching {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            ctx.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull()
    }
}
