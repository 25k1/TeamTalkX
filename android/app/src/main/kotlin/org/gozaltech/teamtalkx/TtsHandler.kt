package org.gozaltech.teamtalkx

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.speech.tts.TextToSpeech
import java.util.Locale
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class TtsHandler(
    private val context: Context,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/tts") {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var utteranceId = 0

    private var volume = 1.0f
    private var accessibilityStream = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> initEngine(call.argument<String>("engine"), result)
                "getEngines" -> result.success(
                    tts?.engines?.map {
                        mapOf("name" to it.name, "label" to it.label)
                    } ?: emptyList<Map<String, String>>()
                )
                "getLanguages" -> result.success(availableLanguages())
                "getVoices" -> result.success(availableVoices())
                "configure" -> {
                    configure(call)
                    result.success(null)
                }
                "speak" -> {
                    speak(
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("interrupt") == true
                    )
                    result.success(null)
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initEngine(engine: String?, result: MethodChannel.Result) {
        tts?.shutdown()
        ready = false
        var replied = false
        tts = TextToSpeech(context, { status ->
            ready = status == TextToSpeech.SUCCESS
            if (!replied) {
                replied = true
                result.success(ready)
            }
        }, if (engine.isNullOrEmpty()) null else engine)
    }

    private fun availableLanguages(): List<String> {
        val engine = tts ?: return emptyList()
        return try {
            engine.availableLanguages?.map { it.toLanguageTag() }?.sorted()
                ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun availableVoices(): List<Map<String, String>> {
        val engine = tts ?: return emptyList()
        return try {
            engine.voices?.filter { !it.isNetworkConnectionRequired }?.map {
                mapOf("name" to it.name, "locale" to it.locale.toLanguageTag())
            }?.sortedBy { it["name"] } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun configure(call: io.flutter.plugin.common.MethodCall) {
        val engine = tts ?: return
        val language = call.argument<String>("language") ?: ""
        val voiceName = call.argument<String>("voice") ?: ""
        val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
        val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
        volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
        accessibilityStream = call.argument<Boolean>("accessibilityStream") ?: false

        if (language.isNotEmpty()) {
            engine.language = Locale.forLanguageTag(language)
        }
        if (voiceName.isNotEmpty()) {
            try {
                engine.voices?.firstOrNull { it.name == voiceName }?.let {
                    engine.voice = it
                }
            } catch (e: Exception) {

            }
        }
        engine.setSpeechRate(rate)
        engine.setPitch(pitch)
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(
                    if (accessibilityStream)
                        AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY
                    else
                        AudioAttributes.USAGE_MEDIA
                )
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
    }

    private fun speak(text: String, interrupt: Boolean) {
        if (!ready || text.isEmpty()) return
        val params = Bundle()
        params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        val mode = if (interrupt) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        tts?.speak(text, mode, params, "tt${utteranceId++}")
    }

    override fun dispose() {
        tts?.shutdown()
        tts = null
        super.dispose()
    }
}
