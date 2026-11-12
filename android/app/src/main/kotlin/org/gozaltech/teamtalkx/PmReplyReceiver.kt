package org.gozaltech.teamtalkx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

class PmReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val userId = intent.getIntExtra(PmNotificationHandler.EXTRA_PM_USER, 0)
        val text = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(PmNotificationHandler.KEY_REPLY)
            ?.toString()
            ?.takeIf { it.isNotBlank() }
        if (userId != 0 && text != null) {
            Handler(Looper.getMainLooper()).post {
                PmNotificationHandler.pmChannel?.invokeMethod(
                    "reply",
                    mapOf("userId" to userId, "text" to text)
                )
            }
        }
        NotificationManagerCompat.from(context).cancel(userId)
    }
}
