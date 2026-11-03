/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Home Screen providing real-time pairing status, connection controls,
 * manual IP dialog, quick actions, and recent activity history.
 */

package com.droidlink.companion.ui

import com.droidlink.companion.models.ProtocolMessage

import androidx.compose.foundation.layout.ExperimentalLayoutApi

import androidx.compose.foundation.layout.FlowRow

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.CastConnected
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.animation.animateContentSize
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.BatteryStd
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.OutlinedCard
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.droidlink.companion.R
import com.droidlink.companion.models.ConnectionState
import com.droidlink.companion.services.ClipboardService
import com.droidlink.companion.services.ConnectionService
import com.droidlink.companion.services.FileServerService
import com.droidlink.companion.services.ScreenCaptureService
import com.droidlink.companion.utils.Constants
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ActivityLogItem(
    val id: String = System.currentTimeMillis().toString(),
    val title: String,
    val description: String,
    val time: String = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HomeScreen(
    onRequestScreenCapture: () -> Unit,
    onRequestPermissions: () -> Unit
) {
    val context = LocalContext.current
    val connectionState by ConnectionService.connectionState.collectAsState()
    val latencyMs by ConnectionService.latencyMs.collectAsState()
    val macStatus by ConnectionService.macStatus.collectAsState()

    var showManualIpDialog by remember { mutableStateOf(false) }
    var targetIpInput by remember { mutableStateOf("") }
    var targetPortInput by remember { mutableStateOf(Constants.DEFAULT_CONTROL_PORT.toString()) }

    val activityLogs = remember {
        mutableStateListOf(
            ActivityLogItem(title = "App Initialized", description = "DroidLink companion background service active")
        )
    }

    // File picker launcher for Quick Action: Send File
    val sendToMac: (Uri?) -> Unit = { uri ->
        if (uri != null) {
            val intent = Intent(context, FileServerService::class.java).apply {
                action = Constants.ACTION_SEND_FILE
                putExtra(Constants.EXTRA_FILE_URI, uri)
                if (connectionState is ConnectionState.Connected) {
                    putExtra(Constants.EXTRA_TARGET_IP, (connectionState as ConnectionState.Connected).hostAddress)
                }
            }
            context.startService(intent)
            activityLogs.add(0, ActivityLogItem(title = "Sending File", description = uri.lastPathSegment ?: "File"))
            Toast.makeText(context, "Streaming file to Mac…", Toast.LENGTH_SHORT).show()
        }
    }
    val filePickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument(), sendToMac)
    val photoPickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia(), sendToMac)

    Column(
        modifier = Modifier
            .fillMaxSize()
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
                    text = "Android Companion",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier.size(44.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = if (connectionState.isConnected) Icons.Default.CastConnected else Icons.Default.Cast,
                        contentDescription = null,
                        tint = if (connectionState.isConnected) MaterialTheme.colorScheme.primary else Color.Gray
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Connection Status Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
            )
        ) {
            Column(
                modifier = Modifier.padding(20.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
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
                            is ConnectionState.Mirroring -> "Mirroring Active"
                            is ConnectionState.Connecting -> "Connecting to ${(connectionState as ConnectionState.Connecting).targetHost}…"
                            is ConnectionState.Discovering -> "Discovering Mac on Wi-Fi…"
                            is ConnectionState.Disconnected -> "Not Connected"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                if (connectionState.isConnected) {
                    Text(
                        // a loopback host means the link runs through the adb tunnel (USB)
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

                // Action Controls Row
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
                            Text("Disconnect", maxLines = 1, softWrap = false)
                        }

                        // Mirroring Toggle Button
                        if (ScreenCaptureService.isRunning) {
                            OutlinedButton(
                                onClick = {
                                    val stopIntent = Intent(context, ScreenCaptureService::class.java).apply {
                                        action = Constants.ACTION_STOP_SCREEN_CAPTURE
                                    }
                                    context.startService(stopIntent)
                                    activityLogs.add(0, ActivityLogItem(title = "Mirroring Stopped", description = "User ended stream"))
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("Stop Mirror")
                            }
                        } else {
                            Button(
                                onClick = {
                                    onRequestScreenCapture()
                                    activityLogs.add(0, ActivityLogItem(title = "Mirror Requested", description = "Starting projection flow"))
                                },
                                contentPadding = PaddingValues(horizontal = 12.dp),
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.Default.Cast, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Mirror Screen", maxLines = 1, softWrap = false)
                            }
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
                                Toast.makeText(context, "Scanning QR Code from Mac app…", Toast.LENGTH_SHORT).show()
                                activityLogs.add(0, ActivityLogItem(title = "QR Scanner", description = "Opened pairing camera"))
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Scan QR")
                        }
                    }
                }
            }
        }

        macStatus?.takeIf { connectionState.isConnected }?.let {
            Spacer(modifier = Modifier.height(12.dp))
            MacCard(it)
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Quick Actions Section
        Text(
            text = "Quick Actions",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(10.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            QuickActionTile(
                onClick = {
                    // The app is in the foreground here, so Android lets it read the clipboard
                    val clip = (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager)
                        .primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
                    if (clip.isNotBlank()) {
                        ConnectionService.broadcastProtocolMessage(ProtocolMessage.ClipboardSync(text = clip))
                        Toast.makeText(context, "Synced clipboard to Mac", Toast.LENGTH_SHORT).show()
                        activityLogs.add(0, ActivityLogItem(title = "Clipboard Synced", description = clip.take(20)))
                    } else {
                        Toast.makeText(context, "Clipboard is empty", Toast.LENGTH_SHORT).show()
                    }
                },
                label = "Send Clipboard",
                icon = Icons.Default.ContentPaste
            )

            QuickActionTile(
                onClick = {
                    filePickerLauncher.launch(arrayOf("*/*"))
                },
                label = "Send File",
                icon = Icons.Default.UploadFile
            )

            QuickActionTile(
                onClick = {
                    photoPickerLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                },
                label = "Send Photo",
                icon = Icons.Default.Image
            )
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

        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(activityLogs, key = { it.id }) { log ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = log.title,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = log.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Text(
                            text = log.time,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }
                }
            }
        }
    }

    // Manual IP Dialog
    if (showManualIpDialog) {
        AlertDialog(
            onDismissRequest = { showManualIpDialog = false },
            title = { Text("Connect to Mac IP") },
            text = {
                Column {
                    Text("Enter the local IP address and port displayed on your Mac's DroidLink screen:")
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

/** Equal-width tile: icon above its label. */
@Composable
private fun RowScope.QuickActionTile(
    onClick: () -> Unit,
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    OutlinedCard(onClick = onClick, modifier = Modifier.weight(1f), shape = RoundedCornerShape(16.dp)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp, horizontal = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(6.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

private fun macCommand(action: String) =
    ConnectionService.broadcastProtocolMessage(ProtocolMessage.MacCommand(action))

/** The Mac's battery at a glance; tap to expand storage, volume, media and power controls. */
@Composable
private fun MacCard(status: kotlinx.serialization.json.JsonObject) {
    fun int(key: String) = status[key]?.jsonPrimitive?.intOrNull
    fun bool(key: String) = status[key]?.jsonPrimitive?.booleanOrNull == true
    var expanded by remember { mutableStateOf(false) }
    var confirmSleep by remember { mutableStateOf(false) }

    val battery = int("batteryLevel")
    val charging = bool("isCharging")
    val batteryColor = when {
        charging || (battery ?: 100) > 30 -> Color(0xFF43A047)
        battery!! >= 15 -> Color(0xFFFB8C00)
        else -> Color(0xFFE53935)
    }

    Card(
        onClick = { expanded = !expanded },
        modifier = Modifier.fillMaxWidth().animateContentSize(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Laptop, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        status["name"]?.jsonPrimitive?.content ?: "Mac",
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1
                    )
                    val minutes = int("minutesRemaining")
                    Text(
                        when {
                            battery == null -> "Plugged in"
                            charging -> "Charging" + (minutes?.let { " • full in ${it / 60}h ${it % 60}m" } ?: "")
                            bool("onPower") -> "Plugged in, not charging"
                            else -> "On battery" + (minutes?.let { " • ${it / 60}h ${it % 60}m left" } ?: "")
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                battery?.let {
                    Icon(
                        if (charging) Icons.Default.BatteryChargingFull else Icons.Default.BatteryStd,
                        contentDescription = null, tint = batteryColor, modifier = Modifier.size(20.dp)
                    )
                    Text("$it%", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = batteryColor)
                }
                Icon(
                    if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            battery?.let {
                Spacer(Modifier.height(12.dp))
                LinearProgressIndicator(
                    progress = { it / 100f },
                    color = batteryColor,
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp))
                )
            }

            if (expanded) {
                Spacer(Modifier.height(16.dp))
                val free = int("storageFreeGB") ?: 0
                val total = int("storageTotalGB")?.takeIf { it > 0 } ?: 1
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Storage, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Storage", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    Text("$free GB free of $total GB", style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(
                    progress = { (total - free) / total.toFloat() },
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp))
                )

                Spacer(Modifier.height(16.dp))
                val muted = bool("muted")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (muted) Icons.Default.VolumeOff else Icons.Default.VolumeUp, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (muted) "Muted" else "Volume ${int("volume") ?: 0}%", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    IconButton(onClick = { macCommand("volume_down") }) { Icon(Icons.Default.VolumeDown, "Volume down") }
                    IconButton(onClick = { macCommand("mute") }) { Icon(if (muted) Icons.Default.VolumeUp else Icons.Default.VolumeOff, if (muted) "Unmute" else "Mute") }
                    IconButton(onClick = { macCommand("volume_up") }) { Icon(Icons.Default.VolumeUp, "Volume up") }
                }

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    IconButton(onClick = { macCommand("previous") }) { Icon(Icons.Default.SkipPrevious, "Previous track") }
                    FilledTonalIconButton(onClick = { macCommand("play_pause") }) { Icon(Icons.Default.PlayArrow, "Play or pause") }
                    IconButton(onClick = { macCommand("next") }) { Icon(Icons.Default.SkipNext, "Next track") }
                }

                Spacer(Modifier.height(8.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { macCommand("lock") }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Lock", maxLines = 1)
                    }
                    OutlinedButton(onClick = { confirmSleep = true }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Default.Bedtime, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Sleep", maxLines = 1)
                    }
                    IconButton(onClick = { macCommand("refresh") }) { Icon(Icons.Default.Refresh, "Refresh") }
                }
            }
        }
    }

    // Sleeping drops the connection until the Mac wakes, so confirm first
    if (confirmSleep) {
        AlertDialog(
            onDismissRequest = { confirmSleep = false },
            title = { Text("Put the Mac to sleep?") },
            text = { Text("DroidLink disconnects until the Mac wakes up.") },
            confirmButton = { TextButton(onClick = { confirmSleep = false; macCommand("sleep") }) { Text("Sleep") } },
            dismissButton = { TextButton(onClick = { confirmSleep = false }) { Text("Cancel") } }
        )
    }
}
