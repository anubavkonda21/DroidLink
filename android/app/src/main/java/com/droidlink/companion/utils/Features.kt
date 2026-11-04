package com.droidlink.companion.utils

import android.content.Context
import com.droidlink.companion.models.ProtocolMessage

/**
 * In-app on/off switches for each sync feature (Status screen). Saved in SharedPreferences, on by default.
 * Android doesn't let an app revoke its own permissions, so these stop the data instead; the Status
 * screen links to the system page for revoking the permissions themselves.
 */
object Features {
    const val NOTIFICATIONS = "feature_notifications"
    const val CLIPBOARD = "feature_clipboard"
    const val FILES = "feature_files"
    const val CALLS = "feature_calls"

    fun isOn(context: Context, key: String) =
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE).getBoolean(key, true)

    fun set(context: Context, key: String, on: Boolean) =
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(key, on).apply()

    /** Which switch controls this outgoing message; null = always allowed (heartbeats, status, commands). */
    fun keyFor(message: ProtocolMessage): String? = when (message) {
        is ProtocolMessage.NotificationForward -> if (message.isCall) CALLS else NOTIFICATIONS
        is ProtocolMessage.CallEvent -> CALLS
        is ProtocolMessage.ClipboardSync -> CLIPBOARD
        is ProtocolMessage.FileTransferOffer -> FILES
        else -> null
    }
}
