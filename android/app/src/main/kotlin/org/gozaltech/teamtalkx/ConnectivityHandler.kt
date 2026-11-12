package org.gozaltech.teamtalkx

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger

class ConnectivityHandler(
    context: Context,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/connectivity") {
    private val manager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = post(true)
        override fun onLost(network: Network) = post(false)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnline" -> result.success(isOnline())
                else -> result.notImplemented()
            }
        }
        manager.registerDefaultNetworkCallback(callback)
    }

    private fun isOnline(): Boolean {
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun post(online: Boolean) {
        main.post { channel.invokeMethod("changed", online) }
    }

    override fun dispose() {
        try {
            manager.unregisterNetworkCallback(callback)
        } catch (e: IllegalArgumentException) {
        }
        super.dispose()
    }
}
