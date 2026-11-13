package org.gozaltech.teamtalkx

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var deepLinkChannel: MethodChannel? = null
    private var initialLink: String? = null
    private var initialFileXml: String? = null
    private var mediaKeys: MediaKeysHandler? = null
    private var ttsHandler: TtsHandler? = null
    private var pmNotifications: PmNotificationHandler? = null
    private var hotkey: HotkeyHandler? = null
    private var export: ExportHandler? = null
    private var appInfo: AppInfoHandler? = null
    private var connectivity: ConnectivityHandler? = null
    private var audioRouting: AudioRoutingHandler? = null
    private var interruptions: InterruptionsHandler? = null
    private var secrets: SecretCipherHandler? = null
    private var soundPackFolder: SoundPackFolderHandler? = null
    private var updates: UpdateHandler? = null
    private var initialPmUser = 0

    fun consumeInitialPm(): Int {
        val user = initialPmUser
        initialPmUser = 0
        return user
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        intent?.let { launch ->
            val data = launch.data
            when {
                data?.scheme == "tt" -> initialLink = launch.dataString
                data != null -> initialFileXml = readTextUri(data)
            }
        }
        initialPmUser = intent?.getIntExtra(PmNotificationHandler.EXTRA_PM_USER, 0) ?: 0
        mediaKeys = MediaKeysHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        ttsHandler = TtsHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        pmNotifications = PmNotificationHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )
        hotkey = HotkeyHandler(flutterEngine.dartExecutor.binaryMessenger)
        export = ExportHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        appInfo = AppInfoHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            onFullyDrawn = { reportFullyDrawn() },
        )
        connectivity = ConnectivityHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        audioRouting = AudioRoutingHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        interruptions = InterruptionsHandler(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
        secrets = SecretCipherHandler(flutterEngine.dartExecutor.binaryMessenger)
        soundPackFolder = SoundPackFolderHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        updates = UpdateHandler(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        ConnectionForegroundService.actionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.gozaltech.teamtalkx/foreground_action"
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.gozaltech.teamtalkx/foreground"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    ConnectionForegroundService.start(
                        this,
                        call.argument<String>("serverName") ?: "",
                        call.argument<String>("channelName") ?: "",
                        call.argument<Map<String, String>>("text") ?: emptyMap(),
                        call.argument<Boolean>("transmitting") ?: false,
                        call.argument<Boolean>("recording") ?: false,
                        call.argument<Boolean>("keepAwake") ?: false
                    )
                    result.success(null)
                }
                "stop" -> {
                    ConnectionForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.gozaltech.teamtalkx/haptics"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "waveform" -> {
                    val timings = (call.argument<List<Int>>("timings") ?: emptyList())
                        .map { it.toLong() }.toLongArray()
                    val amplitudes = (call.argument<List<Int>>("amplitudes") ?: emptyList())
                        .toIntArray()
                    result.success(vibrateWaveform(timings, amplitudes))
                }
                else -> result.notImplemented()
            }
        }

        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.gozaltech.teamtalkx/deeplink"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(initialLink)
                        initialLink = null
                    }
                    "getInitialFile" -> {
                        result.success(initialFileXml)
                        initialFileXml = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private fun vibrateWaveform(timings: LongArray, amplitudes: IntArray): Boolean {
        if (timings.isEmpty()) return false
        val v = vibrator()
        if (!v.hasVibrator() || !v.hasAmplitudeControl()) return false
        return try {
            v.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (hotkey?.onKeyEvent(event) == true) return true
        if (mediaKeys?.onKeyEvent(event) == true) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val pmUser = intent.getIntExtra(PmNotificationHandler.EXTRA_PM_USER, 0)
        if (pmUser != 0) {
            PmNotificationHandler.pmChannel?.invokeMethod("openPm", pmUser)
        }
        val data = intent.data
        when {
            data?.scheme == "tt" ->
                deepLinkChannel?.invokeMethod("onLink", intent.dataString)
            data != null ->
                readTextUri(data)?.let { deepLinkChannel?.invokeMethod("onFile", it) }
        }
    }

    private fun readTextUri(uri: android.net.Uri): String? = try {
        contentResolver.openInputStream(uri)?.use {
            it.readBytes().toString(Charsets.UTF_8)
        }
    } catch (e: Exception) {
        null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (soundPackFolder?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        mediaKeys?.dispose()
        mediaKeys = null
        ttsHandler?.dispose()
        ttsHandler = null
        pmNotifications?.dispose()
        pmNotifications = null
        hotkey?.dispose()
        hotkey = null
        export?.dispose()
        export = null
        appInfo?.dispose()
        appInfo = null
        connectivity?.dispose()
        connectivity = null
        audioRouting?.dispose()
        audioRouting = null
        interruptions?.dispose()
        interruptions = null
        secrets?.dispose()
        secrets = null
        soundPackFolder?.dispose()
        soundPackFolder = null
        updates?.dispose()
        updates = null
        ConnectionForegroundService.actionChannel = null
        super.onDestroy()
    }
}
