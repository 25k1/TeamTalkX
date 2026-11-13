package org.gozaltech.teamtalkx

import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.telephony.TelephonyManager
import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlatformRulesTest {
    @Test
    fun mediaKeysMapToTheirActions() {
        for (code in listOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
        )) {
            assertEquals("playPause", PlatformRules.mediaKeyName(code))
        }
        assertEquals("next", PlatformRules.mediaKeyName(KeyEvent.KEYCODE_MEDIA_NEXT))
        assertEquals("previous", PlatformRules.mediaKeyName(KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        assertEquals("fastForward", PlatformRules.mediaKeyName(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD))
        assertEquals("rewind", PlatformRules.mediaKeyName(KeyEvent.KEYCODE_MEDIA_REWIND))
        assertEquals("stop", PlatformRules.mediaKeyName(KeyEvent.KEYCODE_MEDIA_STOP))
    }

    @Test
    fun otherKeysAreLeftToTheSystem() {
        assertNull(PlatformRules.mediaKeyName(KeyEvent.KEYCODE_VOLUME_UP))
        assertNull(PlatformRules.mediaKeyName(KeyEvent.KEYCODE_A))
    }

    @Test
    fun outputsAreGroupedByKind() {
        assertEquals("speaker", PlatformRules.outputKind(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER))
        assertEquals("earpiece", PlatformRules.outputKind(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE))
        assertEquals("wired", PlatformRules.outputKind(AudioDeviceInfo.TYPE_WIRED_HEADPHONES))
        assertEquals("usb", PlatformRules.outputKind(AudioDeviceInfo.TYPE_USB_HEADSET))
        assertEquals("bluetooth", PlatformRules.outputKind(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP))
        assertEquals("bluetooth", PlatformRules.outputKind(AudioDeviceInfo.TYPE_BLE_HEADSET))
        assertEquals("hearingAid", PlatformRules.outputKind(AudioDeviceInfo.TYPE_HEARING_AID))
        assertNull(PlatformRules.outputKind(AudioDeviceInfo.TYPE_TELEPHONY))
    }

    @Test
    fun onlyMediaThatIsNotSpeechOrSoundsCountsAsOtherAudio() {
        assertTrue(
            PlatformRules.isOtherAppAudio(AudioAttributes.USAGE_MEDIA, AudioAttributes.CONTENT_TYPE_MUSIC)
        )
        assertTrue(
            PlatformRules.isOtherAppAudio(AudioAttributes.USAGE_MEDIA, AudioAttributes.CONTENT_TYPE_MOVIE)
        )
        assertFalse(
            PlatformRules.isOtherAppAudio(AudioAttributes.USAGE_MEDIA, AudioAttributes.CONTENT_TYPE_SPEECH)
        )
        assertFalse(
            PlatformRules.isOtherAppAudio(
                AudioAttributes.USAGE_MEDIA,
                AudioAttributes.CONTENT_TYPE_SONIFICATION,
            )
        )
        assertFalse(
            PlatformRules.isOtherAppAudio(
                AudioAttributes.USAGE_NOTIFICATION,
                AudioAttributes.CONTENT_TYPE_MUSIC,
            )
        )
    }

    private fun state(
        carrier: Int = TelephonyManager.CALL_STATE_IDLE,
        mode: Int = AudioManager.MODE_NORMAL,
        ringtone: Boolean = false,
        own: Boolean = false,
        telecom: Boolean = false,
    ) = PlatformRules.callState(carrier, mode, ringtone, own) { telecom }

    @Test
    fun idleWhenNothingIsGoingOn() {
        assertEquals("idle", state())
    }

    @Test
    fun carrierCallsAreActiveOrRinging() {
        assertEquals("active", state(carrier = TelephonyManager.CALL_STATE_OFFHOOK))
        assertEquals("ringing", state(carrier = TelephonyManager.CALL_STATE_RINGING))
    }

    @Test
    fun callAudioModesAreActive() {
        for (mode in listOf(
            AudioManager.MODE_IN_CALL,
            PlatformRules.MODE_CALL_SCREENING,
            PlatformRules.MODE_CALL_REDIRECT,
            PlatformRules.MODE_COMMUNICATION_REDIRECT,
        )) {
            assertEquals("active", state(mode = mode))
        }
    }

    @Test
    fun anotherAppsVoipCallIsActiveButOurOwnIsNot() {
        assertEquals("active", state(mode = AudioManager.MODE_IN_COMMUNICATION))
        assertEquals("idle", state(mode = AudioManager.MODE_IN_COMMUNICATION, own = true))
    }

    @Test
    fun ringtonesRing() {
        assertEquals("ringing", state(mode = AudioManager.MODE_RINGTONE))
        assertEquals("ringing", state(ringtone = true))
    }

    @Test
    fun telecomIsAskedOnlyAsALastResort() {
        assertEquals("active", state(telecom = true))
        var asked = false
        PlatformRules.callState(
            TelephonyManager.CALL_STATE_RINGING,
            AudioManager.MODE_NORMAL,
            ringtonePlaying = false,
            ownCommunication = false,
        ) {
            asked = true
            true
        }
        assertFalse(asked)
    }
}
