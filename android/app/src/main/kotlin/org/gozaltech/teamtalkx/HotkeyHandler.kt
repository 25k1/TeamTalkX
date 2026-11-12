package org.gozaltech.teamtalkx

import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class HotkeyHandler(messenger: BinaryMessenger) :
    ChannelHandler(messenger, CHANNEL) {
    private var pttKeyCode = 0
    private var capturing = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPttKey" -> {
                    pttKeyCode = call.argument<Int>("keyCode") ?: 0
                    result.success(null)
                }
                "startCapture" -> {
                    capturing = true
                    result.success(null)
                }
                "stopCapture" -> {
                    capturing = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode

        if (code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_HOME) {
            return false
        }
        if (capturing) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                channel.invokeMethod(
                    "captured",
                    mapOf("keyCode" to code, "label" to keyLabel(code))
                )
            }
            return true
        }
        if (pttKeyCode != 0 && code == pttKeyCode) {
            when (event.action) {
                KeyEvent.ACTION_DOWN ->
                    if (event.repeatCount == 0) channel.invokeMethod("pttDown", null)
                KeyEvent.ACTION_UP -> channel.invokeMethod("pttUp", null)
            }
            return true
        }
        return false
    }

    private fun keyLabel(code: Int): String =
        KeyEvent.keyCodeToString(code)?.removePrefix("KEYCODE_")?.replace('_', ' ')
            ?: "Key $code"

    companion object {
        const val CHANNEL = "org.gozaltech.teamtalkx/hotkey"
    }
}
