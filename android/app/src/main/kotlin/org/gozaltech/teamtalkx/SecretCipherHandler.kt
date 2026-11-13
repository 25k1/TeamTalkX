package org.gozaltech.teamtalkx

import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class SecretCipherHandler(
    messenger: BinaryMessenger
) : ChannelHandler(messenger, "org.gozaltech.teamtalkx/secrets") {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "encrypt" -> run(result) { encrypt(call.argument<String>("text") ?: "") }
                "decrypt" -> run(result) { decrypt(call.argument<String>("data") ?: "") }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(result: MethodChannel.Result, work: () -> String) {
        worker.execute {
            val outcome = try {
                Result.success(work())
            } catch (e: Throwable) {
                Result.failure(e)
            }
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e ->
                        val code = if (e is SecretBox.Undecryptable) "undecryptable" else "unavailable"
                        Log.w(TAG, "Secret $code", e)
                        result.error(code, e.javaClass.simpleName, null)
                    }
                )
            }
        }
    }

    private fun existingKey(): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return store.getKey(ALIAS, null) as? SecretKey
    }

    private fun key(): SecretKey {
        existingKey()?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypt(text: String): String =
        Base64.encodeToString(SecretBox.seal(key(), text), Base64.NO_WRAP)

    private fun decrypt(data: String): String {
        val key = existingKey() ?: throw SecretBox.Undecryptable(null)
        val bytes = try {
            Base64.decode(data, Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            throw SecretBox.Undecryptable(e)
        }
        return SecretBox.open(key, bytes)
    }

    override fun dispose() {
        worker.shutdown()
        super.dispose()
    }

    private companion object {
        const val TAG = "TeamTalkXSecrets"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "teamtalkx_secrets"
    }
}
