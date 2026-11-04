/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Status screen: live link quality, phone battery and which features are running.
 *
 */

package com.droidlink.companion.ui

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.BatteryStd
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Card
import com.droidlink.companion.utils.Features
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Security
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.droidlink.companion.services.ConnectionService
import com.droidlink.companion.services.NotificationListenerService
import com.droidlink.companion.ui.theme.Accents
import com.droidlink.companion.ui.theme.GlassSwitch
import com.droidlink.companion.utils.DeviceInfo

/** Live status of the link and of each feature. Only real readings; the switches stop or allow each kind of data. */
@Composable
fun StatusScreen() {
    val context = LocalContext.current
    val deviceInfo = remember { DeviceInfo(context) }
    val latencyMs by ConnectionService.latencyMs.collectAsState()
    val connectionState by ConnectionService.connectionState.collectAsState()
    val battery = remember { deviceInfo.getBatteryInfo() }
    val network = remember { deviceInfo.getNetworkInfo() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text("Status", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))

        // Connection
        StatusCard {
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Metric(Icons.Default.Speed, Accents.Green, "Latency",
                    if (connectionState.isConnected) "$latencyMs ms" else "—",
                    when {
                        !connectionState.isConnected -> "Not connected"
                        latencyMs < 20 -> "Excellent"
                        latencyMs < 60 -> "Good"
                        else -> "Slow"
                    })
                Metric(Icons.Default.Wifi, Accents.Blue, "Network",
                    if (network.isWifiConnected) "Wi-Fi" else "Mobile",
                    network.ssid.takeIf { network.isWifiConnected && it.isNotBlank() && !it.startsWith("<") } ?: "—")
            }
        }

        Spacer(Modifier.height(12.dp))

        // Phone battery
        StatusCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconBubble(if (battery.isCharging) Icons.Default.BatteryChargingFull else Icons.Default.BatteryStd, Accents.Green)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Phone battery", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    Text(if (battery.isCharging) "Charging" else "On battery",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("${battery.level}%", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Accents.Green)
            }
            Spacer(Modifier.height(10.dp))
            LinearProgressIndicator(
                progress = { battery.level / 100f },
                color = Accents.Green,
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp))
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Thermostat, contentDescription = null, modifier = Modifier.size(16.dp), tint = Accents.Orange)
                Spacer(Modifier.width(6.dp))
                Text("%.1f°C".format(battery.temperatureCelsius), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        Spacer(Modifier.height(24.dp))
        Text("Features", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(10.dp))

        FeatureRow(Icons.Default.NotificationsActive, Accents.Pink, "Notifications",
            if (NotificationListenerService.instance != null) "Phone notifications on the Mac" else "Needs notification access",
            Features.NOTIFICATIONS)
        FeatureRow(Icons.Default.ContentPaste, Accents.Orange, "Clipboard",
            "Copy on one, paste on the other", Features.CLIPBOARD)
        FeatureRow(Icons.Default.CloudDownload, Accents.Blue, "File transfer",
            "Send files to the Mac", Features.FILES)
        FeatureRow(Icons.Default.Call, Accents.Green, "Calls",
            "Caller ID on the Mac", Features.CALLS)

        Spacer(Modifier.height(16.dp))
        // Android only lets the user revoke permissions, so link straight to this app's system page
        Card(
            onClick = {
                context.startActivity(
                    android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts("package", context.packageName, null))
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Row(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                IconBubble(Icons.Default.Security, Accents.Teal)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text("Phone permissions", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    Text("Turn off camera, SMS, contacts and more in Android settings",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun StatusCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(16.dp)) { content() }
    }
}

@Composable
private fun IconBubble(icon: ImageVector, color: Color) {
    Box(
        modifier = Modifier.size(40.dp).clip(CircleShape).background(color.copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun Metric(icon: ImageVector, color: Color, title: String, value: String, note: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconBubble(icon, color)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(note, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1)
        }
    }
}

/** A feature with a real on/off switch: off stops that data going to (and coming from) the Mac. */
@Composable
private fun FeatureRow(icon: ImageVector, color: Color, title: String, subtitle: String, featureKey: String) {
    val context = LocalContext.current
    var isOn by remember { mutableStateOf(Features.isOn(context, featureKey)) }
    Card(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Row(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            IconBubble(icon, if (isOn) color else Color.Gray)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                Text(if (isOn) subtitle else "Off: nothing is shared", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            GlassSwitch(
                checked = isOn,
                onCheckedChange = { isOn = it; Features.set(context, featureKey, it) },
                onColor = color
            )
        }
    }
}
