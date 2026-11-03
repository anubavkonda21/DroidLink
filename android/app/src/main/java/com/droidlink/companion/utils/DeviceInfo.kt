/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * System hardware, battery, storage, and network state queries for device telemetry.
 */

package com.droidlink.companion.utils

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.DisplayMetrics
import android.view.WindowManager
import com.droidlink.companion.models.ProtocolMessage
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Utility helper for retrieving device telemetry, hardware attributes, and network metrics.
 */
class DeviceInfo(private val context: Context) {

    /**
     * User-facing device brand and marketing model (e.g. "Google Pixel 8 Pro").
     */
    val deviceName: String
        get() = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    /**
     * Internal manufacturer hardware identifier.
     */
    val manufacturer: String
        get() = Build.MANUFACTURER

    /**
     * Model code.
     */
    val model: String
        get() = Build.MODEL

    /**
     * Android OS version string (e.g. "14").
     */
    val androidVersion: String
        get() = Build.VERSION.RELEASE

    /**
     * Android SDK integer level (e.g. 34).
     */
    val sdkInt: Int
        get() = Build.VERSION.SDK_INT

    /**
     * Retrieves current battery status including level, charging state, and temperature.
     */
    fun getBatteryInfo(): BatteryInfo {
        val batteryIntent = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        ) ?: return BatteryInfo(level = 100, isCharging = false, temperatureCelsius = 25.0f)

        val level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val percent = if (level >= 0 && scale > 0) (level * 100) / scale else 100

        val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        val tempTenths = batteryIntent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val tempCelsius = tempTenths / 10.0f

        return BatteryInfo(
            level = percent,
            isCharging = isCharging,
            temperatureCelsius = tempCelsius
        )
    }

    /**
     * Retrieves storage capacity statistics in bytes.
     */
    fun getStorageInfo(): StorageInfo {
        return runCatching {
            val path = Environment.getDataDirectory()
            val stat = StatFs(path.path)
            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            val availableBlocks = stat.availableBlocksLong

            val totalBytes = totalBlocks * blockSize
            val freeBytes = availableBlocks * blockSize
            StorageInfo(totalBytes = totalBytes, freeBytes = freeBytes)
        }.getOrDefault(StorageInfo(totalBytes = 64_000_000_000L, freeBytes = 32_000_000_000L))
    }

    /**
     * Retrieves current Wi-Fi network SSID and device local IPv4 address.
     */
    fun getNetworkInfo(): NetworkInfo {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork
        val capabilities = connectivityManager.getNetworkCapabilities(network)

        val isWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        var ssid = "Unknown"
        var ipAddress = getLocalIpAddress()

        if (isWifi) {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val connectionInfo: WifiInfo? = wifiManager.connectionInfo
            val rawSsid = connectionInfo?.ssid
            if (!rawSsid.isNullOrBlank() && rawSsid != "<unknown ssid>") {
                ssid = rawSsid.trim('"')
            } else {
                ssid = "Wi-Fi Connected"
            }
        }

        return NetworkInfo(
            ssid = ssid,
            ipAddress = ipAddress,
            isWifiConnected = isWifi
        )
    }

    /**
     * Returns the physical screen resolution and pixel density.
     */
    fun getDisplayMetrics(): DisplaySize {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)

        return DisplaySize(
            width = metrics.widthPixels,
            height = metrics.heightPixels,
            densityDpi = metrics.densityDpi,
            refreshRate = runCatching {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.refreshRate
            }.getOrDefault(60.0f)
        )
    }

    /**
     * Generates a snapshot of device status for Mac sync.
     */
    fun getDeviceStatusMessage(): ProtocolMessage.DeviceStatus {
        val battery = getBatteryInfo()
        val storage = getStorageInfo()
        val network = getNetworkInfo()

        val thermalStatus = when {
            battery.temperatureCelsius > 42.0f -> "Critical"
            battery.temperatureCelsius > 38.0f -> "Warm"
            else -> "Normal"
        }

        return ProtocolMessage.DeviceStatus(
            batteryLevel = battery.level,
            isCharging = battery.isCharging,
            thermalStatus = thermalStatus,
            wifiSsid = network.ssid,
            freeStorageBytes = storage.freeBytes,
            totalStorageBytes = storage.totalBytes
        )
    }

    /**
     * Scans active network interfaces to locate device local IPv4 address.
     */
    private fun getLocalIpAddress(): String {
        return runCatching {
            val interfaces = NetworkInterface.getNetworkInterfaces().toList()
            for (intf in interfaces) {
                if (intf.isLoopback || !intf.isUp) continue
                for (addr in intf.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return@runCatching addr.hostAddress ?: "127.0.0.1"
                    }
                }
            }
            "127.0.0.1"
        }.getOrDefault("127.0.0.1")
    }

    data class BatteryInfo(
        val level: Int,
        val isCharging: Boolean,
        val temperatureCelsius: Float
    )

    data class StorageInfo(
        val totalBytes: Long,
        val freeBytes: Long
    ) {
        val freePercentage: Int
            get() = if (totalBytes > 0) ((freeBytes * 100) / totalBytes).toInt() else 0
    }

    data class NetworkInfo(
        val ssid: String,
        val ipAddress: String,
        val isWifiConnected: Boolean
    )

    data class DisplaySize(
        val width: Int,
        val height: Int,
        val densityDpi: Int,
        val refreshRate: Float
    )
}
