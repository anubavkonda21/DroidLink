package com.droidlink.companion.utils

import android.content.Context
import com.droidlink.companion.models.ProtocolMessage

/**
 * In-app on/off switch for notification forwarding. Saved in SharedPreferences, on by default.
 */
object Features {
    const val NOTIFICATIONS = "feature_notifications"

    fun isOn(context: Context, key: String = NOTIFICATIONS) =
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE).getBoolean(key, true)

    fun set(context: Context, key: String = NOTIFICATIONS, on: Boolean) =
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(key, on).apply()

    fun keyFor(message: ProtocolMessage): String? = when (message) {
        is ProtocolMessage.NotificationForward -> NOTIFICATIONS
        else -> null
    }
}
