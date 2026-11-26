/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Core connection lifecycle manager providing mDNS/NSD discovery,
 * TCP control channel server, heartbeat monitoring, and notification routing.
 */

package com.droidlink.companion.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.droidlink.companion.MainActivity
import com.droidlink.companion.models.ConnectionState
import com.droidlink.companion.models.MacWire
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Constants
import com.droidlink.companion.utils.Features
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service maintaining the control link to forward notifications to the paired Mac.
 */
class ConnectionService : Service() {

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private lateinit var notificationManager: NotificationManager
    private lateinit var nsdManager: NsdManager
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var controlServerSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private var heartbeatJob: Job? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private val isPushingToMac = AtomicBoolean(false)

    private val activeClients = CopyOnWriteArrayList<Socket>()
    private val activeWriters = CopyOnWriteArrayList<DataOutputStream>()
    private val clientWriters = java.util.concurrent.ConcurrentHashMap<DataOutputStream, Socket>()
    private val pendingFrames = ArrayDeque<ByteArray>()

    inner class LocalBinder : Binder() {
        fun getService(): ConnectionService = this@ConnectionService
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager

        createNotificationChannel()
        startForeground(Constants.NOTIFICATION_ID_CONNECTION, buildForegroundNotification("Ready to connect"))

        acquireWifiLock()
        registerNetworkCallback()
        startControlServer(Constants.DEFAULT_CONTROL_PORT)
        registerNsdService(Constants.DEFAULT_CONTROL_PORT)
        startHeartbeatLoop()

        synchronized(pendingBeforeStart) {
            if (pendingBeforeStart.isNotEmpty()) {
                synchronized(pendingFrames) {
                    while (pendingBeforeStart.isNotEmpty()) {
                        if (pendingFrames.size >= MAX_PENDING_FRAMES) pendingFrames.removeFirst()
                        pendingFrames.addLast(pendingBeforeStart.removeFirst())
                    }
                }
                triggerOutboundMacPush()
            }
        }

        Log.d(TAG, "ConnectionService created and running")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        when (action) {
            Constants.ACTION_DISCONNECT -> disconnectCurrentClients()
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
        unregisterNetworkCallback()
        releaseWifiLock()
        unregisterNsdService()
        stopControlServer()
        heartbeatJob?.cancel()
        _connectionState.value = ConnectionState.Disconnected
        Log.d(TAG, "ConnectionService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    private fun registerNsdService(port: Int) {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "${Constants.NSD_SERVICE_NAME}-${Build.MODEL.replace(" ", "_")}"
            serviceType = Constants.NSD_SERVICE_TYPE
            setPort(port)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS Service registered: ${info.serviceName} on port ${info.port}")
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

    private fun startControlServer(port: Int) {
        serverJob?.cancel()
        serverJob = serviceScope.launch {
            try {
                controlServerSocket = ServerSocket(port)
                Log.i(TAG, "Control server listening on port $port")
                _connectionState.value = ConnectionState.Discovering

                while (isActive) {
                    val clientSocket = controlServerSocket?.accept() ?: break
                    Log.i(TAG, "Accepted Mac connection from ${clientSocket.inetAddress.hostAddress}")
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

    fun connectToHost(host: String, port: Int) {
        serviceScope.launch {
            _connectionState.value = ConnectionState.Connecting(host)
            try {
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

    private suspend fun handleClientConnection(socket: Socket) = withContext(Dispatchers.IO) {
        runCatching {
            socket.keepAlive = true
            socket.tcpNoDelay = true
        }
        activeClients.add(socket)
        val writer = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
        activeWriters.add(writer)
        clientWriters[writer] = socket
        val hostAddress = socket.inetAddress.hostAddress ?: "Unknown"

        if (hostAddress != "127.0.0.1" && hostAddress != "::1" && hostAddress != "Unknown") {
            getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(Constants.PREF_KEY_LAST_MAC_IP, hostAddress)
                .apply()
        }

        flushPendingFrames(writer, socket)

        try {
            val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
            while (isActive) {
                val frame = MacWire.readFrame(input) ?: break
                val envelope = MacWire.decode(frame) ?: continue
                processIncomingMessage(envelope, hostAddress)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Client socket disconnected: ${e.message}")
        } finally {
            activeClients.remove(socket)
            activeWriters.remove(writer)
            clientWriters.remove(writer)
            runCatching { socket.close() }

            if (activeClients.isEmpty()) {
                _connectionState.value = ConnectionState.Disconnected
                updateForegroundNotification("Disconnected")
            }
        }
    }

    private fun processIncomingMessage(msg: MacWire.Envelope, remoteHost: String) {
        val p = msg.payload
        when (msg.type) {
            "handshake" -> {
                val macName = p?.str("deviceName") ?: "Mac"
                Log.i(TAG, "Handshake from Mac: $macName")
                _connectionState.value = ConnectionState.Connected(deviceName = macName, hostAddress = remoteHost)
                updateForegroundNotification("Connected to $macName")
            }
            "heartbeat" -> {
                if (!_connectionState.value.isConnected) {
                    _connectionState.value = ConnectionState.Connected(deviceName = "Mac", hostAddress = remoteHost)
                }
                val rtt = System.currentTimeMillis() - (msg.timestamp * 1000).toLong()
                _latencyMs.value = rtt.coerceAtLeast(0L)
            }
            "notification_reply" -> {
                val key = p?.str("notificationId") ?: return
                NotificationListenerService.replyToNotification(key, p.str("replyText") ?: "")
            }
            "notification_dismiss" -> p?.str("notificationId")?.let { NotificationListenerService.dismiss(it) }
            "disconnect" -> disconnectCurrentClients()
            else -> Log.d(TAG, "Ignored message type: ${msg.type}")
        }
    }

    private fun JsonObject.str(key: String) = this[key]?.jsonPrimitive?.content

    private fun startHeartbeatLoop() {
        heartbeatJob?.cancel()
        heartbeatJob = serviceScope.launch {
            while (isActive) {
                delay(Constants.HEARTBEAT_INTERVAL_MS)
                if (_connectionState.value.isConnected) {
                    sendProtocolMessage(ProtocolMessage.Heartbeat(System.currentTimeMillis()))
                }
            }
        }
    }

    fun sendProtocolMessage(message: ProtocolMessage) {
        val body = MacWire.encode(message) ?: return
        val isNotification = message is ProtocolMessage.NotificationForward
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = if (isNotification) {
            pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DroidLink:SocketSend")?.apply {
                setReferenceCounted(false)
                acquire(4_000L)
            }
        } else null

        serviceScope.launch(Dispatchers.IO) {
            try {
                var delivered = false
                for (writer in activeWriters) {
                    val ok = runCatching { MacWire.writeFrame(writer, body) }.isSuccess
                    if (ok) {
                        delivered = true
                    } else {
                        activeWriters.remove(writer)
                        clientWriters.remove(writer)?.let { deadSocket ->
                            activeClients.remove(deadSocket)
                            runCatching { deadSocket.close() }
                        }
                    }
                }
                if (!delivered && isNotification) {
                    enqueuePendingFrame(body)
                    triggerOutboundMacPush()
                }
            } finally {
                if (wakeLock?.isHeld == true) {
                    runCatching { wakeLock.release() }
                }
            }
        }
    }

    private fun enqueuePendingFrame(body: ByteArray) {
        synchronized(pendingFrames) {
            if (pendingFrames.size >= MAX_PENDING_FRAMES) {
                pendingFrames.removeFirst()
            }
            pendingFrames.addLast(body)
        }
    }

    private fun flushPendingFrames(writer: DataOutputStream, socket: Socket) {
        val toSend = mutableListOf<ByteArray>()
        synchronized(pendingFrames) {
            while (pendingFrames.isNotEmpty()) {
                toSend.add(pendingFrames.removeFirst())
            }
        }
        for (frame in toSend) {
            val ok = runCatching { MacWire.writeFrame(writer, frame) }.isSuccess
            if (!ok) {
                enqueuePendingFrame(frame)
                activeWriters.remove(writer)
                clientWriters.remove(writer)
                activeClients.remove(socket)
                runCatching { socket.close() }
                break
            }
        }
    }

    private fun triggerOutboundMacPush() {
        val lastMacIp = getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .getString(Constants.PREF_KEY_LAST_MAC_IP, null)
            ?.takeIf { it.isNotBlank() } ?: return
        if (!isPushingToMac.compareAndSet(false, true)) return

        serviceScope.launch(Dispatchers.IO) {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(lastMacIp, Constants.MAC_NOTIFICATION_PORT), 3_000)
                Log.i(TAG, "Outbound push connected to Mac $lastMacIp:${Constants.MAC_NOTIFICATION_PORT}")
                handleClientConnection(socket)
            } catch (e: Exception) {
                Log.d(TAG, "Outbound push to $lastMacIp:${Constants.MAC_NOTIFICATION_PORT} failed: ${e.message}")
            } finally {
                isPushingToMac.set(false)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWifiLock() {
        runCatching {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wm.createWifiLock(mode, "DroidLink:WifiLock").apply {
                setReferenceCounted(false)
                acquire()
            }
        }.onFailure { Log.w(TAG, "Failed to acquire WifiLock", it) }
    }

    private fun releaseWifiLock() {
        runCatching {
            if (wifiLock?.isHeld == true) wifiLock?.release()
            wifiLock = null
        }
    }

    private fun registerNetworkCallback() {
        runCatching {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            connectivityManager = cm
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    if (registrationListener == null) {
                        registerNsdService(Constants.DEFAULT_CONTROL_PORT)
                    }
                    val hasPending = synchronized(pendingFrames) { pendingFrames.isNotEmpty() }
                    if (hasPending && activeWriters.isEmpty()) {
                        triggerOutboundMacPush()
                    }
                }
            }
            networkCallback = cb
            cm.registerDefaultNetworkCallback(cb)
        }.onFailure { Log.w(TAG, "Failed to register network callback", it) }
    }

    private fun unregisterNetworkCallback() {
        networkCallback?.let { cb ->
            runCatching { connectivityManager?.unregisterNetworkCallback(cb) }
            networkCallback = null
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
                description = "Shows active notification bridge connection status"
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
            .setContentTitle("DroidLink Notifications")
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
        private const val MAX_PENDING_FRAMES = 25
        private val pendingBeforeStart = ArrayDeque<ByteArray>()

        @Volatile
        var instance: ConnectionService? = null
            private set

        private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
        val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

        private val _latencyMs = MutableStateFlow<Long>(0L)
        val latencyMs: StateFlow<Long> = _latencyMs.asStateFlow()

        fun hasActiveClients(): Boolean = instance?.activeWriters?.isNotEmpty() == true

        fun broadcastProtocolMessage(message: ProtocolMessage) {
            val service = instance
            if (service == null) {
                if (message is ProtocolMessage.NotificationForward) {
                    MacWire.encode(message)?.let { frame ->
                        synchronized(pendingBeforeStart) {
                            if (pendingBeforeStart.size >= MAX_PENDING_FRAMES) pendingBeforeStart.removeFirst()
                            pendingBeforeStart.addLast(frame)
                        }
                    }
                }
                return
            }
            Features.keyFor(message)?.let { if (!Features.isOn(service, it)) return }
            service.sendProtocolMessage(message)
        }
    }
}
