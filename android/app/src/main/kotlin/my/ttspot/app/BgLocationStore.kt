package my.ttspot.app

import android.Manifest
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * "Share location when TT Spot is closed": what the native side remembers.
 *
 * App-private SharedPreferences hold the Supabase URL, the publishable key and
 * the member id. The location token itself is encrypted with an AES-256-GCM key
 * that lives in the Android Keystore (never leaves the secure hardware where
 * there is one), so a copied prefs file or a cloud backup restored on another
 * phone is useless. The Supabase session is never touched from here.
 */
object BgLocationStore {
    private const val PREFS = "ttspot_bglocation"
    private const val KEY_ALIAS = "ttspot_bglocation_token_key"

    data class Config(val url: String, val apiKey: String, val token: String, val userId: String, val devCa: String?)

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Random per install; names this phone on the server (one live token per phone). */
    fun installId(ctx: Context): String {
        val p = prefs(ctx)
        p.getString("install_id", null)?.let { return it }
        val id = UUID.randomUUID().toString().replace("-", "")
        p.edit().putString("install_id", id).apply()
        return id
    }

    fun deviceLabel(ctx: Context): String {
        val model = listOf(Build.MANUFACTURER, Build.MODEL).filter { !it.isNullOrBlank() }.joinToString(" ").ifBlank { "Android" }
        return "${model.take(80)} (${installId(ctx).take(8)})"
    }

    fun save(ctx: Context, url: String, apiKey: String, token: String, userId: String, devCa: String?) {
        prefs(ctx).edit()
            .putBoolean("enabled", true)
            .putBoolean("paused", false)
            .putString("url", url)
            .putString("api_key", apiKey)
            .putString("token", encrypt(token))
            .putString("user_id", userId)
            .putString("dev_ca", devCa)
            .remove("last_result")
            .remove("last_at")
            .apply()
    }

    /** The saved setup, or null when the feature is off (or the token can't be read). */
    fun load(ctx: Context): Config? {
        val p = prefs(ctx)
        if (!p.getBoolean("enabled", false)) return null
        val url = p.getString("url", null) ?: return null
        val key = p.getString("api_key", null) ?: return null
        val user = p.getString("user_id", null) ?: return null
        val token = p.getString("token", null)?.let { decrypt(it) } ?: return null
        return Config(url, key, token, user, p.getString("dev_ca", null))
    }

    fun isPaused(ctx: Context) = prefs(ctx).getBoolean("paused", false)
    fun setPaused(ctx: Context, paused: Boolean) = prefs(ctx).edit().putBoolean("paused", paused).apply()

    /** Feature off: forget the token and the member, keep the install id. */
    fun clear(ctx: Context, reason: String) {
        prefs(ctx).edit()
            .putBoolean("enabled", false)
            .putBoolean("paused", false)
            .remove("url").remove("api_key").remove("token").remove("user_id").remove("dev_ca")
            .putString("last_result", reason)
            .putLong("last_at", System.currentTimeMillis())
            .apply()
    }

    fun setLast(ctx: Context, result: String) {
        prefs(ctx).edit().putString("last_result", result).putLong("last_at", System.currentTimeMillis()).apply()
    }

    fun status(ctx: Context): Map<String, Any?> {
        val p = prefs(ctx)
        val cfg = load(ctx)
        return mapOf(
            "enabled" to (cfg != null),
            "paused" to p.getBoolean("paused", false),
            "running" to BgLocationService.running,
            "userId" to cfg?.userId,
            "lastResult" to p.getString("last_result", null),
            "lastAt" to p.getLong("last_at", 0L).takeIf { it > 0L },
            "background" to hasBackgroundPermission(ctx),
            "foreground" to hasForegroundPermission(ctx),
            "device" to deviceLabel(ctx),
        )
    }

    // ------------------------------------------------------------ permissions

    fun hasForegroundPermission(ctx: Context): Boolean =
        ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ctx.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** "Allow all the time". Before Android 10 the foreground grant covers it. */
    fun hasBackgroundPermission(ctx: Context): Boolean {
        if (!hasForegroundPermission(ctx)) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ctx.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    // ------------------------------------------------------------- the token

    private fun keystoreKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String = try {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, keystoreKey())
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        "gcm:" + Base64.encodeToString(c.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(ct, Base64.NO_WRAP)
    } catch (e: Exception) {
        // No usable keystore (rare, broken ROMs): app-private storage only.
        "plain:$plain"
    }

    private fun decrypt(stored: String): String? = try {
        when {
            stored.startsWith("plain:") -> stored.removePrefix("plain:")
            stored.startsWith("gcm:") -> {
                val parts = stored.split(":")
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, keystoreKey(), GCMParameterSpec(128, Base64.decode(parts[1], Base64.NO_WRAP)))
                String(c.doFinal(Base64.decode(parts[2], Base64.NO_WRAP)), Charsets.UTF_8)
            }
            else -> null
        }
    } catch (e: Exception) {
        null
    }

    // ------------------------------------------------------------------ http

    /**
     * POST <url>/rest/v1/rpc/<fn> as anon (publishable key only, no session).
     * Blocking: call it off the main thread. Returns (HTTP code, body).
     */
    fun rpc(ctx: Context, cfg: Config, fn: String, body: JSONObject): Pair<Int, String?> {
        val conn = URL("${cfg.url.trimEnd('/')}/rest/v1/rpc/$fn").openConnection() as HttpURLConnection
        try {
            if (conn is HttpsURLConnection) devSocketFactory(ctx, cfg.devCa)?.let { conn.sslSocketFactory = it }
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("apikey", cfg.apiKey)
            // A legacy anon JWT also goes in Authorization; the new sb_publishable_ keys must not.
            if (cfg.apiKey.startsWith("eyJ")) conn.setRequestProperty("Authorization", "Bearer ${cfg.apiKey}")
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }
            return code to text
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Debug builds only, mirroring main.dart: also trust the dev machine's
     * antivirus root (env.json DEV_EXTRA_CA_PEM_B64) so the emulator can reach
     * Supabase. Release builds never get a value and never call this.
     */
    private fun devSocketFactory(ctx: Context, pemB64: String?): SSLSocketFactory? {
        if (pemB64.isNullOrEmpty()) return null
        if ((ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return null
        return try {
            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(Base64.decode(pemB64, Base64.DEFAULT))) as X509Certificate
            val extraStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null); setCertificateEntry("dev", cert) }
            val extra = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                .apply { init(extraStore) }.trustManagers.filterIsInstance<X509TrustManager>().first()
            val system = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                .apply { init(null as KeyStore?) }.trustManagers.filterIsInstance<X509TrustManager>().first()
            val both = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = system.checkClientTrusted(chain, authType)
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                    try {
                        system.checkServerTrusted(chain, authType)
                    } catch (e: CertificateException) {
                        extra.checkServerTrusted(chain, authType)
                    }
                }
                override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers + extra.acceptedIssuers
            }
            SSLContext.getInstance("TLS").apply { init(null, arrayOf(both), null) }.socketFactory
        } catch (e: Exception) {
            null
        }
    }
}
