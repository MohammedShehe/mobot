package com.example.mobot

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Android gives no "gender" for text-to-speech voices (they are called things like
 * "en-us-x-iom-local"), so MO measures it: each voice says a sentence, the pitch of the
 * recording is analysed, and the result is cached.
 */
object VoiceTools {
    private const val PREFS = "mo_native"
    private const val SENTENCE = "The quick brown fox jumps over the lazy dog, and then it goes home to sleep."
    private val main = Handler(Looper.getMainLooper())

    /** Installed voices only (voices that are listed but not downloaded silently fall back to the default voice). */
    fun list(ctx: Context, done: (List<Map<String, Any>>) -> Unit) {
        val app = ctx.applicationContext
        main.post {
            var tts: TextToSpeech? = null
            try {
                tts = TextToSpeech(app) { status ->
                    val out = ArrayList<Map<String, Any>>()
                    try {
                        if (status == TextToSpeech.SUCCESS) {
                            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            val voices: Set<Voice> = tts?.voices ?: emptySet()
                            for (v in voices) {
                                if (v.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) == true) continue
                                out.add(
                                    mapOf(
                                        "name" to v.name,
                                        "locale" to v.locale.toLanguageTag(),
                                        "quality" to v.quality,
                                        "network" to v.isNetworkConnectionRequired,
                                        "gender" to (prefs.getString("g:${v.name}", "") ?: "")
                                    )
                                )
                            }
                        }
                    } catch (_: Throwable) {}
                    try { tts?.shutdown() } catch (_: Throwable) {}
                    main.post { done(out) }
                }
            } catch (_: Throwable) {
                done(emptyList())
            }
        }
    }

    /** name -> "male" | "female" | "" (unknown). Results are cached on the device. */
    fun classify(ctx: Context, names: List<String>, done: (Map<String, String>) -> Unit) {
        val app = ctx.applicationContext
        Thread {
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val out = HashMap<String, String>()
            val todo = ArrayList<String>()
            for (n in names) {
                val c = prefs.getString("g:$n", null)
                if (c != null) out[n] = c else todo.add(n)
            }
            if (todo.isNotEmpty()) {
                var ttsRef: TextToSpeech? = null
                var ok = false
                val ready = CountDownLatch(1)
                main.post {
                    try {
                        ttsRef = TextToSpeech(app) { st -> ok = st == TextToSpeech.SUCCESS; ready.countDown() }
                    } catch (_: Throwable) { ready.countDown() }
                }
                ready.await(10, TimeUnit.SECONDS)
                val engine = ttsRef
                if (ok && engine != null) {
                    val all: Set<Voice> = engine.voices ?: emptySet()
                    for (n in todo) {
                        val v = all.firstOrNull { it.name == n }
                        if (v == null) { out[n] = ""; continue }
                        val g = try { analyse(engine, v, app) } catch (_: Throwable) { "" }
                        out[n] = g
                        if (g.isNotEmpty()) prefs.edit().putString("g:$n", g).apply()
                    }
                }
                main.post { try { engine?.shutdown() } catch (_: Throwable) {} }
            }
            main.post { done(out) }
        }.start()
    }

    private fun analyse(tts: TextToSpeech, v: Voice, ctx: Context): String {
        val f = File(ctx.cacheDir, "vt_${System.nanoTime()}.wav")
        try {
            tts.setVoice(v)
            tts.setPitch(1.0f)
            tts.setSpeechRate(1.0f)
            val latch = CountDownLatch(1)
            var good = false
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) { good = true; latch.countDown() }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) { latch.countDown() }
                override fun onError(utteranceId: String?, errorCode: Int) { latch.countDown() }
            })
            val r = tts.synthesizeToFile(SENTENCE, Bundle(), f, "vt")
            if (r != TextToSpeech.SUCCESS) return ""
            latch.await(20, TimeUnit.SECONDS)
            if (!good || !f.exists()) return ""
            return pitchToGender(f.readBytes())
        } finally {
            try { f.delete() } catch (_: Throwable) {}
        }
    }

    private fun le16(b: ByteArray, o: Int) = (b[o].toInt() and 0xff) or ((b[o + 1].toInt() and 0xff) shl 8)
    private fun le32(b: ByteArray, o: Int) = le16(b, o) or (le16(b, o + 2) shl 16)

    private fun pitchToGender(wav: ByteArray): String {
        if (wav.size < 64 || String(wav, 0, 4) != "RIFF") return ""
        val channels = maxOf(1, le16(wav, 22))
        val sr = le32(wav, 24)
        val bits = le16(wav, 34)
        if (bits != 16 || sr < 8000) return ""
        var pos = 12
        var start = -1
        var end = wav.size
        while (pos + 8 <= wav.size) {
            val id = String(wav, pos, 4)
            val sz = le32(wav, pos + 4)
            if (id == "data") {
                start = pos + 8
                if (sz > 0 && start + sz <= wav.size) end = start + sz
                break
            }
            if (sz < 0) break
            pos += 8 + sz
        }
        if (start < 0) return ""
        val frames = (end - start) / (2 * channels)
        val s = ShortArray(frames)
        for (i in 0 until frames) s[i] = le16(wav, start + i * 2 * channels).toShort()

        val frame = (sr * 0.05).toInt()
        val hop = (sr * 0.025).toInt()
        val minLag = sr / 300
        val maxLag = sr / 70
        val f0s = ArrayList<Double>()
        var at = (sr * 0.1).toInt()
        while (at + frame + maxLag + 1 < s.size) {
            var e = 0.0
            for (i in 0 until frame) { val x = s[at + i].toDouble(); e += x * x }
            if (Math.sqrt(e / frame) > 500) {
                val r = DoubleArray(maxLag + 2)
                var best = 0.0
                for (lag in minLag..maxLag) {
                    var sum = 0.0
                    var e2 = 0.0
                    for (i in 0 until frame) {
                        val a = s[at + i].toDouble()
                        val b = s[at + i + lag].toDouble()
                        sum += a * b
                        e2 += b * b
                    }
                    r[lag] = if (e > 0 && e2 > 0) sum / Math.sqrt(e * e2) else 0.0
                    if (r[lag] > best) best = r[lag]
                }
                if (best > 0.6) {
                    // Smallest lag that is a clear peak (avoids octave errors).
                    for (lag in (minLag + 1) until maxLag) {
                        if (r[lag] >= 0.85 * best && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1]) {
                            f0s.add(sr.toDouble() / lag)
                            break
                        }
                    }
                }
            }
            at += hop
        }
        if (f0s.size < 8) return ""
        f0s.sort()
        val median = f0s[f0s.size / 2]
        return if (median >= 158.0) "female" else "male"
    }
}
