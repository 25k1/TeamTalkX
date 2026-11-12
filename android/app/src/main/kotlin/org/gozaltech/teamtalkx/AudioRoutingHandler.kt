package org.gozaltech.teamtalkx

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger

class AudioRoutingHandler(
    context: Context,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/audio_routing") {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var communication = false
        set(value) {
            field = value
            communicationActive = value
        }

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = changed()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = changed()
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "outputs" -> result.success(outputs())
                "setCommunication" -> {
                    setCommunication(
                        call.argument<Boolean>("on") == true,
                        call.argument<Int>("deviceId") ?: 0
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        audio.registerAudioDeviceCallback(deviceCallback, main)
    }

    private fun changed() {
        channel.invokeMethod("outputsChanged", null)
    }

    private fun outputs(): List<Map<String, Any>> =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .mapNotNull { d ->
                val kind = kindOf(d.type) ?: return@mapNotNull null
                mapOf("id" to d.id, "kind" to kind, "name" to d.productName.toString())
            }
            .distinctBy { "${it["kind"]}/${it["name"]}" }

    private fun kindOf(type: Int): String? = when (type) {
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

    private fun setCommunication(on: Boolean, deviceId: Int) {
        if (!on) {
            if (communication) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audio.clearCommunicationDevice()
                } else {
                    @Suppress("DEPRECATION")
                    audio.isSpeakerphoneOn = false
                    @Suppress("DEPRECATION")
                    audio.stopBluetoothSco()
                }
                communication = false
                audio.mode = AudioManager.MODE_NORMAL
            }
            return
        }
        communication = true
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = audio.availableCommunicationDevices.firstOrNull { it.id == deviceId }
                ?: audio.availableCommunicationDevices.firstOrNull { d ->
                    val chosen = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        .firstOrNull { it.id == deviceId }
                    chosen != null && kindOf(d.type) == kindOf(chosen.type) &&
                        d.productName == chosen.productName
                }
            if (device != null) {
                audio.setCommunicationDevice(device)
            } else {
                audio.clearCommunicationDevice()
            }
        } else {
            val chosen = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.id == deviceId }
            val kind = chosen?.let { kindOf(it.type) }
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = kind == "speaker"
            @Suppress("DEPRECATION")
            if (kind == "bluetooth") audio.startBluetoothSco() else audio.stopBluetoothSco()
        }
    }

    override fun dispose() {
        audio.unregisterAudioDeviceCallback(deviceCallback)
        setCommunication(false, 0)
        super.dispose()
    }

    companion object {
        @Volatile
        var communicationActive = false
            private set
    }
}
