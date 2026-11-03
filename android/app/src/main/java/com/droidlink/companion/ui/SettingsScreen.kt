/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * User Settings Screen covering video encoder controls, network preference,
 * clipboard automation, security PINs, encryption, and open-source licenses.
 */

package com.droidlink.companion.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.droidlink.companion.utils.Constants
import kotlin.math.roundToInt

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE) }

    // Every setting is saved as it changes, so it survives app restarts and updates
    // Video settings
    var selectedResolution by remember { prefs.stringPref("resolution", "1080p (1920x1080)") }
    var selectedFps by remember { prefs.intPref("fps", 60) }
    var selectedCodec by remember { prefs.stringPref("codec", "H.264 (AVC)") }
    var bitrateMbps by remember { prefs.floatPref("bitrate_mbps", 8.0f) }

    // Connection settings
    var preferredMode by remember { prefs.stringPref("preferred_mode", Constants.MODE_AUTO) }
    var servicePort by remember { prefs.stringPref("service_port", Constants.DEFAULT_CONTROL_PORT.toString()) }

    // Clipboard & Notifications
    var clipboardAutoSync by remember { prefs.boolPref("clipboard_auto_sync", true) }
    var otpForwarding by remember { prefs.boolPref("otp_forwarding", true) }
    var autoAcceptFiles by remember { prefs.boolPref("auto_accept_files", false) }

    // Security
    var requirePin by remember { prefs.boolPref("require_pin", false) }
    var encryptionEnabled by remember { prefs.boolPref("encryption", true) }

    // Dialogs
    var showResolutionDialog by remember { mutableStateOf(false) }
    var showModeDialog by remember { mutableStateOf(false) }
    var showLicensesDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Text(
            text = "Settings",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            text = "Configure mirroring quality, network channels, and security",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(20.dp))

        // SECTION: Video Settings
        SettingsSectionHeader(icon = Icons.Default.Videocam, title = "Video Streaming")
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsClickableRow(
                    title = "Resolution",
                    subtitle = selectedResolution,
                    onClick = { showResolutionDialog = true }
                )
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text("Frame Rate", style = MaterialTheme.typography.bodyLarge)
                        Text("$selectedFps FPS", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    }
                    Row {
                        listOf(30, 60, 90, 120).forEach { fps ->
                            TextButton(onClick = { selectedFps = fps }) {
                                Text(
                                    text = "$fps",
                                    fontWeight = if (selectedFps == fps) FontWeight.Bold else FontWeight.Normal,
                                    color = if (selectedFps == fps) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                Column {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Bitrate", style = MaterialTheme.typography.bodyLarge)
                        Text("${bitrateMbps.roundToInt()} Mbps", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                    }
                    Slider(
                        value = bitrateMbps,
                        onValueChange = { bitrateMbps = it },
                        valueRange = 2f..25f,
                        steps = 22
                    )
                }

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsClickableRow(
                    title = "Video Codec",
                    subtitle = selectedCodec,
                    onClick = {
                        selectedCodec = if (selectedCodec.contains("H.264")) "H.265 (HEVC)" else "H.264 (AVC)"
                        Toast.makeText(context, "Selected codec: $selectedCodec", Toast.LENGTH_SHORT).show()
                    }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // SECTION: Connection
        SettingsSectionHeader(icon = Icons.Default.Router, title = "Connection & Discovery")
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsClickableRow(
                    title = "Preferred Transport",
                    subtitle = preferredMode,
                    onClick = { showModeDialog = true }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Service Port", style = MaterialTheme.typography.bodyLarge)
                        Text("mDNS and TCP listen port", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    OutlinedTextField(
                        value = servicePort,
                        onValueChange = { servicePort = it },
                        modifier = Modifier.width(100.dp),
                        singleLine = true
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // SECTION: Clipboard & File Transfer
        SettingsSectionHeader(icon = Icons.Default.Sync, title = "Ecosystem Sync")
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsSwitchRow(
                    title = "Auto-sync Clipboard",
                    subtitle = "Instantly copy text and links to/from Mac",
                    checked = clipboardAutoSync,
                    onCheckedChange = { clipboardAutoSync = it }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsSwitchRow(
                    title = "Detect & Forward OTPs",
                    subtitle = "Extract 2FA verification codes for one-click copy on Mac",
                    checked = otpForwarding,
                    onCheckedChange = { otpForwarding = it }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsSwitchRow(
                    title = "Auto-accept Files",
                    subtitle = "Save incoming files from paired Mac to Downloads/DroidLink",
                    checked = autoAcceptFiles,
                    onCheckedChange = { autoAcceptFiles = it }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // SECTION: Security
        SettingsSectionHeader(icon = Icons.Default.Lock, title = "Security & Encryption")
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsSwitchRow(
                    title = "Require PIN Pairing",
                    subtitle = "Verify 6-digit PIN on Mac before accepting stream",
                    checked = requirePin,
                    onCheckedChange = { requirePin = it }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsSwitchRow(
                    title = "End-to-End Encryption",
                    subtitle = "Encrypt video, notifications, and clipboard traffic",
                    checked = encryptionEnabled,
                    onCheckedChange = { encryptionEnabled = it }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // SECTION: About
        SettingsSectionHeader(icon = Icons.Default.Info, title = "About")
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "DroidLink Companion for Android",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Version 1.0.0 (Build 1) • Target SDK 35",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsClickableRow(
                    title = "GitHub Repository",
                    subtitle = "github.com/droidlink/droidlink",
                    onClick = {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com"))
                        context.startActivity(browserIntent)
                    }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsClickableRow(
                    title = "Open Source Licenses",
                    subtitle = "View software notices and dependencies",
                    onClick = { showLicensesDialog = true }
                )
            }
        }

        Spacer(modifier = Modifier.height(30.dp))
    }

    // Resolution Picker Dialog
    if (showResolutionDialog) {
        val options = listOf("720p (1280x720)", "1080p (1920x1080)", "1440p (2560x1440)", "Native Display Resolution")
        AlertDialog(
            onDismissRequest = { showResolutionDialog = false },
            title = { Text("Select Resolution") },
            text = {
                Column {
                    options.forEach { opt ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    selectedResolution = opt
                                    showResolutionDialog = false
                                }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = selectedResolution == opt,
                                onClick = {
                                    selectedResolution = opt
                                    showResolutionDialog = false
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(opt)
                        }
                    }
                }
            },
            confirmButton = {}
        )
    }

    // Preferred Transport Dialog
    if (showModeDialog) {
        val modes = listOf(Constants.MODE_AUTO, Constants.MODE_WIFI, Constants.MODE_USB)
        AlertDialog(
            onDismissRequest = { showModeDialog = false },
            title = { Text("Preferred Transport") },
            text = {
                Column {
                    modes.forEach { mode ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    preferredMode = mode
                                    showModeDialog = false
                                }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = preferredMode == mode,
                                onClick = {
                                    preferredMode = mode
                                    showModeDialog = false
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(mode)
                        }
                    }
                }
            },
            confirmButton = {}
        )
    }

    // Open Source Licenses Dialog
    if (showLicensesDialog) {
        AlertDialog(
            onDismissRequest = { showLicensesDialog = false },
            title = { Text("Open Source Licenses") },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        "DroidLink is built using high-performance open source libraries:\n\n" +
                                "• Jetpack Compose & Material 3 (Apache 2.0)\n" +
                                "• Kotlin Coroutines & Serialization (Apache 2.0)\n" +
                                "• OkHttp (Apache 2.0)\n" +
                                "• AndroidX Core, Lifecycle, Navigation (Apache 2.0)\n\n" +
                                "Copyright (c) 2026 DroidLink Project. Licensed under the MIT License."
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showLicensesDialog = false }) {
                    Text("Close")
                }
            }
        )
    }
}

@Composable
private fun SettingsSectionHeader(icon: ImageVector, title: String) {
    Row(
        modifier = Modifier.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(text = title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SettingsClickableRow(title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingsSwitchRow(title: String, subtitle: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

/** A Compose state that writes every change straight to SharedPreferences. */
private class PrefState<T>(initial: T, private val save: (T) -> Unit) : androidx.compose.runtime.MutableState<T> {
    private val state = mutableStateOf(initial)
    override var value: T
        get() = state.value
        set(v) { state.value = v; save(v) }
    override fun component1() = value
    override fun component2(): (T) -> Unit = { value = it }
}

private fun android.content.SharedPreferences.boolPref(key: String, default: Boolean) =
    PrefState(getBoolean(key, default)) { edit().putBoolean(key, it).apply() }
private fun android.content.SharedPreferences.stringPref(key: String, default: String) =
    PrefState(getString(key, default) ?: default) { edit().putString(key, it).apply() }
private fun android.content.SharedPreferences.intPref(key: String, default: Int) =
    PrefState(getInt(key, default)) { edit().putInt(key, it).apply() }
private fun android.content.SharedPreferences.floatPref(key: String, default: Float) =
    PrefState(getFloat(key, default)) { edit().putFloat(key, it).apply() }
