/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Core connection lifecycle manager providing mDNS/NSD service discovery,
 * WebSocket/TCP control channel server, bidirectional protocol message routing,
 * heartbeat monitoring, and USB ADB port forwarding compatibility.
 */

package com.droidlink.companion.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.droidlink.companion.MainActivity
import com.droidlink.companion.models.ConnectionState
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Constants
import com.droidlink.companion.utils.DeviceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Foreground service acting as the central coordination hub for all DroidLink ecosystem streams.
 */
class ConnectionService : Service() {

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private lateinit var notificationManager: NotificationManager
    private lateinit var nsdManager: NsdManager
    private lateinit var deviceInfo: DeviceInfo

    private var controlServerSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private var heartbeatJob: Job? = null
    private var registrationListener: NsdManager.RegistrationListener? = null

    // Active client control sockets (Mac desktop connections)
    private val activeClients = CopyOnWriteArrayList<Socket>()
    private val activeWriters = CopyOnWriteArrayList<PrintWriter>()

    inner class LocalBinder : Binder() {
        fun getService(): ConnectionService = this@ConnectionService
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
        deviceInfo = DeviceInfo(this)

        createNotificationChannel()
        startForeground(Constants.NOTIFICATION_ID_CONNECTION, buildForegroundNotification("Ready to connect"))

        startControlServer(Constants.DEFAULT_CONTROL_PORT)
        registerNsdService(Constants.DEFAULT_CONTROL_PORT)
        startHeartbeatLoop()

        Log.d(TAG, "ConnectionService created and running")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.d(TAG, "onStartCommand action: $action")

        when (action) {
            Constants.ACTION_DISCONNECT -> {
                disconnectCurrentClients()
            }
            Constants.ACTION_CONNECT -> {
                val host = intent.getStringExtra(Constants.EXTRA_TARGET_IP)
                val port = intent.getIntExtra(Constants.EXTRA_TARGET_PORT, Constants.DEFAULT_CONTROL_PORT)
                if (!host.isNullOrBlank()) {
                    connectToHost(host, port)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        unregisterNsdService()
        stopControlServer()
        heartbeatJob?.cancel()
        _connectionState.value = ConnectionState.Disconnected
        Log.d(TAG, "ConnectionService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    /**
     * Registers Network Service Discovery (mDNS) so macOS DroidLink can discover phone automatically.
     */
    private fun registerNsdService(port: Int) {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "${Constants.NSD_SERVICE_NAME}-${Build.MODEL.replace(" ", "_")}"
            serviceType = Constants.NSD_SERVICE_TYPE
            setPort(port)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS Service successfully registered: ${info.serviceName} on port ${info.port}")
            }

            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "mDNS registration failed with error: $errorCode")
            }

            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS Service unregistered: ${info.serviceName}")
            }

            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "mDNS unregistration failed: $errorCode")
            }
        }

        runCatching {
            nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        }.onFailure {
            Log.e(TAG, "Error registering NSD service", it)
        }
    }

    private fun unregisterNsdService() {
        registrationListener?.let {
            runCatching { nsdManager.unregisterService(it) }
            registrationListener = null
        }
    }

    /**
     * Starts the TCP JSON control server on the device.
     */
    private fun startControlServer(port: Int) {
        serverJob?.cancel()
        serverJob = serviceScope.launch {
            try {
                controlServerSocket = ServerSocket(port)
                Log.i(TAG, "Control server listening on port $port")
                _connectionState.value = ConnectionState.Discovering

                while (isActive) {
                    val clientSocket = controlServerSocket?.accept() ?: break
                    Log.i(TAG, "Accepted incoming Mac control connection from ${clientSocket.inetAddress.hostAddress}")
                    launch {
                        handleClientConnection(clientSocket)
                    }
                }
            } catch (e: Exception) {
                if (isActive) {
                    Log.e(TAG, "Control server exception", e)
                }
            }
        }
    }

    private fun stopControlServer() {
        serverJob?.cancel()
        disconnectCurrentClients()
        runCatching { controlServerSocket?.close() }
        controlServerSocket = null
    }

    /**
     * Outbound connection logic for manual IP or QR code pairing.
     */
    fun connectToHost(host: String, port: Int) {
        serviceScope.launch {
            _connectionState.value = ConnectionState.Connecting(host)
            try {
                Log.i(TAG, "Initiating outbound connection to $host:$port")
                val socket = withContext(Dispatchers.IO) { Socket(host, port) }
                launch {
                    handleClientConnection(socket)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed connecting to $host:$port", e)
                _connectionState.value = ConnectionState.Disconnected
            }
        }
    }

    /**
     * Handles an active control socket session with reading loop and message routing.
     */
    private suspend fun handleClientConnection(socket: Socket) = withContext(Dispatchers.IO) {
        activeClients.add(socket)
        val writer = PrintWriter(socket.getOutputStream(), true)
        activeWriters.add(writer)

        val hostAddress = socket.inetAddress.hostAddress ?: "Unknown"

        // Send Initial Handshake to Mac
        val display = deviceInfo.getDisplayMetrics()
        val handshake = ProtocolMessage.Handshake(
            version = Constants.PROTOCOL_VERSION,
            deviceName = deviceInfo.deviceName,
            deviceModel = deviceInfo.model,
            osVersion = deviceInfo.androidVersion,
            screenWidth = display.width,
            screenHeight = display.height
        )
        sendMessageDirect(writer, handshake)

        try {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
            while (isActive) {
                val line = reader.readLine() ?: break
                if (line.isNotBlank()) {
                    processIncomingMessage(line, hostAddress)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Client socket disconnected or closed: ${e.message}")
        } finally {
            activeClients.remove(socket)
            activeWriters.remove(writer)
            runCatching { socket.close() }

            if (activeClients.isEmpty()) {
                _connectionState.value = ConnectionState.Disconnected
                updateForegroundNotification("Disconnected")
            }
        }
    }

    /**
     * Deserializes and routes incoming protocol messages from Mac to respective subsystems.
     */
    private fun processIncomingMessage(json: String, remoteHost: String) {
        val msg = ProtocolMessage.fromJson(json) ?: run {
            Log.w(TAG, "Unrecognized message JSON: $json")
            return
        }

        when (msg) {
            is ProtocolMessage.HandshakeAck -> {
                Log.i(TAG, "Handshake confirmed with Mac: ${msg.macHostname} (Session: ${msg.sessionId})")
                _connectionState.value = ConnectionState.Connected(
                    deviceName = msg.macHostname,
                    hostAddress = remoteHost
                )
                updateForegroundNotification("Connected to ${msg.macHostname}")
                // Start sending device status updates
                sendDeviceTelemetry()
            }

            is ProtocolMessage.HeartbeatAck -> {
                val now = System.currentTimeMillis()
                val rtt = now - msg.originalTimestamp
                _latencyMs.value = rtt.coerceAtLeast(0L)
            }

            is ProtocolMessage.Heartbeat -> {
                // Reply immediately
                sendProtocolMessage(ProtocolMessage.HeartbeatAck(msg.timestamp))
            }

            is ProtocolMessage.ClipboardSync -> {
                Log.d(TAG, "Received remote clipboard update")
                ClipboardService.applyRemoteClip(msg.text)
            }

            is ProtocolMessage.NotificationReply -> {
                Log.i(TAG, "Received remote notification reply for key: ${msg.key}")
                NotificationListenerService.replyToNotification(msg.key, msg.replyText)
            }

            is ProtocolMessage.CallControl -> {
                Log.i(TAG, "Received remote call control action: ${msg.action}")
                CallBridgeService.handleRemoteCallControl(msg)
            }

            is ProtocolMessage.StartMirroring -> {
                Log.i(TAG, "Received StartMirroring command from Mac")
                // Trigger screen capture service
                val intent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = Constants.ACTION_START_SCREEN_CAPTURE
                    msg.config?.let { putExtra(Constants.EXTRA_MIRROR_CONFIG, it) }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            }

            is ProtocolMessage.StopMirroring -> {
                Log.i(TAG, "Received StopMirroring command from Mac")
                val intent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = Constants.ACTION_STOP_SCREEN_CAPTURE
                }
                startService(intent)
            }

            is ProtocolMessage.InputEvent -> {
                // Input injection placeholder (e.g. AccessibilityService / root input tap)
                Log.d(TAG, "Received InputEvent: ${msg.action} at (${msg.x}, ${msg.y})")
            }

            else -> {
                Log.d(TAG, "Unhandled message: $msg")
            }
        }
    }

    /**
     * Periodic heartbeat loop to monitor link liveness and measure RTT latency.
     */
    private fun startHeartbeatLoop() {
        heartbeatJob?.cancel()
        heartbeatJob = serviceScope.launch {
            while (isActive) {
                delay(Constants.HEARTBEAT_INTERVAL_MS)
                if (_connectionState.value.isConnected) {
                    sendProtocolMessage(ProtocolMessage.Heartbeat(System.currentTimeMillis()))
                    sendDeviceTelemetry()
                }
            }
        }
    }

    private fun sendDeviceTelemetry() {
        val telemetry = deviceInfo.getDeviceStatusMessage()
        sendProtocolMessage(telemetry)
    }

    fun sendProtocolMessage(message: ProtocolMessage) {
        val json = ProtocolMessage.toJson(message)
        serviceScope.launch(Dispatchers.IO) {
            for (writer in activeWriters) {
                runCatching {
                    writer.println(json)
                }
            }
        }
    }

    private fun sendMessageDirect(writer: PrintWriter, message: ProtocolMessage) {
        val json = ProtocolMessage.toJson(message)
        runCatching {
            writer.println(json)
        }
    }

    fun disconnectCurrentClients() {
        for (client in activeClients) {
            runCatching { client.close() }
        }
        activeClients.clear()
        activeWriters.clear()
        _connectionState.value = ConnectionState.Disconnected
        updateForegroundNotification("Not Connected")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.CHANNEL_ID_CONNECTION,
                "DroidLink Connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active companion connection status"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(statusText: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, Constants.CHANNEL_ID_CONNECTION)
            .setContentTitle("DroidLink Companion")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateForegroundNotification(statusText: String) {
        notificationManager.notify(
            Constants.NOTIFICATION_ID_CONNECTION,
            buildForegroundNotification(statusText)
        )
    }

    companion object {
        private const val TAG = "ConnectionService"

        @Volatile
        var instance: ConnectionService? = null
            private set

        private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
        val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

        private val _latencyMs = MutableStateFlow<Long>(0L)
        val latencyMs: StateFlow<Long> = _latencyMs.asStateFlow()

        /**
         * Global entry point for other services (Notifications, Clipboard, Calls) to broadcast messages.
         */
        fun broadcastProtocolMessage(message: ProtocolMessage) {
            instance?.sendProtocolMessage(message)
        }

        fun updateState(state: ConnectionState) {
            _connectionState.value = state
        }
    }
}
