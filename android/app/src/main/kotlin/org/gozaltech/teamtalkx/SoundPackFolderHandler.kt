package org.gozaltech.teamtalkx

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class SoundPackFolderHandler(
    private val activity: Activity,
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/sound_pack_folder") {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var pendingWrite = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result, call.argument<Boolean>("write") ?: false)
                "release" -> {
                    release(call.argument<String>("tree"))
                    result.success(null)
                }
                "save" -> background(result) {
                    save(
                        Uri.parse(call.argument<String>("tree")),
                        File(call.argument<String>("path") ?: ""),
                        call.argument<String>("name") ?: "recording"
                    )
                }
                "list" -> background(result) { list(Uri.parse(call.argument<String>("tree"))) }
                "read" -> background(result) {
                    activity.contentResolver
                        .openInputStream(Uri.parse(call.argument<String>("uri")))
                        ?.use { it.readBytes() }
                        ?: throw IllegalStateException("No stream")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pick(result: MethodChannel.Result, write: Boolean) {
        pendingPick?.success(null)
        pendingPick = result
        pendingWrite = write
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                (if (write) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
        )
        try {
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            Log.w(TAG, "No folder picker", e)
            pendingPick = null
            result.error("unavailable", e.javaClass.simpleName, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    (if (pendingWrite) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
            )
            result.success(mapOf("tree" to tree.toString(), "name" to displayName(tree)))
        } catch (e: SecurityException) {
            Log.w(TAG, "Folder access not granted", e)
            result.success(null)
        }
        return true
    }

    private fun release(tree: String?) {
        if (tree.isNullOrEmpty()) return
        for (flag in listOf(
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )) {
            try {
                activity.contentResolver.releasePersistableUriPermission(Uri.parse(tree), flag)
            } catch (e: SecurityException) {
            }
        }
    }

    private fun save(tree: Uri, source: File, name: String): String {
        val folder = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree)
        )
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
        val doc = DocumentsContract.createDocument(activity.contentResolver, folder, mime, name)
            ?: throw IllegalStateException("The file could not be created")
        try {
            activity.contentResolver.openOutputStream(doc)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw IllegalStateException("No stream")
        } catch (e: Exception) {
            runCatching { DocumentsContract.deleteDocument(activity.contentResolver, doc) }
            throw e
        }
        source.delete()
        return documentName(doc) ?: name
    }

    private fun documentName(doc: Uri): String? {
        activity.contentResolver.query(
            doc,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { if (it.moveToFirst()) return it.getString(0) }
        return null
    }

    private fun displayName(tree: Uri): String {
        val doc = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree)
        )
        activity.contentResolver.query(
            doc,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { if (it.moveToFirst()) return it.getString(0) ?: "" }
        return ""
    }

    private data class Child(val id: String, val name: String, val isDir: Boolean, val modified: Long)

    private fun children(tree: Uri, parentId: String): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val out = mutableListOf<Child>()
        activity.contentResolver.query(
            uri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            ),
            null,
            null,
            null
        )?.use { c ->
            while (c.moveToNext()) {
                out += Child(
                    id = c.getString(0),
                    name = c.getString(1) ?: "",
                    isDir = c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                    modified = if (c.isNull(3)) 0L else c.getLong(3)
                )
            }
        } ?: throw SecurityException("The folder can't be read")
        return out
    }

    private fun sounds(tree: Uri, files: List<Child>): List<Map<String, Any>> =
        files.filter { !it.isDir && it.name.substringAfterLast('.', "").lowercase() in EXTENSIONS }
            .map {
                mapOf(
                    "name" to it.name,
                    "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, it.id).toString(),
                    "modified" to it.modified
                )
            }

    private fun list(tree: Uri): List<Map<String, Any>> {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val top = children(tree, rootId)
        val packs = mutableListOf<Map<String, Any>>()
        val rootSounds = sounds(tree, top)
        if (rootSounds.isNotEmpty()) {
            packs += mapOf("name" to displayName(tree), "sounds" to rootSounds)
        }
        for (dir in top.filter { it.isDir }) {
            val packSounds = sounds(tree, children(tree, dir.id))
            if (packSounds.isNotEmpty()) packs += mapOf("name" to dir.name, "sounds" to packSounds)
        }
        return packs
    }

    private fun background(result: MethodChannel.Result, work: () -> Any) {
        worker.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e ->
                        Log.w(TAG, "Picked folder", e)
                        result.error("unreadable", e.javaClass.simpleName, null)
                    }
                )
            }
        }
    }

    override fun dispose() {
        pendingPick?.success(null)
        pendingPick = null
        worker.shutdown()
        super.dispose()
    }

    private companion object {
        const val TAG = "TeamTalkXFolders"
        const val REQUEST_PICK = 4711
        val EXTENSIONS = setOf("wav", "ogg", "mp3", "m4a", "opus", "flac")
    }
}
