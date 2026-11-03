/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Telephony and Call Bridge Service monitoring incoming and ongoing phone calls,
 * querying contacts, forwarding call events to macOS, and handling remote call control.
 */

package com.droidlink.companion.services

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.media.AudioManager
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import com.droidlink.companion.models.ProtocolMessage
import com.droidlink.companion.utils.PermissionHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Service managing phone state monitoring and remote call operations.
 */
class CallBridgeService : Service() {

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private lateinit var telephonyManager: TelephonyManager
    private lateinit var audioManager: AudioManager
    private var telecomManager: TelecomManager? = null

    private var telephonyCallback: TelephonyCallback? = null
    private var phoneStateListener: PhoneStateListener? = null

    data class CallStateInfo(
        val state: String = "IDLE", // IDLE, RINGING, OFFHOOK
        val phoneNumber: String = "",
        val callerName: String? = null
    )

    inner class LocalBinder : Binder() {
        fun getService(): CallBridgeService = this@CallBridgeService
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager

        registerCallListener()
        Log.d(TAG, "CallBridgeService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        unregisterCallListener()
        Log.d(TAG, "CallBridgeService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    @Suppress("DEPRECATION")
    private fun registerCallListener() {
        if (!PermissionHelper.isPermissionGranted(this, android.Manifest.permission.READ_PHONE_STATE)) {
            Log.w(TAG, "READ_PHONE_STATE permission not granted. Skipping call listener registration.")
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        handleCallState(state, "")
                    }
                }
                telephonyManager.registerTelephonyCallback(mainExecutor, callback)
                telephonyCallback = callback
            } else {
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        handleCallState(state, phoneNumber ?: "")
                    }
                }
                telephonyManager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                phoneStateListener = listener
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException registering call listener", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun unregisterCallListener() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let { telephonyManager.unregisterTelephonyCallback(it) }
            } else {
                phoneStateListener?.let { telephonyManager.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error unregistering call listener", e)
        }
    }

    private fun handleCallState(state: Int, incomingNumber: String) {
        serviceScope.launch {
            val stateName = when (state) {
                TelephonyManager.CALL_STATE_RINGING -> "RINGING"
                TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
                else -> "IDLE"
            }

            val callerName = if (incomingNumber.isNotBlank()) resolveContactName(incomingNumber) else null

            Log.i(TAG, "Call state changed: $stateName ($incomingNumber, Name: $callerName)")

            val callInfo = CallStateInfo(
                state = stateName,
                phoneNumber = incomingNumber,
                callerName = callerName
            )
            _activeCallState.value = callInfo

            // Broadcast call event to connected Mac
            val event = ProtocolMessage.CallEvent(
                callState = stateName,
                phoneNumber = incomingNumber,
                callerName = callerName
            )
            ConnectionService.broadcastProtocolMessage(event)
        }
    }

    /**
     * Resolves caller name from device Contacts database given a phone number.
     */
    private fun resolveContactName(phoneNumber: String): String? {
        if (!PermissionHelper.isPermissionGranted(this, android.Manifest.permission.READ_CONTACTS)) {
            return null
        }

        return runCatching {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(phoneNumber)
            )
            val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
            val cursor: Cursor? = contentResolver.query(uri, projection, null, null, null)

            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (nameIndex != -1) it.getString(nameIndex) else null
                } else null
            }
        }.getOrNull()
    }

    /**
     * Accepts an incoming ringing call (requires Android ANSWER_PHONE_CALLS / TelecomManager).
     */
    @SuppressLint("MissingPermission")
    fun acceptCall(): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                telecomManager?.acceptRingingCall()
                Log.i(TAG, "Accepted incoming call via TelecomManager")
                true
            } else {
                // TODO: Legacy fallback for pre-Oreo if ever needed
                false
            }
        }.getOrElse { e ->
            Log.e(TAG, "Failed to accept call", e)
            false
        }
    }

    /**
     * Rejects / ends an incoming or active phone call.
     */
    @SuppressLint("MissingPermission")
    fun rejectCall(): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                telecomManager?.endCall()
                Log.i(TAG, "Ended call via TelecomManager")
                true
            } else {
                false
            }
        }.getOrElse { e ->
            Log.e(TAG, "Failed to end call", e)
            false
        }
    }

    /**
     * Silences device ringer during incoming call.
     */
    fun silenceRinger() {
        runCatching {
            audioManager.ringerMode = AudioManager.RINGER_MODE_SILENT
            Log.i(TAG, "Silenced ringer via AudioManager")
        }.onFailure {
            Log.w(TAG, "Could not silence ringer", it)
        }
    }

    companion object {
        private const val TAG = "CallBridgeService"

        @Volatile
        var instance: CallBridgeService? = null
            private set

        private val _activeCallState = MutableStateFlow(CallStateInfo())
        val activeCallState: StateFlow<CallStateInfo> = _activeCallState.asStateFlow()

        /**
         * Dispatches remote call command from Mac.
         */
        fun handleRemoteCallControl(command: ProtocolMessage.CallControl) {
            when (command.action.uppercase()) {
                "ANSWER" -> instance?.acceptCall()
                "REJECT", "DECLINE" -> instance?.rejectCall()
                "SILENCE" -> instance?.silenceRinger()
                else -> Log.w(TAG, "Unknown remote call action: ${command.action}")
            }
        }
    }
}
