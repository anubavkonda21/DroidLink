/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Dedicated TCP file transfer engine supporting bidirectional streaming,
 * CRC32 checksum verification, scoped storage saving, and real-time progress tracking.
 */

package com.droidlink.companion.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Constants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.zip.CRC32

/**
 * Service managing local TCP file transfer server and outbound upload client.
 */
class FileServerService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var serverJob: Job? = null
    private var serverSocket: ServerSocket? = null
    private lateinit var notificationManager: NotificationManager

    data class TransferProgress(
        val fileName: String = "",
        val bytesTransferred: Long = 0L,
        val totalBytes: Long = 0L,
        val isUploading: Boolean = false,
        val isComplete: Boolean = false,
        val error: String? = null
    ) {
        val percentage: Int
            get() = if (totalBytes > 0) ((bytesTransferred * 100) / totalBytes).toInt() else 0
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        startFileServer()
        Log.d(TAG, "FileServerService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == Constants.ACTION_SEND_FILE) {
            val uri = intent.getParcelableExtra<Uri>(Constants.EXTRA_FILE_URI)
            val targetIp = intent.getStringExtra(Constants.EXTRA_TARGET_IP) ?: "127.0.0.1"
            val targetPort = intent.getIntExtra(Constants.EXTRA_TARGET_PORT, Constants.DEFAULT_FILE_PORT)

            if (uri != null) {
                sendFileToHost(uri, targetIp, targetPort)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        stopFileServer()
        Log.d(TAG, "FileServerService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Initializes background TCP server listening for file transfers from macOS.
     */
    private fun startFileServer() {
        serverJob?.cancel()
        serverJob = serviceScope.launch {
            try {
                serverSocket = ServerSocket(Constants.DEFAULT_FILE_PORT)
                Log.i(TAG, "File server listening on port ${Constants.DEFAULT_FILE_PORT}")

                while (isActive) {
                    val clientSocket = serverSocket?.accept() ?: break
                    launch {
                        handleIncomingConnection(clientSocket)
                    }
                }
            } catch (e: Exception) {
                if (isActive) {
                    Log.e(TAG, "File server socket error", e)
                }
            }
        }
    }

    private fun stopFileServer() {
        serverJob?.cancel()
        runCatching { serverSocket?.close() }
        serverSocket = null
    }

    /**
     * Handles incoming file transmission over TCP.
     * Protocol frame:
     * - UTF fileName
     * - Long fileSize
     * - Long expectedCrc32
     * - Raw payload bytes
     */
    private suspend fun handleIncomingConnection(socket: Socket) = withContext(Dispatchers.IO) {
        socket.use { s ->
            val dis = DataInputStream(BufferedInputStream(s.getInputStream()))
            val dos = DataOutputStream(BufferedOutputStream(s.getOutputStream()))

            try {
                val fileName = dis.readUTF()
                val fileSize = dis.readLong()
                val expectedChecksum = dis.readLong()

                Log.i(TAG, "Receiving file: $fileName, size: $fileSize bytes")
                updateProgress(TransferProgress(fileName = fileName, totalBytes = fileSize, isUploading = false))

                val outputFile = prepareDestinationFile(fileName)
                val fos = FileOutputStream(outputFile)
                val crc32 = CRC32()

                val buffer = ByteArray(64 * 1024)
                var bytesRemaining = fileSize
                var totalRead = 0L

                fos.use { out ->
                    while (bytesRemaining > 0) {
                        val toRead = buffer.size.toLong().coerceAtMost(bytesRemaining).toInt()
                        val bytesRead = dis.read(buffer, 0, toRead)
                        if (bytesRead == -1) break

                        out.write(buffer, 0, bytesRead)
                        crc32.update(buffer, 0, bytesRead)

                        bytesRemaining -= bytesRead
                        totalRead += bytesRead
                        updateProgress(TransferProgress(fileName = fileName, bytesTransferred = totalRead, totalBytes = fileSize))
                    }
                }

                val actualChecksum = crc32.value
                val isSuccess = (actualChecksum == expectedChecksum) && (totalRead == fileSize)

                // Write confirmation ack
                dos.writeBoolean(isSuccess)
                dos.writeUTF(if (isSuccess) "OK" else "CRC mismatch or truncated")
                dos.flush()

                if (isSuccess) {
                    Log.i(TAG, "File saved successfully to ${outputFile.absolutePath}")
                    updateProgress(TransferProgress(fileName = fileName, bytesTransferred = totalRead, totalBytes = fileSize, isComplete = true))
                    notifyFileSaved(outputFile)
                } else {
                    Log.e(TAG, "File verification failed: actual CRC=$actualChecksum, expected=$expectedChecksum")
                    outputFile.delete()
                    updateProgress(TransferProgress(fileName = fileName, error = "Integrity check failed"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling incoming file", e)
                updateProgress(TransferProgress(error = e.localizedMessage ?: "Transfer failed"))
            }
        }
    }

    /**
     * Sends an Android content Uri to macOS host over TCP.
     */
    fun sendFileToHost(uri: Uri, targetHost: String, targetPort: Int) {
        serviceScope.launch(Dispatchers.IO) {
            val contentResolver = applicationContext.contentResolver
            var fileName = "transfer_${System.currentTimeMillis()}"
            var fileSize = 0L

            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                if (cursor.moveToFirst()) {
                    if (nameIndex != -1) fileName = cursor.getString(nameIndex) ?: fileName
                    if (sizeIndex != -1) fileSize = cursor.getLong(sizeIndex)
                }
            }

            Log.i(TAG, "Sending $fileName ($fileSize bytes) to $targetHost:$targetPort")
            updateProgress(TransferProgress(fileName = fileName, totalBytes = fileSize, isUploading = true))

            try {
                // Copy into Downloads/DroidLink, then tell the Mac to pull it over adb (USB or wireless adb).
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/DroidLink")
                }
                val target = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: error("Could not create file in Downloads")
                var transferred = 0L
                contentResolver.openInputStream(uri)?.use { input ->
                    contentResolver.openOutputStream(target)?.use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var bytesRead: Int
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            transferred += bytesRead
                            updateProgress(TransferProgress(fileName = fileName, bytesTransferred = transferred, totalBytes = fileSize, isUploading = true))
                        }
                    }
                } ?: error("Could not read the selected file")

                // Android may rename on clash ("name (1).ext"), so send the name it actually used
                val savedName = contentResolver.query(target, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: fileName

                ConnectionService.broadcastProtocolMessage(
                    ProtocolMessage.FileTransferOffer(
                        fileId = java.util.UUID.randomUUID().toString(),
                        fileName = savedName,
                        fileSize = transferred,
                        checksumCrc32 = 0
                    )
                )
                Log.i(TAG, "Saved $savedName to Downloads/DroidLink and offered it to the Mac")
                updateProgress(TransferProgress(fileName = savedName, bytesTransferred = transferred, totalBytes = transferred, isUploading = true, isComplete = true))
            } catch (e: Exception) {
                Log.e(TAG, "Failed sending file to Mac", e)
                updateProgress(TransferProgress(fileName = fileName, isUploading = true, error = e.localizedMessage))
            }
        }
    }

    private fun prepareDestinationFile(fileName: String): File {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val droidLinkDir = File(downloadsDir, "DroidLink")
        if (!droidLinkDir.exists()) {
            droidLinkDir.mkdirs()
        }
        var target = File(droidLinkDir, fileName)
        var counter = 1
        val baseName = fileName.substringBeforeLast('.', fileName)
        val ext = if (fileName.contains('.')) "." + fileName.substringAfterLast('.') else ""

        while (target.exists()) {
            target = File(droidLinkDir, "$baseName ($counter)$ext")
            counter++
        }
        return target
    }

    private fun notifyFileSaved(file: File) {
        // Index with media scanner so pictures/videos show in Photos gallery
        val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
        mediaScanIntent.data = Uri.fromFile(file)
        sendBroadcast(mediaScanIntent)
    }

    private fun updateProgress(progress: TransferProgress) {
        _currentTransfer.value = progress
        updateNotification(progress)
    }

    private fun updateNotification(progress: TransferProgress) {
        val title = if (progress.isUploading) "Sending file to Mac" else "Receiving file from Mac"
        val content = "${progress.fileName} (${progress.percentage}%)"

        val notification = NotificationCompat.Builder(this, Constants.CHANNEL_ID_FILE_TRANSFER)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progress.percentage, progress.totalBytes <= 0)
            .setOngoing(!progress.isComplete && progress.error == null)
            .setAutoCancel(progress.isComplete)
            .build()

        notificationManager.notify(Constants.NOTIFICATION_ID_FILE_TRANSFER, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.CHANNEL_ID_FILE_TRANSFER,
                "DroidLink File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress of file transfers between phone and Mac"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "FileServerService"

        @Volatile
        var instance: FileServerService? = null
            private set

        private val _currentTransfer = MutableStateFlow(TransferProgress())
        val currentTransfer: StateFlow<TransferProgress> = _currentTransfer.asStateFlow()
    }
}
