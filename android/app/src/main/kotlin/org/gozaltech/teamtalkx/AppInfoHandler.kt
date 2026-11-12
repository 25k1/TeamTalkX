package org.gozaltech.teamtalkx

import android.content.Context
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger

class AppInfoHandler(
    context: Context,
    messenger: BinaryMessenger,
    private val onFullyDrawn: () -> Unit,
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/appinfo") {

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "version" -> try {
                    val info = context.packageManager.getPackageInfo(context.packageName, 0)
                    result.success(info.versionName)
                } catch (e: PackageManager.NameNotFoundException) {
                    result.error("unavailable", e.message, null)
                }
                "fullyDrawn" -> {
                    onFullyDrawn()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
