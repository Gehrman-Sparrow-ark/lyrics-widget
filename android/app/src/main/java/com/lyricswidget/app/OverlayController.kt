package com.lyricswidget.app

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.WindowManager
import kotlin.math.roundToInt

/** Shows the lyrics card as a floating window pinned near the top of the screen. */
class OverlayController(private val ctx: Context) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val themed: Context = ContextThemeWrapper(ctx, R.style.Theme_Lyrics)
    private val main = Handler(Looper.getMainLooper())
    private var card: LyricsCard? = null
    private var lp: WindowManager.LayoutParams? = null
    private var running = false
    private var pausedSince = 0L

    private var dragOx = 0
    private var dragOy = 0

    private val ticker = object : Runnable {
        override fun run() {
            if (!running) return
            val nextLine = LyricsStore.tick()
            evaluate(nextLine || Prefs.showProgress)
            main.postDelayed(this, if (card != null && LyricsStore.playing) 50 else 200)
        }
    }
    private val storeListener: () -> Unit = { evaluate() }
    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key -> onPref(key) }

    fun start() {
        if (running) return
        running = true
        Prefs.sp.registerOnSharedPreferenceChangeListener(prefListener)
        LyricsStore.addListener(storeListener)
        main.post(ticker)
    }

    fun stop() {
        running = false
        main.removeCallbacksAndMessages(null)
        Prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        LyricsStore.removeListener(storeListener)
        detach()
    }

    private fun canDraw(): Boolean = Settings.canDrawOverlays(ctx)

    fun evaluate(render: Boolean = true) {
        if (!running) return
        val s = LyricsStore
        var show = Prefs.enabled && canDraw() && s.hasPlayer && !s.appVisible && s.dismissedKey != s.key()
        if (show && Prefs.hideNoLyrics && s.lines.isEmpty() && !s.busy) show = false
        if (show && Prefs.hideWhenPaused) {
            if (s.playing) {
                pausedSince = 0L
            } else {
                if (pausedSince == 0L) pausedSince = SystemClock.elapsedRealtime()
                if (SystemClock.elapsedRealtime() - pausedSince > 8000) show = false
            }
        } else {
            pausedSince = 0L
        }
        if (show) {
            val wasAttached = card != null
            attach()
            if (render || !wasAttached) renderCard()
        } else {
            detach()
        }
    }

    private fun renderCard() {
        val c = card ?: return
        val s = LyricsStore
        c.render(CardState(s.title, s.artist, s.art, s.lines, s.idx, s.status, s.playing, s.curPos(), s.length))
    }

    private fun screenW(): Int = ctx.resources.displayMetrics.widthPixels
    private fun screenH(): Int = ctx.resources.displayMetrics.heightPixels

    private fun maxX(width: Int): Int = ((screenW() - width) / 2).coerceAtLeast(0)

    private fun place(p: WindowManager.LayoutParams) {
        p.width = (screenW() * Prefs.widthPct / 100f).roundToInt()
        p.x = ctx.dp(Prefs.posX).coerceIn(-maxX(p.width), maxX(p.width))
        p.y = if (Prefs.posY >= 0) ctx.dp(Prefs.posY) else statusBarHeightPx(ctx) + ctx.dp(12)
    }

    private fun attach() {
        if (card != null) return
        val c = LyricsCard(themed)
        c.onPicker = {
            val i = Intent(ctx, PickerActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try { ctx.startActivity(i) } catch (e: Exception) { }
        }
        c.onReload = { LyricsStore.reload() }
        c.onClose = { LyricsStore.dismiss() }
        c.onSync = { i -> LyricsStore.syncTo(i) }
        c.onPrev = { LyricsStore.prev() }
        c.onNext = { LyricsStore.next() }
        c.onToggle = { LyricsStore.toggle() }
        c.onSeek = { f -> if (LyricsStore.length > 0) LyricsStore.seekTo(LyricsStore.length * f) }
        c.onDragStart = {
            dragOx = lp?.x ?: 0
            dragOy = lp?.y ?: 0
        }
        c.onDrag = { dx, dy ->
            val p = lp
            val view = card
            if (p != null && view != null) {
                p.x = (dragOx + dx).roundToInt().coerceIn(-maxX(p.width), maxX(p.width))
                p.y = (dragOy + dy).roundToInt().coerceIn(0, (screenH() - view.height).coerceAtLeast(0))
                try { wm.updateViewLayout(view, p) } catch (e: Exception) { }
            }
        }
        c.onDragEnd = {
            val p = lp
            if (p != null) {
                val density = ctx.resources.displayMetrics.density
                Prefs.sp.edit()
                    .putInt("posX", (p.x / density).roundToInt())
                    .putInt("posY", (p.y / density).roundToInt())
                    .apply()
            }
        }

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        p.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        place(p)
        try {
            wm.addView(c, p)
            card = c
            lp = p
        } catch (e: Exception) {
            card = null
            lp = null
        }
    }

    private fun detach() {
        val c = card ?: return
        try { wm.removeView(c) } catch (e: Exception) { }
        card = null
        lp = null
    }

    /** Re-applies width and position (after rotation or a settings change). */
    fun relayout() {
        val c = card ?: return
        val p = lp ?: return
        place(p)
        try { wm.updateViewLayout(c, p) } catch (e: Exception) { }
    }

    private fun onPref(key: String?) {
        if (!running) return
        when (key) {
            "posX", "posY", "widthPct" -> relayout()
            else -> {
                card?.rebuild()
                relayout()
                evaluate()
            }
        }
    }
}
