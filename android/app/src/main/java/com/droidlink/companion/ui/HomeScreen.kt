/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Home Screen focused solely on pairing with the Mac and forwarding phone notifications.
 */

package com.droidlink.companion.ui

import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.droidlink.companion.models.ConnectionState
import com.droidlink.companion.services.ConnectionService
import com.droidlink.companion.services.NotificationListenerService
import com.droidlink.companion.ui.theme.Accents
import com.droidlink.companion.ui.theme.ForestGreen
import com.droidlink.companion.ui.theme.GlassSwitch
import com.droidlink.companion.ui.theme.MintLight
import com.droidlink.companion.utils.Constants
import com.droidlink.companion.utils.Features
import com.droidlink.companion.utils.PermissionHelper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ActivityLogItem(
    val id: String = System.currentTimeMillis().toString(),
    val title: String,
    val description: String,
    val time: String = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
)

@Composable
fun HomeScreen(
    onRequestPermissions: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val connectionState by ConnectionService.connectionState.collectAsState()
    val latencyMs by ConnectionService.latencyMs.collectAsState()

    var showManualIpDialog by remember { mutableStateOf(false) }
    var targetIpInput by remember { mutableStateOf("") }
    var targetPortInput by remember { mutableStateOf(Constants.DEFAULT_CONTROL_PORT.toString()) }

    var notificationsEnabled by remember { mutableStateOf(Features.isOn(context, Features.NOTIFICATIONS)) }
    var hasNotificationAccess by remember { mutableStateOf(PermissionHelper.isNotificationServiceEnabled(context)) }
    var batteryUnrestricted by remember { mutableStateOf(PermissionHelper.isIgnoringBatteryOptimizations(context)) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                hasNotificationAccess = PermissionHelper.isNotificationServiceEnabled(context)
                batteryUnrestricted = PermissionHelper.isIgnoringBatteryOptimizations(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val activityLogs = remember {
        mutableStateListOf(
            ActivityLogItem(title = "Notification Bridge Ready", description = "Listening for Mac connection")
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // App Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(
                    text = "DroidLink",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = "Phone Notifications for Mac",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Surface(
                shape = RoundedCornerShape(14.dp),
                color = if (connectionState.isConnected) MintLight else MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier.size(44.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.Bolt,
                        contentDescription = if (connectionState.isConnected) "Connected" else "Not connected",
                        tint = if (connectionState.isConnected) ForestGreen else Color.Gray
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Connection Status Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = glassCardColors(),
            border = glassBorder()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val statusDotColor = when (connectionState) {
                        is ConnectionState.Connected -> Color(0xFF2E7D32)
                        is ConnectionState.Mirroring -> Color(0xFF00897B)
                        is ConnectionState.Connecting, is ConnectionState.Discovering -> Color(0xFFF57F17)
                        is ConnectionState.Disconnected -> Color(0xFFC62828)
                    }

                    Box(
                        modifier = Modifier
                            .size(14.dp)
                            .clip(CircleShape)
                            .background(statusDotColor)
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = when (connectionState) {
                            is ConnectionState.Connected -> "Connected to ${(connectionState as ConnectionState.Connected).deviceName}"
                            is ConnectionState.Mirroring -> "Connected"
                            is ConnectionState.Connecting -> "Connecting to ${(connectionState as ConnectionState.Connecting).targetHost}…"
                            is ConnectionState.Discovering -> "Waiting for Mac…"
                            is ConnectionState.Disconnected -> "Not Connected"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                if (connectionState.isConnected) {
                    Text(
                        text = listOfNotNull(
                            (connectionState as? ConnectionState.Connected)?.hostAddress
                                ?.let { if (it.startsWith("127.") || it == "localhost") "USB" else "Wi-Fi • $it" },
                            latencyMs.takeIf { it > 0 }?.let { "$it ms" }
                        ).joinToString(" • "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        text = "Make sure DroidLink for macOS is running on the same network or connected via USB cable.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    if (connectionState.isConnected) {
                        Button(
                            onClick = {
                                val intent = Intent(context, ConnectionService::class.java).apply {
                                    action = Constants.ACTION_DISCONNECT
                                }
                                context.startService(intent)
                                activityLogs.add(0, ActivityLogItem(title = "Disconnected", description = "Manual disconnect requested"))
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.LinkOff, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Disconnect")
                        }
                    } else {
                        Button(
                            onClick = { showManualIpDialog = true },
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.Link, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Connect to Mac")
                        }

                        FilledTonalButton(
                            onClick = {
                                val devOptions = Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    .putExtra(":settings:fragment_args_key", "toggle_adb_wireless")
                                try {
                                    context.startActivity(devOptions)
                                    Toast.makeText(
                                        context,
                                        "Open Wireless debugging, then tap \"Pair device with QR code\" and scan the code on your Mac.",
                                        Toast.LENGTH_LONG
                                    ).show()
                                } catch (_: android.content.ActivityNotFoundException) {
                                    Toast.makeText(
                                        context,
                                        "Turn on Developer options first: Settings › About phone › tap Build number 7 times.",
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                                activityLogs.add(0, ActivityLogItem(title = "Pair with Mac", description = "Opened Wireless debugging settings"))
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Pair with QR")
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Notification Forwarding Card (the sole feature)
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = glassCardColors(),
            border = glassBorder()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background((if (notificationsEnabled && hasNotificationAccess) Accents.Pink else Color.Gray).copy(alpha = 0.18f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.Default.NotificationsActive,
                            contentDescription = null,
                            tint = if (notificationsEnabled && hasNotificationAccess) Accents.Pink else Color.Gray,
                            modifier = Modifier.size(22.dp)
                        )
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            "Forward Notifications",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            when {
                                !hasNotificationAccess -> "Notification access required in Android Settings"
                                NotificationListenerService.instance == null && notificationsEnabled -> "Waiting for listener service…"
                                notificationsEnabled -> "Sending phone notifications to your Mac"
                                else -> "Paused: nothing is sent to your Mac"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    GlassSwitch(
                        checked = notificationsEnabled,
                        onCheckedChange = {
                            notificationsEnabled = it
                            Features.set(context, Features.NOTIFICATIONS, it)
                        },
                        onColor = Accents.Pink
                    )
                }

                if (!hasNotificationAccess) {
                    Spacer(Modifier.height(12.dp))
                    Button(
                        onClick = {
                            context.startActivity(PermissionHelper.createNotificationListenerSettingsIntent())
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Enable Notification Access")
                    }
                }

                if (!batteryUnrestricted) {
                    Spacer(Modifier.height(10.dp))
                    FilledTonalButton(
                        onClick = {
                            runCatching {
                                context.startActivity(PermissionHelper.createIgnoreBatteryOptimizationIntent(context))
                            }.onFailure {
                                context.startActivity(PermissionHelper.createAppSettingsIntent(context))
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Allow Background Running (Battery)")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Recent Activity Section
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Recent Activity",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Icon(Icons.Default.History, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        Spacer(modifier = Modifier.height(10.dp))

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            activityLogs.take(20).forEach { log ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = glassCardColors(),
                    border = glassBorder()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(log.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                            Text(log.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(log.time, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                }
            }
        }
    }

    if (showManualIpDialog) {
        AlertDialog(
            onDismissRequest = { showManualIpDialog = false },
            title = { Text("Connect to Mac IP") },
            text = {
                Column {
                    Text("Enter the local IP address and port of your Mac:")
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = targetIpInput,
                        onValueChange = { targetIpInput = it },
                        label = { Text("Mac IP Address") },
                        placeholder = { Text("192.168.1.150") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = targetPortInput,
                        onValueChange = { targetPortInput = it },
                        label = { Text("Port") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val port = targetPortInput.toIntOrNull() ?: Constants.DEFAULT_CONTROL_PORT
                        if (targetIpInput.isNotBlank()) {
                            val intent = Intent(context, ConnectionService::class.java).apply {
                                action = Constants.ACTION_CONNECT
                                putExtra(Constants.EXTRA_TARGET_IP, targetIpInput.trim())
                                putExtra(Constants.EXTRA_TARGET_PORT, port)
                            }
                            context.startService(intent)
                            activityLogs.add(0, ActivityLogItem(title = "Connecting", description = "Target $targetIpInput:$port"))
                        }
                        showManualIpDialog = false
                    }
                ) {
                    Text("Connect")
                }
            },
            dismissButton = {
                TextButton(onClick = { showManualIpDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun glassCardColors() = CardDefaults.cardColors(
    containerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)
)

@Composable
private fun glassBorder() = BorderStroke(
    1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
)
