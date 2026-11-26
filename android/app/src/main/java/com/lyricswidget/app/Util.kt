package com.lyricswidget.app

import android.content.Context
import android.graphics.Color
import android.util.TypedValue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Shared background thread pool. */
object Net {
    val pool: ExecutorService = Executors.newCachedThreadPool()
}

fun Context.dp(v: Number): Int =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

fun parseColorOr(s: String, def: Int): Int =
    try { Color.parseColor(s) } catch (e: Exception) { def }

fun Int.withAlpha(a: Float): Int =
    (this and 0x00FFFFFF) or ((a.coerceIn(0f, 1f) * 255f).toInt() shl 24)

fun luminance(c: Int): Double =
    (0.299 * Color.red(c) + 0.587 * Color.green(c) + 0.114 * Color.blue(c)) / 255.0

fun statusBarHeightPx(ctx: Context): Int {
    val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
    return if (id > 0) ctx.resources.getDimensionPixelSize(id) else ctx.dp(24)
}

/** Default distance from the top of the screen: just under the status bar. */
fun defaultTopDp(ctx: Context): Int =
    (statusBarHeightPx(ctx) / ctx.resources.displayMetrics.density).toInt() + 12

fun fmtTime(sec: Double): String {
    val s = sec.toInt().coerceAtLeast(0)
    return "%02d:%02d".format(s / 60, s % 60)
}
