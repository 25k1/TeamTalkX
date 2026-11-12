package org.gozaltech.teamtalkx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
                UpdateHandler.current?.report("confirm", null)
            }
            PackageInstaller.STATUS_SUCCESS -> UpdateHandler.current?.report("success", null)
            PackageInstaller.STATUS_FAILURE_ABORTED -> UpdateHandler.current?.report("cancelled", message)
            else -> {
                Log.w(UpdateHandler.TAG, "Install failed: $status $message")
                UpdateHandler.current?.report("failed", message)
            }
        }
    }
}
