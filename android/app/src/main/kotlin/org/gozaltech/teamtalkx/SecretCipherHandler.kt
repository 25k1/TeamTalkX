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
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

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
                        val code = if (e is Undecryptable) "undecryptable" else "unavailable"
                        Log.w(TAG, "Secret $code", e)
                        result.error(code, e.javaClass.simpleName, null)
                    }
                )
            }
        }
    }

    private class Undecryptable(cause: Throwable?) : Exception(cause)

    private fun key(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        if (!create) return null
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

    private fun encrypt(text: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        val iv = cipher.iv
        val sealed = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + sealed, Base64.NO_WRAP)
    }

    private fun decrypt(data: String): String {
        val key = key(create = false) ?: throw Undecryptable(null)
        val bytes = try {
            Base64.decode(data, Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            throw Undecryptable(e)
        }
        if (bytes.size <= IV_BYTES) throw Undecryptable(null)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES)
        )
        val plain = try {
            cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)
        } catch (e: javax.crypto.AEADBadTagException) {
            throw Undecryptable(e)
        }
        return String(plain, Charsets.UTF_8)
    }

    override fun dispose() {
        worker.shutdown()
        super.dispose()
    }

    private companion object {
        const val TAG = "TeamTalkXSecrets"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "teamtalkx_secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
