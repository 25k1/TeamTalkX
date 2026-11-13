package org.gozaltech.teamtalkx

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger

class InterruptionsHandler(
    private val context: Context,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/interruptions") {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val telephony =
        context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    private val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
    private val main = Handler(Looper.getMainLooper())

    private var monitoring = false
    private var carrierState = TelephonyManager.CALL_STATE_IDLE
    private var ringtonePlaying = false
    private var reportedCall: String? = null
    private var reportedOtherPlaying: Boolean? = null
    private var telephonyCallback: Any? = null
    private var modeListener: Any? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { start(); result.success(null) }
                "stop" -> { stop(); result.success(null) }
                "duckOthers" -> {
                    duckOthers(call.argument<Boolean>("voiceCall") == true)
                    result.success(null)
                }
                "stopDuckingOthers" -> { stopDuckingOthers(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private val playbackCallback = object : AudioManager.AudioPlaybackCallback() {
        override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>) =
            update(configs)
    }

    private val poll = object : Runnable {
        override fun run() {
            if (!monitoring) return
            update(null)
            if (reportedCall != "idle") main.postDelayed(this, POLL_MS)
        }
    }

    @Suppress("DEPRECATION")
    private val phoneStateListener = object : PhoneStateListener() {
        @Deprecated("Deprecated in API 31; used before it")
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            carrierState = state
            update(null)
        }
    }

    private var focusRequest: AudioFocusRequest? = null

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK ->
                channel.invokeMethod("focus", "ducked")
            AudioManager.AUDIOFOCUS_GAIN ->
                channel.invokeMethod("focus", "regained")
            AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                focusRequest?.let { audio.abandonAudioFocusRequest(it) }
                focusRequest = null
                channel.invokeMethod("focus", "lost")
            }
        }
    }

    private fun duckOthers(voiceCall: Boolean) {
        if (focusRequest != null) return
        val attributes = AudioAttributes.Builder()
            .setUsage(
                if (voiceCall) AudioAttributes.USAGE_VOICE_COMMUNICATION
                else AudioAttributes.USAGE_GAME
            )
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attributes)
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener(focusListener, main)
            .build()
        if (audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            focusRequest = request
        } else {
            channel.invokeMethod("focus", "lost")
        }
    }

    private fun stopDuckingOthers() {
        focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    private fun hasPhonePermission() =
        context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    private fun start() {
        if (monitoring) return
        monitoring = true
        reportedCall = null
        reportedOtherPlaying = null
        carrierState = TelephonyManager.CALL_STATE_IDLE
        audio.registerAudioPlaybackCallback(playbackCallback, main)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val listener = AudioManager.OnModeChangedListener { update(null) }
            audio.addOnModeChangedListener(context.mainExecutor, listener)
            modeListener = listener
            if (hasPhonePermission()) {
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        carrierState = state
                        update(null)
                    }
                }
                try {
                    telephony.registerTelephonyCallback(context.mainExecutor, callback)
                    telephonyCallback = callback
                } catch (e: SecurityException) {
                    telephonyCallback = null
                }
            }
        } else {
            @Suppress("DEPRECATION")
            telephony.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
        }
        update(audio.activePlaybackConfigurations)
    }

    private fun stop() {
        if (!monitoring) return
        monitoring = false
        main.removeCallbacks(poll)
        audio.unregisterAudioPlaybackCallback(playbackCallback)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (modeListener as? AudioManager.OnModeChangedListener)?.let {
                audio.removeOnModeChangedListener(it)
            }
            (telephonyCallback as? TelephonyCallback)?.let {
                telephony.unregisterTelephonyCallback(it)
            }
        } else {
            @Suppress("DEPRECATION")
            telephony.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
        }
        modeListener = null
        telephonyCallback = null
    }

    private fun update(configs: List<AudioPlaybackConfiguration>?) {
        if (!monitoring) return
        if (configs != null) {
            ringtonePlaying = configs.any {
                it.audioAttributes.usage == AudioAttributes.USAGE_NOTIFICATION_RINGTONE
            }
            val other = configs.any {
                PlatformRules.isOtherAppAudio(it.audioAttributes.usage, it.audioAttributes.contentType)
            }
            if (other != reportedOtherPlaying) {
                reportedOtherPlaying = other
                channel.invokeMethod("otherPlaying", other)
            }
        }
        val call = callState()
        if (call != reportedCall) {
            reportedCall = call
            channel.invokeMethod("callState", call)
            main.removeCallbacks(poll)
            if (call != "idle") main.postDelayed(poll, POLL_MS)
        }
    }

    private fun callState(): String = PlatformRules.callState(
        carrierState = carrierState,
        audioMode = audio.mode,
        ringtonePlaying = ringtonePlaying,
        ownCommunication = AudioRoutingHandler.communicationActive,
    ) { telecomInCall() }

    private fun telecomInCall(): Boolean {
        if (!hasPhonePermission()) return false
        return try {
            telecom.isInCall
        } catch (e: SecurityException) {
            false
        }
    }

    override fun dispose() {
        stop()
        stopDuckingOthers()
        super.dispose()
    }

    companion object {
        private const val POLL_MS = 2000L

    }
}
