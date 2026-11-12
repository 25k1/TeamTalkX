package org.gozaltech.teamtalkx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.plugin.common.MethodChannel

class ConnectionForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopSelf()
            ACTION_TOGGLE_TX -> sendAction("toggleTransmission")
            ACTION_STOP_RECORDING -> sendAction("stopRecording")
            else -> {
                val serverName = intent?.getStringExtra(EXTRA_SERVER) ?: ""
                val channelName = intent?.getStringExtra(EXTRA_CHANNEL) ?: ""
                val transmitting = intent?.getBooleanExtra(EXTRA_TRANSMITTING, false) ?: false
                val recording = intent?.getBooleanExtra(EXTRA_RECORDING, false) ?: false
                val keepAwake = intent?.getBooleanExtra(EXTRA_KEEP_AWAKE, false) ?: false
                startForegroundWithNotification(serverName, channelName, transmitting, recording)
                if (keepAwake) acquireWakeLock() else releaseWakeLock()
            }
        }

        return START_NOT_STICKY
    }

    private fun sendAction(method: String) {
        Handler(Looper.getMainLooper()).post {
            runCatching { actionChannel?.invokeMethod(method, null) }
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {

        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun startForegroundWithNotification(
        serverName: String,
        channelName: String,
        transmitting: Boolean,
        recording: Boolean
    ) {
        createNotificationChannel()
        val notification = buildNotification(serverName, channelName, transmitting, recording)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
    }

    private fun buildNotification(
        serverName: String,
        channelName: String,
        transmitting: Boolean,
        recording: Boolean
    ): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val body = if (channelName.isEmpty()) serverName else "$serverName / $channelName"
        val text = listOfNotNull(
            body,
            if (transmitting) getString(R.string.notification_transmitting) else null,
            if (recording) getString(R.string.notification_recording) else null
        ).joinToString(" ")
        val toggleIntent = Intent(this, ConnectionForegroundService::class.java)
            .setAction(ACTION_TOGGLE_TX)
        val togglePending = PendingIntent.getService(
            this,
            1,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val toggleLabel = if (transmitting) {
            getString(R.string.notification_stop_transmitting)
        } else {
            getString(R.string.notification_start_transmitting)
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_headset)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(0, toggleLabel, togglePending)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        if (recording) {
            val stopRecording = PendingIntent.getService(
                this,
                2,
                Intent(this, ConnectionForegroundService::class.java)
                    .setAction(ACTION_STOP_RECORDING),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, getString(R.string.notification_stop_recording), stopRecording)
        }
        return builder.build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )
        channel.setShowBadge(false)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "connection"
        private const val WAKELOCK_TAG = "teamtalkx:connection"
        private const val NOTIFICATION_ID = 1
        private const val EXTRA_SERVER = "serverName"
        private const val EXTRA_CHANNEL = "channelName"
        private const val EXTRA_TRANSMITTING = "transmitting"
        private const val EXTRA_RECORDING = "recording"
        private const val EXTRA_KEEP_AWAKE = "keepAwake"
        private const val ACTION_STOP = "org.gozaltech.teamtalkx.STOP"
        private const val ACTION_TOGGLE_TX = "org.gozaltech.teamtalkx.TOGGLE_TX"
        private const val ACTION_STOP_RECORDING = "org.gozaltech.teamtalkx.STOP_RECORDING"

        var actionChannel: MethodChannel? = null

        fun start(
            context: Context,
            serverName: String,
            channelName: String,
            transmitting: Boolean,
            recording: Boolean,
            keepAwake: Boolean
        ) {
            val intent = Intent(context, ConnectionForegroundService::class.java)
                .putExtra(EXTRA_SERVER, serverName)
                .putExtra(EXTRA_CHANNEL, channelName)
                .putExtra(EXTRA_TRANSMITTING, transmitting)
                .putExtra(EXTRA_RECORDING, recording)
                .putExtra(EXTRA_KEEP_AWAKE, keepAwake)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ConnectionForegroundService::class.java))
        }
    }
}
