package com.droidlink.companion.services

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Path
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Turns mouse, trackpad and keyboard input from the Mac into gestures and text on the phone.
 * Needs the user to switch it on in Settings > Accessibility.
 */
class InputService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())

    // Current mouse stroke, in screen pixels
    private val stroke = mutableListOf<Pair<Float, Float>>()
    private var strokeStart = 0L

    // Scroll deltas are batched so a trackpad flick becomes one swipe instead of hundreds
    private var scrollX = 0f
    private var scrollY = 0f
    private var scrollDx = 0f
    private var scrollDy = 0f
    private val flushScroll = Runnable { dispatchScroll() }

    override fun onServiceConnected() {
        instance = this
        Log.i(TAG, "Input service connected")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    private fun toScreen(nx: Float, ny: Float): Pair<Float, Float> {
        val m = resources.displayMetrics
        return nx.coerceIn(0f, 1f) * (m.widthPixels - 1) to ny.coerceIn(0f, 1f) * (m.heightPixels - 1)
    }

    // shortcut: the stroke is replayed when the mouse is released, so drags show up on release; upgrade to
    // continued strokes (GestureDescription.StrokeDescription.continueStroke) if live dragging is needed.
    private fun onTouch(action: Int, nx: Float, ny: Float) {
        val point = toScreen(nx, ny)
        when (action) {
            ACTION_DOWN -> {
                stroke.clear(); stroke.add(point); strokeStart = SystemClock.uptimeMillis()
            }
            ACTION_MOVE -> if (stroke.isNotEmpty()) stroke.add(point)
            ACTION_UP -> {
                if (stroke.isEmpty()) return
                stroke.add(point)
                val duration = (SystemClock.uptimeMillis() - strokeStart)
                    .coerceIn(1L, GestureDescription.getMaxGestureDuration() - 1)
                dispatchPath(stroke.toList(), duration)
                stroke.clear()
            }
            ACTION_CANCEL -> stroke.clear()
        }
    }

    private fun onScroll(nx: Float, ny: Float, dx: Float, dy: Float) {
        val (x, y) = toScreen(nx, ny)
        scrollX = x; scrollY = y
        scrollDx += dx; scrollDy += dy
        main.removeCallbacks(flushScroll)
        main.postDelayed(flushScroll, SCROLL_BATCH_MS)
    }

    private fun dispatchScroll() {
        val m = resources.displayMetrics
        val endX = (scrollX + scrollDx * SCROLL_SCALE).coerceIn(0f, m.widthPixels - 1f)
        val endY = (scrollY + scrollDy * SCROLL_SCALE).coerceIn(0f, m.heightPixels - 1f)
        scrollDx = 0f; scrollDy = 0f
        if (endX == scrollX && endY == scrollY) return
        dispatchPath(listOf(scrollX to scrollY, endX to endY), SWIPE_MS)
    }

    private fun dispatchPath(points: List<Pair<Float, Float>>, durationMs: Long) {
        val path = Path().apply {
            moveTo(points[0].first, points[0].second)
            points.drop(1).forEach { lineTo(it.first, it.second) }
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        dispatchGesture(gesture, null, null)
    }

    private fun onKey(keyCode: Int, action: Int, character: String?) {
        if (action != 0) return // act on key down only
        when (keyCode) {
            KEYCODE_ESCAPE -> performGlobalAction(GLOBAL_ACTION_BACK)
            KEYCODE_DEL -> editFocused { it.dropLast(1) }
            KEYCODE_ENTER -> {
                val node = focusedInput()
                if (node != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
                }
            }
            else -> {
                val text = character?.filter { !it.isISOControl() } ?: return
                if (text.isNotEmpty()) editFocused { it + text }
            }
        }
    }

    private fun focusedInput(): AccessibilityNodeInfo? =
        rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.takeIf { it.isEditable }

    // shortcut: edits at the end of the field, not at the cursor; fine for typing, upgrade with text selection if needed.
    private fun editFocused(change: (String) -> String) {
        val node = focusedInput() ?: return
        val current = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && node.isShowingHintText) "" else node.text?.toString() ?: ""
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, change(current))
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    companion object {
        private const val TAG = "InputService"

        // Mac TouchAction raw values
        private const val ACTION_DOWN = 0
        private const val ACTION_UP = 1
        private const val ACTION_MOVE = 2
        private const val ACTION_CANCEL = 3

        private const val KEYCODE_ENTER = 66
        private const val KEYCODE_DEL = 67
        private const val KEYCODE_ESCAPE = 111

        private const val SCROLL_BATCH_MS = 40L
        private const val SCROLL_SCALE = 4f
        private const val SWIPE_MS = 120L

        @Volatile
        var instance: InputService? = null
            private set

        fun touch(action: Int, nx: Float, ny: Float) = onMain { it.onTouch(action, nx, ny) }
        fun scroll(nx: Float, ny: Float, dx: Float, dy: Float) = onMain { it.onScroll(nx, ny, dx, dy) }
        fun key(keyCode: Int, action: Int, character: String?) = onMain { it.onKey(keyCode, action, character) }

        fun navigate(context: Context, target: String) {
            if (target == "volumeUp" || target == "volumeDown") {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val dir = if (target == "volumeUp") AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
                return
            }
            val action = when (target) {
                "back" -> GLOBAL_ACTION_BACK
                "home" -> GLOBAL_ACTION_HOME
                "recents" -> GLOBAL_ACTION_RECENTS
                "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
                "lockScreen" -> GLOBAL_ACTION_LOCK_SCREEN
                else -> return
            }
            onMain { it.performGlobalAction(action) }
        }

        private fun onMain(block: (InputService) -> Unit) {
            val service = instance ?: run {
                Log.w(TAG, "Input from Mac ignored: accessibility service is off")
                return
            }
            service.main.post { block(service) }
        }
    }
}
