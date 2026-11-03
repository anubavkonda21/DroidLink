/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * High-performance hardware-accelerated screen capture and video streaming service
 * utilizing MediaProjection, MediaCodec (H.264 / H.265), and VirtualDisplay.
 */

package com.droidlink.companion.services

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.droidlink.companion.MainActivity
import com.droidlink.companion.models.ConnectionState
import com.droidlink.companion.models.MirrorConfig
import com.droidlink.companion.utils.Constants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer

/**
 * Foreground service capturing the Android screen display and streaming low-latency
 * H.264 / H.265 video packets over TCP or USB socket.
 */
class ScreenCaptureService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var notificationManager: NotificationManager
    private lateinit var projectionManager: MediaProjectionManager

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var mediaCodec: MediaCodec? = null
    private var inputSurface: Surface? = null

    private var videoServerSocket: ServerSocket? = null
    private var streamJob: Job? = null
    private var activeConfig: MirrorConfig = MirrorConfig()

    private var isCapturing = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        createNotificationChannel()
        Log.d(TAG, "ScreenCaptureService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.d(TAG, "ScreenCaptureService onStartCommand action: $action")

        when (action) {
            Constants.ACTION_START_SCREEN_CAPTURE -> {
                val resultCode = intent.getIntExtra(Constants.EXTRA_MEDIA_PROJECTION_RESULT_CODE, Activity.RESULT_CANCELED)
                val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Constants.EXTRA_MEDIA_PROJECTION_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Constants.EXTRA_MEDIA_PROJECTION_DATA)
                }

                val config = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Constants.EXTRA_MIRROR_CONFIG, MirrorConfig::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Constants.EXTRA_MIRROR_CONFIG)
                } ?: MirrorConfig()

                activeConfig = config

                if (resultCode == Activity.RESULT_OK && resultData != null) {
                    startForeground(
                        Constants.NOTIFICATION_ID_SCREEN_CAPTURE,
                        buildForegroundNotification("Screen mirroring active (${config.width}x${config.height} @ ${config.fps}fps)")
                    )
                    startScreenCapture(resultCode, resultData, config)
                } else {
                    Log.e(TAG, "Invalid MediaProjection intent or result code")
                    stopSelf()
                }
            }

            Constants.ACTION_STOP_SCREEN_CAPTURE -> {
                stopScreenCapture()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        stopScreenCapture()
        Log.d(TAG, "ScreenCaptureService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Initializes MediaProjection, sets up MediaCodec encoder, and accepts video stream connections.
     */
    private fun startScreenCapture(resultCode: Int, resultData: Intent, config: MirrorConfig) {
        if (isCapturing) return
        isCapturing = true

        try {
            mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.i(TAG, "MediaProjection stopped by system")
                    stopScreenCapture()
                    stopSelf()
                }
            }, null)

            // Setup MediaCodec encoder
            setupEncoder(config)

            // Create VirtualDisplay bound to encoder Surface
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "DroidLink-Display",
                config.width,
                config.height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                inputSurface,
                null,
                null
            )

            // Update ConnectionState
            ConnectionService.updateState(
                ConnectionState.Mirroring(
                    deviceName = "MacBook",
                    fps = config.fps,
                    bitrate = config.bitrate
                )
            )

            // Start streaming server and encoder draining loop
            startVideoStreamingServer(config)

        } catch (e: Exception) {
            Log.e(TAG, "Failed starting screen capture pipeline", e)
            stopScreenCapture()
        }
    }

    /**
     * Configures Android MediaCodec video encoder for low-latency streaming.
     */
    private fun setupEncoder(config: MirrorConfig) {
        val format = MediaFormat.createVideoFormat(config.codec, config.width, config.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, config.bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, Constants.DEFAULT_I_FRAME_INTERVAL)

            // Low-latency encoder profile configurations
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_LATENCY, 0)
                setInteger(MediaFormat.KEY_PRIORITY, 0) // Real-time priority
            }
            if (config.codec == Constants.CODEC_H264) {
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            }
        }

        val codec = MediaCodec.createEncoderByType(config.codec)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = codec.createInputSurface()
        codec.start()

        mediaCodec = codec
        Log.i(TAG, "MediaCodec encoder initialized: ${config.codec} (${config.width}x${config.height} @ ${config.fps}fps)")
    }

    /**
     * Spawns TCP server socket on VIDEO_PORT and pumps encoded NAL buffers to connected Mac receiver.
     */
    private fun startVideoStreamingServer(config: MirrorConfig) {
        streamJob?.cancel()
        streamJob = serviceScope.launch(Dispatchers.IO) {
            try {
                videoServerSocket = ServerSocket(Constants.DEFAULT_VIDEO_PORT)
                Log.i(TAG, "Video streaming socket open on port ${Constants.DEFAULT_VIDEO_PORT}")

                while (isActive && isCapturing) {
                    val client = videoServerSocket?.accept() ?: break
                    Log.i(TAG, "Mac connected to video stream: ${client.inetAddress.hostAddress}")
                    drainEncoderToSocket(client)
                }
            } catch (e: Exception) {
                if (isActive && isCapturing) {
                    Log.e(TAG, "Video server error", e)
                }
            }
        }
    }

    /**
     * Continuously drains encoded output buffers from MediaCodec and writes to socket.
     */
    private suspend fun drainEncoderToSocket(socket: Socket) = withContext(Dispatchers.IO) {
        socket.use { s ->
            val dos = DataOutputStream(BufferedOutputStream(s.getOutputStream(), 128 * 1024))
            val bufferInfo = MediaCodec.BufferInfo()
            val codec = mediaCodec ?: return@withContext

            try {
                while (isActive && isCapturing) {
                    val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000L) // 10ms timeout

                    if (outputBufferIndex >= 0) {
                        val outputBuffer: ByteBuffer? = codec.getOutputBuffer(outputBufferIndex)

                        if (outputBuffer != null && bufferInfo.size > 0) {
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)

                            // Frame packet header: [Int: Size] [Long: Presentation Timestamp] [Int: Flags]
                            val packetBytes = ByteArray(bufferInfo.size)
                            outputBuffer.get(packetBytes)

                            dos.writeInt(bufferInfo.size)
                            dos.writeLong(bufferInfo.presentationTimeUs)
                            dos.writeInt(bufferInfo.flags)
                            dos.write(packetBytes)
                            dos.flush()
                        }

                        codec.releaseOutputBuffer(outputBufferIndex, false)
                    } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val newFormat = codec.outputFormat
                        Log.i(TAG, "MediaCodec output format changed: $newFormat")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Video client stream ended: ${e.message}")
            }
        }
    }

    /**
     * Request dynamic keyframe (IDR frame) generation for instant recovery on packet drop.
     */
    fun requestSyncFrame() {
        runCatching {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            }
            mediaCodec?.setParameters(params)
            Log.d(TAG, "Requested sync frame from MediaCodec")
        }
    }

    /**
     * Dynamically adjust encoding bitrate during session.
     */
    fun setBitrate(bitrateBps: Int) {
        runCatching {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrateBps)
            }
            mediaCodec?.setParameters(params)
            activeConfig = activeConfig.copy(bitrate = bitrateBps)
            Log.i(TAG, "Updated dynamic bitrate to $bitrateBps bps")
        }
    }

    /**
     * Clean release of all display, codec, and projection hardware resources.
     */
    private fun stopScreenCapture() {
        if (!isCapturing) return
        isCapturing = false

        streamJob?.cancel()
        runCatching { videoServerSocket?.close() }
        videoServerSocket = null

        runCatching {
            virtualDisplay?.release()
            virtualDisplay = null
        }

        runCatching {
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null
        }

        runCatching {
            inputSurface?.release()
            inputSurface = null
        }

        runCatching {
            mediaProjection?.stop()
            mediaProjection = null
        }

        Log.i(TAG, "Screen capture pipeline successfully halted and released")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.CHANNEL_ID_SCREEN_CAPTURE,
                "DroidLink Screen Mirroring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Foreground notification showing active screen mirroring session"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(content: String): Notification {
        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
            action = Constants.ACTION_STOP_SCREEN_CAPTURE
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val mainIntent = Intent(this, MainActivity::class.java)
        val mainPendingIntent = PendingIntent.getActivity(
            this,
            0,
            mainIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, Constants.CHANNEL_ID_SCREEN_CAPTURE)
            .setContentTitle("Screen Mirroring Active")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentIntent(mainPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Mirroring", stopPendingIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "ScreenCaptureService"

        @Volatile
        var instance: ScreenCaptureService? = null
            private set

        val isRunning: Boolean
            get() = instance?.isCapturing == true
    }
}
