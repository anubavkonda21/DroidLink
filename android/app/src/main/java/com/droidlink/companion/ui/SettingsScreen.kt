/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Settings Screen covering connection discovery, notification access, and app info.
 */

package com.droidlink.companion.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Router
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.droidlink.companion.ui.theme.Accents
import com.droidlink.companion.ui.theme.GlassSwitch
import com.droidlink.companion.utils.Constants
import com.droidlink.companion.utils.Features
import com.droidlink.companion.utils.PermissionHelper

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE) }

    var preferredMode by remember { prefs.stringPref(Constants.PREF_KEY_PREFERRED_MODE, Constants.MODE_AUTO) }
    var servicePort by remember { prefs.stringPref(Constants.PREF_KEY_PORT, Constants.DEFAULT_CONTROL_PORT.toString()) }
    var autoStartOnBoot by remember { mutableStateOf(prefs.getBoolean(Constants.PREF_KEY_AUTO_CONNECT, true)) }
    var notificationsOn by remember { mutableStateOf(Features.isOn(context, Features.NOTIFICATIONS)) }

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
            text = "Notifications, connection and app info",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(20.dp))

        // SECTION: Notifications
        SettingsSectionHeader(icon = Icons.Default.Notifications, title = "Notifications", color = Accents.Pink)
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsSwitchRow(
                    title = "Forward Phone Notifications",
                    subtitle = "Send notifications from this phone to your Mac",
                    checked = notificationsOn,
                    onCheckedChange = {
                        notificationsOn = it
                        Features.set(context, Features.NOTIFICATIONS, it)
                    }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

                SettingsClickableRow(
                    title = "Notification Access",
                    subtitle = if (PermissionHelper.isNotificationServiceEnabled(context))
                        "Allowed in Android settings" else "Tap to enable in Android settings",
                    onClick = {
                        context.startActivity(PermissionHelper.createNotificationListenerSettingsIntent())
                    }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // SECTION: Connection
        SettingsSectionHeader(icon = Icons.Default.Router, title = "Connection & Discovery", color = Accents.Blue)
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                SettingsSwitchRow(
                    title = "Start in Background on Boot",
                    subtitle = "Automatically resume notification forwarding after restarting your phone",
                    checked = autoStartOnBoot,
                    onCheckedChange = {
                        autoStartOnBoot = it
                        prefs.edit().putBoolean(Constants.PREF_KEY_AUTO_CONNECT, it).apply()
                    }
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

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

        // SECTION: About
        SettingsSectionHeader(icon = Icons.Default.Info, title = "About", color = Accents.Teal)
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "DroidLink Notifications for Android",
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
                    subtitle = "github.com/anubavkonda21/DroidLink",
                    onClick = {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/anubavkonda21/DroidLink"))
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

    if (showLicensesDialog) {
        AlertDialog(
            onDismissRequest = { showLicensesDialog = false },
            title = { Text("Open Source Licenses") },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        "DroidLink is built using open source libraries:\n\n" +
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
private fun SettingsSectionHeader(icon: ImageVector, title: String, color: Color) {
    Row(
        modifier = Modifier.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
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
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingsSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        GlassSwitch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private fun android.content.SharedPreferences.stringPref(key: String, default: String) =
    object : androidx.compose.runtime.MutableState<String> {
        private val state = mutableStateOf(getString(key, default) ?: default)
        override var value: String
            get() = state.value
            set(v) { state.value = v; edit().putString(key, v).apply() }
        override fun component1() = value
        override fun component2(): (String) -> Unit = { value = it }
    }
