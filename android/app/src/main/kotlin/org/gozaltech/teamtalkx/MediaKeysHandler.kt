package org.gozaltech.teamtalkx

import android.content.Context
import android.content.Intent
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger

class MediaKeysHandler(
    private val context: Context,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/media_keys") {
    private var session: MediaSessionCompat? = null
    private var mapped = emptySet<String>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    mapped = (call.argument<List<String>>("keys") ?: emptyList()).toSet()
                    if (call.argument<Boolean>("session") == true) startSession() else stopSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onKeyEvent(event: KeyEvent): Boolean {
        val key = PlatformRules.mediaKeyName(event.keyCode) ?: return false
        if (key !in mapped) return false
        report(key, event)
        return true
    }

    private val callback = object : MediaSessionCompat.Callback() {
        override fun onMediaButtonEvent(mediaButtonEvent: Intent): Boolean {
            val event: KeyEvent? = if (android.os.Build.VERSION.SDK_INT >= 33) {
                mediaButtonEvent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                mediaButtonEvent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
            }
            val key = event?.let { PlatformRules.mediaKeyName(it.keyCode) }
                ?: return super.onMediaButtonEvent(mediaButtonEvent)
            report(key, event)
            return true
        }

        override fun onPlay() = press("playPause")
        override fun onPause() = press("playPause")
        override fun onSkipToNext() = press("next")
        override fun onSkipToPrevious() = press("previous")
        override fun onFastForward() = press("fastForward")
        override fun onRewind() = press("rewind")
        override fun onStop() = press("stop")
    }

    private fun press(key: String) {
        channel.invokeMethod("key", mapOf("key" to key, "down" to true))
        channel.invokeMethod("key", mapOf("key" to key, "down" to false))
    }

    private fun report(key: String, event: KeyEvent) {
        when (event.action) {
            KeyEvent.ACTION_DOWN ->
                if (event.repeatCount == 0) {
                    channel.invokeMethod("key", mapOf("key" to key, "down" to true))
                }
            KeyEvent.ACTION_UP ->
                channel.invokeMethod("key", mapOf("key" to key, "down" to false))
        }
    }

    private fun startSession() {
        if (session != null) return
        session = MediaSessionCompat(context, "TeamTalkX").apply {
            setCallback(callback)
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                            PlaybackStateCompat.ACTION_PAUSE or
                            PlaybackStateCompat.ACTION_PLAY_PAUSE or
                            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackStateCompat.ACTION_FAST_FORWARD or
                            PlaybackStateCompat.ACTION_REWIND or
                            PlaybackStateCompat.ACTION_STOP
                    )
                    .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1.0f)
                    .build()
            )
            setMetadata(
                MediaMetadataCompat.Builder()
                    .putString(
                        MediaMetadataCompat.METADATA_KEY_TITLE,
                        context.applicationInfo.loadLabel(context.packageManager).toString()
                    )
                    .build()
            )
            isActive = true
        }
    }

    private fun stopSession() {
        session?.release()
        session = null
    }

    override fun dispose() {
        stopSession()
        super.dispose()
    }
}
