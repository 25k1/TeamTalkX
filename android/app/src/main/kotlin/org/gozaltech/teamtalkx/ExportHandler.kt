package org.gozaltech.teamtalkx

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class ExportHandler(private val context: Context, messenger: BinaryMessenger) :
    ChannelHandler(messenger, CHANNEL) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> background(result) {
                    val name = call.argument<String>("fileName") ?: "export.txt"
                    remove(name)
                    val uri = insert(name, call.argument<String>("mimeType") ?: "")
                    write(uri) { it.write((call.argument<String>("content") ?: "").toByteArray()) }
                    "$RELATIVE_PATH/${displayName(uri) ?: name}"
                }
                "exists" -> background(result) { find(call.argument<String>("fileName") ?: "") != null }
                "remove" -> background(result) { remove(call.argument<String>("fileName") ?: "") }
                "publish" -> background(result) {
                    val source = File(call.argument<String>("path") ?: "")
                    val name = call.argument<String>("fileName") ?: source.name
                    val uri = insert(name, "")
                    write(uri) { out -> source.inputStream().use { it.copyTo(out) } }
                    source.delete()
                    mapOf(
                        "uri" to uri.toString(),
                        "path" to "$RELATIVE_PATH/${displayName(uri) ?: name}"
                    )
                }
                "open" -> {
                    result.success(open(Uri.parse(call.argument<String>("uri") ?: "")))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun find(fileName: String): Uri? {
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
            arrayOf(fileName, "$RELATIVE_PATH/"),
            null
        )?.use {
            if (it.moveToFirst()) {
                return Uri.withAppendedPath(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    it.getLong(0).toString()
                )
            }
        }
        return null
    }

    private fun remove(fileName: String): Boolean {
        val uri = find(fileName) ?: return false
        return try {
            context.contentResolver.delete(uri, null, null) > 0
        } catch (e: SecurityException) {
            false
        }
    }

    private fun insert(fileName: String, mimeType: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            if (mimeType.isNotEmpty()) put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        return context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create the file")
    }

    private fun write(uri: Uri, body: (java.io.OutputStream) -> Unit) {
        val resolver = context.contentResolver
        try {
            resolver.openOutputStream(uri).use { out ->
                out ?: throw IOException("Could not open the file")
                body(out)
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null
            )
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun displayName(uri: Uri): String? =
        context.contentResolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { if (it.moveToFirst()) it.getString(0) else null }

    private fun open(uri: Uri): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, context.contentResolver.getType(uri))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any) {
        worker.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e ->
                        Log.w(TAG, "Downloads", e)
                        result.error("export_failed", e.javaClass.simpleName, null)
                    }
                )
            }
        }
    }

    override fun dispose() {
        worker.shutdown()
        super.dispose()
    }

    companion object {
        const val CHANNEL = "org.gozaltech.teamtalkx/export"
        const val TAG = "TeamTalkXDownloads"
        val RELATIVE_PATH = "${Environment.DIRECTORY_DOWNLOADS}/TeamTalkX"
    }
}
