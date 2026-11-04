/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Main entry activity handling Jetpack Compose UI, runtime permissions flow,
 * and deep link routing.
 */

package com.droidlink.companion

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.droidlink.companion.services.CallBridgeService
import com.droidlink.companion.services.ClipboardService
import com.droidlink.companion.services.ConnectionService
import com.droidlink.companion.services.FileServerService
import com.droidlink.companion.ui.navigation.DroidLinkApp
import com.droidlink.companion.ui.theme.DroidLinkTheme
import com.droidlink.companion.utils.Constants
import com.droidlink.companion.utils.PermissionHelper

/**
 * Main activity of DroidLink Android companion app.
 */
class MainActivity : ComponentActivity() {

    private var showNotificationAccessDialog by mutableStateOf(false)

    // Dangerous runtime permissions launcher
    private val runtimePermissionsLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissionsMap ->
        val grantedCount = permissionsMap.values.count { it }
        Log.i(TAG, "Permissions result: $grantedCount / ${permissionsMap.size} granted")

        // Prompt for notification listener access if not enabled
        if (!PermissionHelper.isNotificationServiceEnabled(this)) {
            showNotificationAccessDialog = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start fundamental background companion services
        startCoreServices()

        // Handle initial incoming deep link if present
        handleDeepLink(intent)

        // Request necessary runtime permissions
        requestAppPermissions()

        setContent {
            DroidLinkTheme {
                DroidLinkApp(
                    onRequestPermissions = { requestAppPermissions() }
                )

                if (showNotificationAccessDialog) {
                    AlertDialog(
                        onDismissRequest = { showNotificationAccessDialog = false },
                        title = { Text("Notification Access Required") },
                        text = {
                            Text("To mirror notifications and enable quick replies from your Mac, DroidLink requires Notification Access permission in Android Settings.")
                        },
                        confirmButton = {
                            TextButton(
                                onClick = {
                                    showNotificationAccessDialog = false
                                    startActivity(PermissionHelper.createNotificationListenerSettingsIntent())
                                }
                            ) {
                                Text("Open Settings")
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { showNotificationAccessDialog = false }) {
                                Text("Later")
                            }
                        }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    /**
     * Triggers request for runtime permissions (telephony, storage, audio, notifications).
     */
    private fun requestAppPermissions() {
        runtimePermissionsLauncher.launch(PermissionHelper.ALL_APP_PERMISSIONS)
    }

    /**
     * Starts connection, clipboard, call bridge, and file server services.
     */
    private fun startCoreServices() {
        // Start Connection Service as foreground
        val connIntent = Intent(this, ConnectionService::class.java).apply {
            action = Constants.ACTION_START_SERVER
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(connIntent)
        } else {
            startService(connIntent)
        }

        // Start Clipboard monitoring service
        startService(Intent(this, ClipboardService::class.java))

        // Start File server service
        startService(Intent(this, FileServerService::class.java))

        // Start Call bridge service
        startService(Intent(this, CallBridgeService::class.java))
    }

    /**
     * Parses deep link URL (e.g. droidlink://connect?ip=192.168.1.100&port=8080).
     */
    private fun handleDeepLink(intent: Intent?) {
        val uri: Uri? = intent?.data
        if (uri != null && uri.scheme == "droidlink") {
            Log.i(TAG, "Handling deep link URI: $uri")
            val host = uri.getQueryParameter("ip")
            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: Constants.DEFAULT_CONTROL_PORT

            if (!host.isNullOrBlank()) {
                val connIntent = Intent(this, ConnectionService::class.java).apply {
                    action = Constants.ACTION_CONNECT
                    putExtra(Constants.EXTRA_TARGET_IP, host)
                    putExtra(Constants.EXTRA_TARGET_PORT, port)
                }
                startService(connIntent)
                Toast.makeText(this, "Connecting to $host:$port via deep link", Toast.LENGTH_SHORT).show()
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
