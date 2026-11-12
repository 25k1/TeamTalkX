package org.gozaltech.teamtalkx

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.app.PendingIntent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.security.MessageDigest

class UpdateHandler(private val context: Context, messenger: BinaryMessenger) :
    ChannelHandler(messenger, "org.gozaltech.teamtalkx/updates") {

    init {
        current = this
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "device" -> result.success(
                    mapOf(
                        "packageName" to context.packageName,
                        "abis" to Build.SUPPORTED_ABIS.toList(),
                        "debuggable" to
                            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
                    )
                )
                "isMetered" -> {
                    val cm = context.getSystemService(ConnectivityManager::class.java)
                    result.success(cm?.isActiveNetworkMetered ?: false)
                }
                "verify" -> result.success(verify(File(call.argument<String>("path") ?: "")))
                "canInstall" -> result.success(context.packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${context.packageName}")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    result.success(start(intent))
                }
                "install" -> {
                    try {
                        install(File(call.argument<String>("path") ?: ""))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Install failed to start", e)
                        result.error("install_failed", e.javaClass.simpleName, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun install(apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= 31) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("teamtalkx.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(context, UpdateInstallReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pending.intentSender)
        }
    }

    fun report(status: String, message: String?) {
        channel.invokeMethod("installStatus", mapOf("status" to status, "message" to message))
    }

    private fun start(intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private fun verify(apk: File): Map<String, Any?> {
        val pm = context.packageManager
        val archive = pm.getPackageArchiveInfo(
            apk.path,
            PackageManager.GET_SIGNING_CERTIFICATES
        ) ?: return mapOf("valid" to false)
        val installed = pm.getPackageInfo(
            context.packageName,
            PackageManager.GET_SIGNING_CERTIFICATES
        )
        @Suppress("DEPRECATION")
        val versionCode =
            if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        return mapOf(
            "valid" to true,
            "packageName" to archive.packageName,
            "versionName" to archive.versionName,
            "versionCode" to versionCode,
            "sameSigner" to (signers(archive) == signers(installed) && signers(archive).isNotEmpty())
        )
    }

    companion object {
        const val TAG = "TeamTalkXUpdates"

        @Volatile
        var current: UpdateHandler? = null
    }

    override fun dispose() {
        if (current === this) current = null
        super.dispose()
    }

    private fun signers(info: PackageInfo): Set<String> {
        val signing = info.signingInfo ?: return emptySet()
        val certs = if (signing.hasMultipleSigners()) {
            signing.apkContentsSigners
        } else {
            signing.signingCertificateHistory
        }
        val sha = MessageDigest.getInstance("SHA-256")
        return certs.map { cert ->
            sha.digest(cert.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }
}
