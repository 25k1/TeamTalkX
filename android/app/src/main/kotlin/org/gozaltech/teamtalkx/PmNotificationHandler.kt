package org.gozaltech.teamtalkx

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PmNotificationHandler(
    private val activity: MainActivity,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, CHANNEL) {

    init {
        pmChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    show(
                        call.argument<Int>("userId") ?: 0,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("message") ?: ""
                    )
                    result.success(null)
                }
                "cancel" -> {
                    NotificationManagerCompat.from(activity)
                        .cancel(call.argument<Int>("userId") ?: 0)
                    result.success(null)
                }
                "getInitialPm" -> result.success(activity.consumeInitialPm())
                else -> result.notImplemented()
            }
        }
        createChannel()
    }

    private fun createChannel() {
        val ch = NotificationChannel(
            NOTIF_CHANNEL,
            "Private messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {

            setSound(null, null)
            enableVibration(false)
        }
        (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(ch)
    }

    private fun show(userId: Int, title: String, message: String) {
        if (userId == 0) return

        val tapIntent = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(EXTRA_PM_USER, userId)
        }
        val tapPending = PendingIntent.getActivity(
            activity, userId, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val remoteInput = RemoteInput.Builder(KEY_REPLY).setLabel("Reply").build()
        val replyIntent = Intent(activity, PmReplyReceiver::class.java)
            .putExtra(EXTRA_PM_USER, userId)
        val replyPending = PendingIntent.getBroadcast(
            activity, userId, replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send, "Reply", replyPending
        ).addRemoteInput(remoteInput).build()

        val notification = NotificationCompat.Builder(activity, NOTIF_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(tapPending)
            .addAction(replyAction)
            .build()

        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (allowed) {
            NotificationManagerCompat.from(activity).notify(userId, notification)
        }
    }

    override fun dispose() {
        super.dispose()
        if (pmChannel === channel) pmChannel = null
    }

    companion object {
        const val CHANNEL = "org.gozaltech.teamtalkx/pmnotify"

        const val NOTIF_CHANNEL = "pm_messages"
        const val EXTRA_PM_USER = "pm_user_id"
        const val KEY_REPLY = "pm_reply"

        @Volatile
        var pmChannel: MethodChannel? = null
    }
}
