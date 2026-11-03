/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Boot receiver to launch background connectivity service on device boot if auto-connect is enabled.
 */

package com.droidlink.companion.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.droidlink.companion.services.ConnectionService
import com.droidlink.companion.utils.Constants

/**
 * Listens for system boot completion and restores background connectivity services.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "Received broadcast action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            val prefs = context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            val autoConnectEnabled = prefs.getBoolean(Constants.PREF_KEY_AUTO_CONNECT, false)

            if (autoConnectEnabled) {
                Log.i(TAG, "Auto-connect enabled. Starting ConnectionService on boot.")
                val serviceIntent = Intent(context, ConnectionService::class.java).apply {
                    this.action = Constants.ACTION_START_SERVER
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } else {
                Log.d(TAG, "Auto-connect disabled. Skipping service startup.")
            }
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
