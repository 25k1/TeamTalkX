package org.gozaltech.teamtalkx

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

abstract class ChannelHandler(messenger: BinaryMessenger, name: String) {
    protected val channel = MethodChannel(messenger, name)

    open fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
