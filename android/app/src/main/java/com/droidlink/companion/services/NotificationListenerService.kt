/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Notification Listener service intercepting system notifications, packaging them,
 * and forwarding to macOS desktop with RemoteInput inline reply capabilities.
 */

package com.droidlink.companion.services

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.service.notification.NotificationListenerService as AndroidNotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Constants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

/**
 * Listens for system notifications and relays them to connected Mac workstation.
 */
class NotificationListenerService : AndroidNotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "NotificationListenerService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.d(TAG, "NotificationListenerService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        // Ignore our own ongoing foreground notifications
        if (sbn.packageName == packageName) {
            return
        }

        serviceScope.launch {
            processAndForwardNotification(sbn)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        Log.d(TAG, "Notification removed: ${sbn.key}")
        // Could notify Mac if dismissed notifications should be mirrored
    }

    /**
     * Extracts readable details and actions from a status bar notification.
     */
    private fun processAndForwardNotification(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle()

        val packageName = sbn.packageName ?: "android"
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: ""

        // Skip completely empty notifications (such as system background badges)
        if (title.isBlank() && text.isBlank()) {
            return
        }

        val packageManager = applicationContext.packageManager
        val appName = runCatching {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        }.getOrDefault(packageName)

        // Check if notification contains RemoteInput for inline replies
        val replyAction = findRemoteInputAction(notification)
        val hasReplyAction = replyAction != null

        // Extract small / large icon as base64 thumbnail
        val iconBase64 = extractIconBase64(packageManager, packageName, notification)

        val forwardMessage = ProtocolMessage.NotificationForward(
            id = sbn.id,
            packageName = packageName,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            hasReplyAction = hasReplyAction,
            key = sbn.key,
            iconBase64 = iconBase64
        )

        Log.d(TAG, "Forwarding notification from $appName: $title")
        _notificationEvents.tryEmit(forwardMessage)

        // Route directly to ConnectionService
        ConnectionService.broadcastProtocolMessage(forwardMessage)
    }

    /**
     * Finds any Action with a direct reply RemoteInput (e.g., messaging apps).
     */
    private fun findRemoteInputAction(notification: Notification): Notification.Action? {
        val actions = notification.actions ?: return null
        for (action in actions) {
            val remoteInputs = action.remoteInputs ?: continue
            for (ri in remoteInputs) {
                if (ri.allowFreeFormInput) {
                    return action
                }
            }
        }
        return null
    }

    /**
     * Sends an inline reply back to the originating app using RemoteInput pending intent.
     */
    fun sendReply(notificationKey: String, replyText: String): Boolean {
        val activeNotifs = runCatching { activeNotifications }.getOrNull() ?: return false
        val sbn = activeNotifs.find { it.key == notificationKey } ?: run {
            Log.w(TAG, "Notification key not found for reply: $notificationKey")
            return false
        }

        val action = findRemoteInputAction(sbn.notification) ?: run {
            Log.w(TAG, "No RemoteInput action available for $notificationKey")
            return false
        }

        val remoteInputs = action.remoteInputs ?: return false
        val replyRemoteInput = remoteInputs.firstOrNull { it.allowFreeFormInput } ?: return false

        return runCatching {
            val intent = Intent()
            val bundle = Bundle()
            bundle.putCharSequence(replyRemoteInput.resultKey, replyText)
            RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
            action.actionIntent.send(this, 0, intent)
            Log.i(TAG, "Successfully sent inline reply to notification: $notificationKey")
            true
        }.getOrElse { e ->
            Log.e(TAG, "Failed sending reply to notification", e)
            false
        }
    }

    /**
     * Extracts application or notification icon and compresses to base64 string.
     */
    private fun extractIconBase64(pm: PackageManager, pkg: String, notification: Notification): String? {
        return runCatching {
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
    }

    companion object {
        private const val TAG = "NotificationListener"

        @Volatile
        var instance: NotificationListenerService? = null
            private set

        private val _notificationEvents = MutableSharedFlow<ProtocolMessage.NotificationForward>(replay = 10)
        val notificationEvents = _notificationEvents.asSharedFlow()

        /**
         * Dispatches a remote reply command received from Mac.
         */
        fun replyToNotification(key: String, replyText: String): Boolean {
            val current = instance
            return current?.sendReply(key, replyText) ?: false
        }
    }
}
