/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Clipboard Synchronization Service with bidirectional text/image syncing,
 * ping-pong loop prevention, and intelligent OTP detection.
 */

package com.droidlink.companion.services

import android.app.Service
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.util.Log
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.Constants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.regex.Pattern

/**
 * Service managing background clipboard listening, debouncing, OTP parsing,
 * and remote synchronization.
 */
class ClipboardService : Service() {

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private lateinit var clipboardManager: ClipboardManager
    private var lastLocalClip: String = ""
    private var lastRemoteClip: String = ""
    private var debounceJob: Job? = null

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        onClipboardChanged()
    }

    inner class LocalBinder : Binder() {
        fun getService(): ClipboardService = this@ClipboardService
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager.addPrimaryClipChangedListener(clipListener)
        Log.d(TAG, "ClipboardService created and listener registered")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        clipboardManager.removePrimaryClipChangedListener(clipListener)
        Log.d(TAG, "ClipboardService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    /**
     * Triggered when Android device primary clipboard changes.
     */
    private fun onClipboardChanged() {
        debounceJob?.cancel()
        debounceJob = serviceScope.launch {
            delay(Constants.CLIPBOARD_DEBOUNCE_MS)

            val clip = clipboardManager.primaryClip ?: return@launch
            if (clip.itemCount == 0) return@launch

            val item = clip.getItemAt(0)
            val text = item.text?.toString() ?: ""

            if (text.isBlank() || text == lastLocalClip || text == lastRemoteClip) {
                // Ignore identical clip or clip originating from remote Mac sync
                return@launch
            }

            lastLocalClip = text
            _lastClipContent.value = text

            val isOtp = detectOtp(text)

            val syncMsg = ProtocolMessage.ClipboardSync(
                text = text,
                mimeType = ClipDescription.MIMETYPE_TEXT_PLAIN,
                timestamp = System.currentTimeMillis(),
                isOtp = isOtp
            )

            Log.i(TAG, "Syncing clipboard to Mac (isOtp: $isOtp): ${text.take(30)}…")
            ConnectionService.broadcastProtocolMessage(syncMsg)
        }
    }

    /**
     * Sets clipboard content received from macOS host.
     */
    fun setRemoteClipboard(text: String) {
        if (text.isBlank() || text == lastLocalClip) return

        serviceScope.launch(Dispatchers.Main) {
            lastRemoteClip = text
            val clipData = ClipData.newPlainText("DroidLink Mac Clip", text)
            clipboardManager.setPrimaryClip(clipData)
            _lastClipContent.value = text
            Log.d(TAG, "Applied remote Mac clipboard to Android: ${text.take(30)}…")
        }
    }

    /**
     * Heuristic regex pattern matching for Two-Factor / One-Time Passwords (OTPs).
     */
    fun detectOtp(content: String): Boolean {
        if (content.length > 120) return false

        // Common OTP formats: 4-8 continuous digits, or 3-3 format like 123-456
        val digitMatch = OTP_CODE_PATTERN.matcher(content).find()
        val keywordMatch = OTP_KEYWORD_PATTERN.matcher(content).find()

        // Pure digits of length 4 to 8 are likely OTPs
        val isPureCode = content.trim().matches(Regex("^\\d{4,8}$"))

        return isPureCode || (digitMatch && keywordMatch)
    }

    companion object {
        private const val TAG = "ClipboardService"

        @Volatile
        var instance: ClipboardService? = null
            private set

        private val OTP_KEYWORD_PATTERN = Pattern.compile(
            "(?i)\\b(code|verification|otp|password|pin|security code|login code|passcode)\\b"
        )
        private val OTP_CODE_PATTERN = Pattern.compile("\\b(\\d{4,8}|\\d{3}-\\d{3})\\b")

        private val _lastClipContent = MutableStateFlow("")
        val lastClipContent: StateFlow<String> = _lastClipContent.asStateFlow()

        /**
         * Utility to apply clipboard content received from network layer.
         */
        fun applyRemoteClip(text: String) {
            instance?.setRemoteClipboard(text)
        }
    }
}
