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
import com.droidlink.companion.utils.Features
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
import com.droidlink.companion.models.MacWire
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
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
    private val activeWriters = CopyOnWriteArrayList<DataOutputStream>()

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
            ACTION_STOP_RINGING -> stopRinging()
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
        SmsBridge.unwatch(this)
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
     * Handles one Mac control connection: length-prefixed JSON envelopes (see MacWire).
     */
    private suspend fun handleClientConnection(socket: Socket) = withContext(Dispatchers.IO) {
        activeClients.add(socket)
        val writer = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
        activeWriters.add(writer)
        val hostAddress = socket.inetAddress.hostAddress ?: "Unknown"

        try {
            val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
            while (isActive) {
                val frame = MacWire.readFrame(input) ?: break
                val envelope = MacWire.decode(frame)
                if (envelope == null) {
                    Log.w(TAG, "Undecodable control frame (${frame.size} bytes)")
                    continue
                }
                processIncomingMessage(envelope, hostAddress)
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
     * Routes a message from the Mac to the matching subsystem.
     */
    private fun processIncomingMessage(msg: MacWire.Envelope, remoteHost: String) {
        val p = msg.payload
        when (msg.type) {
            "handshake" -> {
                val macName = p?.str("deviceName") ?: "Mac"
                Log.i(TAG, "Handshake from Mac: $macName")
                _connectionState.value = ConnectionState.Connected(deviceName = macName, hostAddress = remoteHost)
                updateForegroundNotification("Connected to $macName")
                lastTelemetry = null // new Mac session gets a fresh status on the next tick
                // no "tap to start mirroring" prompt: mirroring is started from the Mac's Mirror button (scrcpy)
                if (ScreenCaptureService.isRunning) ScreenCaptureService.instance?.requestSyncFrame()
            }
            "heartbeat" -> {
                // Mac only sends heartbeats once connected; covers a missed handshake.
                if (!_connectionState.value.isConnected) {
                    _connectionState.value = ConnectionState.Connected(deviceName = "Mac", hostAddress = remoteHost)
                }
                val rtt = System.currentTimeMillis() - (msg.timestamp * 1000).toLong()
                _latencyMs.value = rtt.coerceAtLeast(0L)
            }
            "clipboard_sync" -> if (Features.isOn(this, Features.CLIPBOARD)) p?.str("text")?.let { ClipboardService.applyRemoteClip(it) }
            "notification_reply" -> {
                val key = p?.str("notificationId") ?: return
                NotificationListenerService.replyToNotification(key, p.str("replyText") ?: "")
            }
            "notification_dismiss" -> p?.str("notificationId")?.let { NotificationListenerService.dismiss(it) }
            "touch_event" -> p?.let {
                InputService.touch(it.int("action") ?: return, it.float("normalizedX") ?: return, it.float("normalizedY") ?: return)
            }
            "scroll_event" -> p?.let {
                InputService.scroll(it.float("normalizedX") ?: return, it.float("normalizedY") ?: return,
                    it.float("deltaX") ?: 0f, it.float("deltaY") ?: 0f)
            }
            "navigation" -> p?.str("target")?.let { InputService.navigate(this, it) }
            "key_event" -> p?.let {
                InputService.key(it.int("keyCode") ?: return, it.int("action") ?: return, it.str("character"))
            }
            "sms_list" -> pushSmsList()
            "sms_send" -> {
                val to = p?.str("recipientNumber") ?: return
                val body = p.str("messageBody") ?: return
                serviceScope.launch {
                    // on success the SMS store change pushes a fresh list; on failure push now so the Mac stops waiting
                    if (!SmsBridge.send(this@ConnectionService, to, body)) SmsBridge.pushList(this@ConnectionService)
                }
            }
            "find_phone" -> ringPhone()
            "stop_find_phone" -> stopRinging()
            "mac_status" -> _macStatus.value = p
            "disconnect" -> disconnectCurrentClients()
            else -> Log.d(TAG, "Unhandled message type: ${msg.type}")
        }
    }

    /** Plays the alarm sound for 15 seconds so the phone can be found, even on silent. */
    private var ringing: android.media.Ringtone? = null

    private fun ringPhone() {
        stopRinging()
        val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
            ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
        val ringtone = android.media.RingtoneManager.getRingtone(this, uri) ?: return
        ringtone.audioAttributes = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_ALARM)
            .build()
        ringtone.play()
        ringing = ringtone
        // "Found it" notification with a Stop button, so it can be silenced on the phone too
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(CHANNEL_FIND_PHONE, "Find My Phone", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val stop = PendingIntent.getService(
            this, 3, Intent(this, ConnectionService::class.java).setAction(ACTION_STOP_RINGING),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        notificationManager.notify(
            NOTIFICATION_ID_FIND_PHONE,
            NotificationCompat.Builder(this, CHANNEL_FIND_PHONE)
                .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
                .setContentTitle("Your Mac is looking for this phone")
                .setContentText("Tap Stop to silence it")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(stop)
                .setDeleteIntent(stop)
                .addAction(0, "Stop", stop)
                .build()
        )
        serviceScope.launch { delay(15_000); if (ringing === ringtone) stopRinging() }
    }

    private fun stopRinging() {
        ringing?.stop()
        ringing = null
        notificationManager.cancel(NOTIFICATION_ID_FIND_PHONE)
    }

    private fun JsonObject.str(key: String) = this[key]?.jsonPrimitive?.content
    private fun JsonObject.int(key: String) = this[key]?.jsonPrimitive?.intOrNull
    private fun JsonObject.float(key: String) = this[key]?.jsonPrimitive?.floatOrNull

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

    private var lastTelemetry: ProtocolMessage.DeviceStatus? = null

    /** Only sends when something changed: battery/storage move slowly, so most ticks send nothing. */
    private fun sendDeviceTelemetry() {
        val telemetry = deviceInfo.getDeviceStatusMessage()
        if (telemetry == lastTelemetry) return
        lastTelemetry = telemetry
        sendProtocolMessage(telemetry)
    }

    fun sendProtocolMessage(message: ProtocolMessage) {
        val body = MacWire.encode(message) ?: return
        serviceScope.launch(Dispatchers.IO) {
            for (writer in activeWriters) {
                runCatching { MacWire.writeFrame(writer, body) }
            }
        }
    }

    /** Sends a payload the Mac knows by type name only (no ProtocolMessage class). */
    fun sendRaw(type: String, payload: JsonObject?) {
        val body = MacWire.encodeRaw(type, payload)
        serviceScope.launch(Dispatchers.IO) {
            for (writer in activeWriters) {
                runCatching { MacWire.writeFrame(writer, body) }
            }
        }
    }

    /** Reads SMS off the main thread and sends the list to the Mac, if one is connected. */
    fun pushSmsList() {
        if (activeWriters.isEmpty()) return
        serviceScope.launch { SmsBridge.pushList(this@ConnectionService) }
    }

    fun disconnectCurrentClients() {
        for (client in activeClients) {
            runCatching { client.close() }
        }
        activeClients.clear()
        activeWriters.clear()
        _macStatus.value = null
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
        private const val ACTION_STOP_RINGING = "com.droidlink.companion.STOP_RINGING"
        private const val CHANNEL_FIND_PHONE = "droidlink_channel_find_phone"
        private const val NOTIFICATION_ID_FIND_PHONE = 1005

        @Volatile
        var instance: ConnectionService? = null
            private set

        private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
        val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

        private val _latencyMs = MutableStateFlow<Long>(0L)
        val latencyMs: StateFlow<Long> = _latencyMs.asStateFlow()

        /** Latest `mac_status` payload from the Mac (battery, storage, volume), null until one arrives. */
        private val _macStatus = MutableStateFlow<JsonObject?>(null)
        val macStatus: StateFlow<JsonObject?> = _macStatus.asStateFlow()

        /**
         * Global entry point for other services (Notifications, Clipboard, Calls) to broadcast messages.
         */
        fun broadcastProtocolMessage(message: ProtocolMessage) {
            val service = instance ?: return
            // features switched off on the Status screen send nothing to the Mac
            Features.keyFor(message)?.let { if (!Features.isOn(service, it)) return }
            service.sendProtocolMessage(message)
        }

        fun updateState(state: ConnectionState) {
            _connectionState.value = state
        }
    }
}
