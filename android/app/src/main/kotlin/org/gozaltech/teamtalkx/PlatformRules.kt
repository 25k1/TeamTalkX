package org.gozaltech.teamtalkx

import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.telephony.TelephonyManager
import android.view.KeyEvent
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object PlatformRules {
    const val MODE_CALL_SCREENING = 4
    const val MODE_CALL_REDIRECT = 5
    const val MODE_COMMUNICATION_REDIRECT = 6

    fun mediaKeyName(code: Int): String? = when (code) {
        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
        KeyEvent.KEYCODE_MEDIA_PLAY,
        KeyEvent.KEYCODE_MEDIA_PAUSE,
        KeyEvent.KEYCODE_HEADSETHOOK -> "playPause"
        KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "previous"
        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "fastForward"
        KeyEvent.KEYCODE_MEDIA_REWIND -> "rewind"
        KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
        else -> null
    }

    fun outputKind(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE -> "usb"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
        AudioDeviceInfo.TYPE_HEARING_AID -> "hearingAid"
        else -> null
    }

    fun isOtherAppAudio(usage: Int, contentType: Int): Boolean =
        usage == AudioAttributes.USAGE_MEDIA &&
            contentType != AudioAttributes.CONTENT_TYPE_SPEECH &&
            contentType != AudioAttributes.CONTENT_TYPE_SONIFICATION

    fun callState(
        carrierState: Int,
        audioMode: Int,
        ringtonePlaying: Boolean,
        ownCommunication: Boolean,
        telecomInCall: () -> Boolean,
    ): String {
        val activeMode = audioMode == AudioManager.MODE_IN_CALL ||
            audioMode == MODE_CALL_SCREENING ||
            audioMode == MODE_CALL_REDIRECT ||
            audioMode == MODE_COMMUNICATION_REDIRECT ||
            (audioMode == AudioManager.MODE_IN_COMMUNICATION && !ownCommunication)
        return when {
            carrierState == TelephonyManager.CALL_STATE_OFFHOOK || activeMode -> "active"
            carrierState == TelephonyManager.CALL_STATE_RINGING ||
                audioMode == AudioManager.MODE_RINGTONE ||
                ringtonePlaying -> "ringing"
            telecomInCall() -> "active"
            else -> "idle"
        }
    }
}

internal object SecretBox {
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val IV_BYTES = 12
    private const val TAG_BITS = 128

    class Undecryptable(cause: Throwable?) : Exception(cause)

    fun seal(key: SecretKey, text: String): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8))
    }

    fun open(key: SecretKey, sealed: ByteArray): String {
        if (sealed.size <= IV_BYTES) throw Undecryptable(null)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES))
        val plain = try {
            cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
        } catch (e: AEADBadTagException) {
            throw Undecryptable(e)
        }
        return String(plain, Charsets.UTF_8)
    }
}
