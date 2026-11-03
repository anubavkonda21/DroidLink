/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Centralized runtime permission checks, notification listener verification, and system settings navigation.
 */

package com.droidlink.companion.utils

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.droidlink.companion.services.NotificationListenerService

/**
 * Utility helper managing Android runtime permissions, specialized system settings intents,
 * and service authorization verification.
 */
object PermissionHelper {

    /**
     * Core permissions required for network synchronization, foreground execution, and basic telemetry.
     */
    val CORE_PERMISSIONS: Array<String> = buildList {
        add(Manifest.permission.INTERNET)
        add(Manifest.permission.ACCESS_NETWORK_STATE)
        add(Manifest.permission.ACCESS_WIFI_STATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    /**
     * Telephony & Contact permissions for the Call Bridge ecosystem feature.
     */
    val CALL_BRIDGE_PERMISSIONS = arrayOf(
        Manifest.permission.READ_PHONE_STATE,
        Manifest.permission.CALL_PHONE,
        Manifest.permission.READ_CONTACTS
    )

    /**
     * SMS permissions for the Mac's Messages page (read conversations, send replies, see new texts).
     */
    val SMS_PERMISSIONS = arrayOf(
        Manifest.permission.READ_SMS,
        Manifest.permission.SEND_SMS,
        Manifest.permission.RECEIVE_SMS
    )

    /**
     * Storage & Media permissions for two-way file sharing.
     */
    val STORAGE_PERMISSIONS: Array<String> = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.READ_MEDIA_IMAGES)
            add(Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            add(Manifest.permission.READ_EXTERNAL_STORAGE)
            add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
    }.toTypedArray()

    /**
     * Internal audio capture permission.
     */
    val AUDIO_PERMISSIONS = arrayOf(
        Manifest.permission.RECORD_AUDIO
    )

    /**
     * Complete aggregate list of standard dangerous runtime permissions needed across all features.
     */
    val ALL_APP_PERMISSIONS: Array<String> = (CORE_PERMISSIONS + CALL_BRIDGE_PERMISSIONS + SMS_PERMISSIONS + STORAGE_PERMISSIONS + AUDIO_PERMISSIONS).distinct().toTypedArray()

    /**
     * Checks if a single permission is granted.
     */
    fun isPermissionGranted(context: Context, permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Checks if all permissions in the specified list are granted.
     */
    fun arePermissionsGranted(context: Context, permissions: Array<String>): Boolean {
        return permissions.all { isPermissionGranted(context, it) }
    }

    /**
     * Returns true if all core requirements (network + notifications) are satisfied.
     */
    fun hasCorePermissions(context: Context): Boolean {
        return arePermissionsGranted(context, CORE_PERMISSIONS)
    }

    /**
     * Returns true if Call Bridge permissions are fully granted.
     */
    fun hasCallBridgePermissions(context: Context): Boolean {
        return arePermissionsGranted(context, CALL_BRIDGE_PERMISSIONS)
    }

    /**
     * Returns true if File Transfer storage permissions are fully granted.
     */
    fun hasStoragePermissions(context: Context): Boolean {
        return arePermissionsGranted(context, STORAGE_PERMISSIONS)
    }

    /**
     * Verifies if the app has been granted Notification Access by the user in System Settings.
     */
    fun isNotificationServiceEnabled(context: Context): Boolean {
        val cn = ComponentName(context, NotificationListenerService::class.java)
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }

    /**
     * Creates an Intent directing the user to system Notification Listener settings.
     */
    fun createNotificationListenerSettingsIntent(): Intent {
        return Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }

    /**
     * Creates an Intent directing the user to app details settings page for manual permission grant.
     */
    fun createAppSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }

    /**
     * Checks if battery optimization is ignored for smooth background operation.
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: true
    }

    /**
     * Intent to request exemption from battery optimizations.
     */
    fun createIgnoreBatteryOptimizationIntent(context: Context): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }
}
