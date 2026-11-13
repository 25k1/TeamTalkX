package org.gozaltech.teamtalkx

import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class SecretBoxTest {
    private fun newKey(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test
    fun sealedTextOpensWithTheSameKey() {
        val key = newKey()
        val text = "server password: ქართული, русский"
        assertEquals(text, SecretBox.open(key, SecretBox.seal(key, text)))
    }

    @Test
    fun everySealUsesAFreshNonce() {
        val key = newKey()
        val a = SecretBox.seal(key, "same")
        val b = SecretBox.seal(key, "same")
        assertNotEquals(
            a.copyOfRange(0, SecretBox.IV_BYTES).toList(),
            b.copyOfRange(0, SecretBox.IV_BYTES).toList(),
        )
    }

    @Test(expected = SecretBox.Undecryptable::class)
    fun aChangedByteIsRefused() {
        val key = newKey()
        val sealed = SecretBox.seal(key, "secret")
        sealed[sealed.size - 1] = (sealed[sealed.size - 1].toInt() xor 1).toByte()
        SecretBox.open(key, sealed)
    }

    @Test(expected = SecretBox.Undecryptable::class)
    fun anotherKeyIsRefused() {
        SecretBox.open(newKey(), SecretBox.seal(newKey(), "secret"))
    }

    @Test(expected = SecretBox.Undecryptable::class)
    fun dataShorterThanTheNonceIsRefused() {
        SecretBox.open(newKey(), ByteArray(SecretBox.IV_BYTES))
    }
}
