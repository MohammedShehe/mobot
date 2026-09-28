package com.example.mobot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Always-on wake-word listener (foreground service, microphone type).
 *
 * - While the MO screen is visible it stays idle: the Flutter hands-free loop owns the mic.
 * - Otherwise (app in background, closed, or phone locked) it listens continuously. When it
 *   hears the wake word it stores what was said, wakes the screen and opens MO, which then
 *   listens and answers.
 */
class WakeService : Service() {
    companion object {
        private const val CH_LISTEN = "mo_listen"
        private const val CH_WAKE = "mo_wake_alert"
        private const val ID_LISTEN = 4201
        private const val ID_WAKE = 4202
        private const val PREFS = "mo_native"
        private const val PENDING_TTL_MS = 20_000L

        @Volatile var appVisible = false
        @Volatile private var instance: WakeService? = null
        @Volatile private var pendingText: String? = null
        @Volatile private var pendingAt = 0L

        fun start(ctx: Context, wake: String, locale: String) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("wake", wake).putString("locale", locale).putBoolean("on", true).apply()
            val i = Intent(ctx, WakeService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("on", false).apply()
            ctx.stopService(Intent(ctx, WakeService::class.java))
        }

        fun setVisible(v: Boolean) {
            appVisible = v
            val s = instance ?: return
            s.handler.post { s.onVisibilityChanged() }
        }

        /** Returns what was said after the wake word ("" = wake word only) once, or null. */
        fun consume(): String? {
            val t = pendingText ?: return null
            val fresh = System.currentTimeMillis() - pendingAt < PENDING_TTL_MS
            pendingText = null
            return if (fresh) t else null
        }
    }

    internal val handler = Handler(Looper.getMainLooper())
    private var rec: SpeechRecognizer? = null
    private var running = false
    private var fails = 0
    private var wake = "Yow MO"
    private var lang = "en-US"
    private val listenRunnable = Runnable { listenOnce() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        try {
            goForeground()
        } catch (t: Throwable) {
            // e.g. Android 14+ refuses to start a microphone service from the background.
            stopSelf()
            return START_NOT_STICKY
        }
        val p = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!p.getBoolean("on", false)) {
            stopSelf()
            return START_NOT_STICKY
        }
        wake = p.getString("wake", wake) ?: wake
        lang = p.getString("locale", lang) ?: lang
        running = true
        fails = 0
        restartListening(0)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        destroyRec()
        instance = null
        super.onDestroy()
    }

    // ---- notification ------------------------------------------------------

    private fun nm() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        nm().createNotificationChannel(
            NotificationChannel(CH_LISTEN, "MO wake word", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while MO waits for its wake word"
                setShowBadge(false)
            }
        )
        nm().createNotificationChannel(
            NotificationChannel(CH_WAKE, "MO wake-up", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Opens MO when you say the wake word"
            }
        )
    }

    private fun builder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)

    private fun openAppIntent(): Intent =
        Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            .putExtra("from_wake", true)

    private fun immutable() = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0

    private fun goForeground() {
        ensureChannels()
        val pi = PendingIntent.getActivity(this, 0, openAppIntent(), PendingIntent.FLAG_UPDATE_CURRENT or immutable())
        val n = builder(CH_LISTEN)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("MO is listening")
            .setContentText("Say \"" + (getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("wake", wake) ?: wake) + "\" to wake me up")
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(ID_LISTEN, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(ID_LISTEN, n)
        }
    }

    // ---- listening loop ----------------------------------------------------

    fun onVisibilityChanged() {
        if (!running) return
        if (appVisible) {
            handler.removeCallbacks(listenRunnable)
            destroyRec()
            try { nm().cancel(ID_WAKE) } catch (_: Throwable) {}
        } else {
            restartListening(800)
        }
    }

    private fun restartListening(delayMs: Long) {
        handler.removeCallbacks(listenRunnable)
        handler.postDelayed(listenRunnable, delayMs)
    }

    private fun destroyRec() {
        val r = rec ?: return
        rec = null
        try { r.cancel() } catch (_: Throwable) {}
        try { r.destroy() } catch (_: Throwable) {}
    }

    private fun listenOnce() {
        if (!running) return
        if (appVisible) { destroyRec(); return }
        if (checkCallingOrSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf(); return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) { restartListening(30_000); return }
        destroyRec()
        try {
            val r = SpeechRecognizer.createSpeechRecognizer(this)
            rec = r
            r.setRecognitionListener(Listener(r))
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            r.startListening(i)
        } catch (t: Throwable) {
            destroyRec()
            fails++
            restartListening(minOf(1000L * fails, 8000L))
        }
    }

    private inner class Listener(private val owner: SpeechRecognizer) : RecognitionListener {
        private fun current() = owner === rec
        override fun onReadyForSpeech(params: Bundle?) { if (current()) fails = 0 }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onPartialResults(partialResults: Bundle?) {}

        override fun onResults(results: Bundle?) {
            if (!current()) return
            val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (list != null) {
                for (t in list) {
                    val rest = WakeMatcher.match(t, wake)
                    if (rest != null) { trigger(rest); return }
                }
            }
            restartListening(250)
        }

        override fun onError(error: Int) {
            if (!current()) return
            when (error) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> stopSelf()
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> restartListening(200)
                else -> {
                    destroyRec()
                    fails++
                    restartListening(minOf(1000L * fails, 8000L))
                }
            }
        }
    }

    // ---- wake-up -----------------------------------------------------------

    private fun trigger(rest: String) {
        pendingText = rest
        pendingAt = System.currentTimeMillis()
        destroyRec() // release the microphone for the app
        wakeScreen()
        launchApp()
        // If the app could not open (no overlay permission), go back to listening.
        handler.postDelayed({ if (running && !appVisible) restartListening(0) }, 9_000)
    }

    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "mo:wake"
            )
            wl.acquire(10_000)
        } catch (_: Throwable) {}
    }

    private fun launchApp() {
        val i = openAppIntent()
        // Works directly when "Display over other apps" is allowed for MO.
        try { startActivity(i) } catch (_: Throwable) {}
        // Fallback for the lock screen / when Android blocks background launches.
        try {
            val pi = PendingIntent.getActivity(this, 1, i, PendingIntent.FLAG_UPDATE_CURRENT or immutable())
            val n = builder(CH_WAKE)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle("MO")
                .setContentText("I heard you. Tap to talk.")
                .setContentIntent(pi)
                .setFullScreenIntent(pi, true)
                .setAutoCancel(true)
                .build()
            nm().notify(ID_WAKE, n)
        } catch (_: Throwable) {}
    }
}
