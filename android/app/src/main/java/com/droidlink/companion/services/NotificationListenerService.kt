/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Low-power Notification Listener service intercepting system notifications,
 * caching app icons, skipping ongoing/progress spam, and forwarding to Mac.
 */

package com.droidlink.companion.services

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.service.notification.NotificationListenerService as AndroidNotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import android.util.LruCache
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Features
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Listens for system notifications and relays them to connected Mac workstation.
 */
class NotificationListenerService : AndroidNotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val iconCache = LruCache<String, String>(48)
    private val appNameCache = ConcurrentHashMap<String, String>()
    private val recentSignatures = ConcurrentHashMap<String, Int>()

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "NotificationListenerService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        serviceScope.cancel()
        iconCache.evictAll()
        appNameCache.clear()
        recentSignatures.clear()
        Log.d(TAG, "NotificationListenerService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        // Fast-path exit: avoid any work if this is our own notification or forwarding is off
        if (sbn.packageName == packageName) return
        if (!Features.isOn(this, Features.NOTIFICATIONS)) return

        if (ConnectionService.instance == null) {
            val svcIntent = Intent(this, ConnectionService::class.java).apply {
                action = com.droidlink.companion.utils.Constants.ACTION_START_SERVER
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                runCatching { startForegroundService(svcIntent) }
            } else {
                runCatching { startService(svcIntent) }
            }
        }

        val pm = getSystemService(POWER_SERVICE) as? PowerManager
        val wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DroidLink:NotifForward")?.apply {
            setReferenceCounted(false)
            acquire(4_000L)
        }

        serviceScope.launch {
            try {
                processAndForwardNotification(sbn)
            } finally {
                if (wakeLock?.isHeld == true) {
                    runCatching { wakeLock.release() }
                }
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        recentSignatures.remove(sbn.key)
    }

    private fun processAndForwardNotification(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle()

        val ringing = notification.fullScreenIntent != null ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                extras.getInt(Notification.EXTRA_CALL_TYPE) == Notification.CallStyle.CALL_TYPE_INCOMING)

        // Skip ongoing background banners (music bars, VPN, download progress) and group summaries
        val isOngoing = (notification.flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE)) != 0
        val isGroupSummary = (notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        val isProgress = extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0
        if ((isOngoing || isGroupSummary || isProgress) && !ringing) {
            return
        }

        val packageName = sbn.packageName ?: "android"
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: ""

        if (title.isBlank() && text.isBlank()) return

        val looksLikeCall = notification.category == Notification.CATEGORY_CALL ||
            (ringing && "$title $text".contains("call", ignoreCase = true))
        if (looksLikeCall && !ringing) return
        val isIncomingCall = looksLikeCall && ringing

        // Deduplicate identical consecutive updates for the same notification key
        val signature = "$title\n$text".hashCode()
        if (recentSignatures[sbn.key] == signature) return
        recentSignatures[sbn.key] = signature
        if (recentSignatures.size > 200) recentSignatures.clear()

        val packageManager = applicationContext.packageManager
        val appName = appNameCache.getOrPut(packageName) {
            runCatching {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            }.getOrDefault(packageName)
        }

        val hasReplyAction = findRemoteInputAction(notification) != null
        val iconBase64 = getCachedIconBase64(packageManager, packageName, notification)

        val forwardMessage = ProtocolMessage.NotificationForward(
            id = sbn.id,
            packageName = packageName,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            hasReplyAction = hasReplyAction,
            key = sbn.key,
            iconBase64 = iconBase64,
            isCall = isIncomingCall
        )

        Log.d(TAG, "Forwarding notification from $appName: $title")
        _notificationEvents.tryEmit(forwardMessage)
        ConnectionService.broadcastProtocolMessage(forwardMessage)
    }

    private fun findRemoteInputAction(notification: Notification): Notification.Action? {
        val actions = notification.actions ?: return null
        for (action in actions) {
            val remoteInputs = action.remoteInputs ?: continue
            for (ri in remoteInputs) {
                if (ri.allowFreeFormInput) return action
            }
        }
        return null
    }

    fun sendReply(notificationKey: String, replyText: String): Boolean {
        val activeNotifs = runCatching { activeNotifications }.getOrNull() ?: return false
        val sbn = activeNotifs.find { it.key == notificationKey } ?: return false
        val action = findRemoteInputAction(sbn.notification) ?: return false
        val remoteInputs = action.remoteInputs ?: return false
        val replyRemoteInput = remoteInputs.firstOrNull { it.allowFreeFormInput } ?: return false

        return runCatching {
            val intent = Intent()
            val bundle = Bundle()
            bundle.putCharSequence(replyRemoteInput.resultKey, replyText)
            RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
            action.actionIntent.send(this, 0, intent)
            true
        }.getOrElse { e ->
            Log.e(TAG, "Failed sending reply to notification", e)
            false
        }
    }

    private fun getCachedIconBase64(pm: PackageManager, pkg: String, notification: Notification): String? {
        iconCache.get(pkg)?.let { return it }

        val encoded = runCatching {
            val drawable: Drawable = runCatching {
                notification.getLargeIcon()?.loadDrawable(this)
            }.getOrNull() ?: pm.getApplicationIcon(pkg)

            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 64
                    val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 64
                    val b = Bitmap.createBitmap(width.coerceAtMost(96), height.coerceAtMost(96), Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(b)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    b
                }
            }

            val scaled = if (bitmap.width > 96 || bitmap.height > 96) {
                Bitmap.createScaledBitmap(bitmap, 64, 64, true)
            } else {
                bitmap
            }

            val baos = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.PNG, 80, baos)
            Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
        }.getOrNull()

        if (encoded != null) {
            iconCache.put(pkg, encoded)
        }
        return encoded
    }

    companion object {
        private const val TAG = "NotificationListener"

        @Volatile
        var instance: NotificationListenerService? = null
            private set

        private val _notificationEvents = MutableSharedFlow<ProtocolMessage.NotificationForward>(replay = 10)
        val notificationEvents = _notificationEvents.asSharedFlow()

        fun replyToNotification(key: String, replyText: String): Boolean {
            return instance?.sendReply(key, replyText) ?: false
        }

        fun dismiss(key: String) {
            runCatching { instance?.cancelNotification(key) }
        }
    }
}
