package com.lyricswidget.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.widget.TextViewCompat
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/** Moves stable lyric rows through a clipped viewport instead of replacing their text mid-scroll. */
internal class LyricsWaveView(
    context: Context,
    private val ink: Int,
    textScale: Float,
    visibleLines: Int,
    alignLeft: Boolean,
    onSync: (Int) -> Unit
) : FrameLayout(context) {
    private val radius = visibleLines.coerceIn(1, 5) / 2
    private val centerHeight = context.dp(40f * textScale)
    private val sideHeight = context.dp(28f * textScale)
    private val topPad = context.dp(4)
    val viewportHeight = topPad + centerHeight + 2 * radius * sideHeight + context.dp(2)

    private class Row(val view: TextView, var index: Int? = null)

    private var lines: List<Line> = emptyList()
    private var target = -1
    private var focus = -1f
    private var status = ""
    private val easing = PathInterpolator(0.22f, 0.72f, 0.22f, 1f)
    private var motion: ValueAnimator? = null

    // A row at either edge may be partly visible during a transition.
    private val rows = List(2 * radius + 3) {
        val tv = TextView(context).apply {
            gravity = (if (alignLeft) Gravity.START else Gravity.CENTER_HORIZONTAL) or Gravity.CENTER_VERTICAL
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(ink)
            TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                this, 11, (20 * textScale).roundToInt().coerceAtLeast(14), 1, TypedValue.COMPLEX_UNIT_SP
            )
            visibility = View.INVISIBLE
            if (alignLeft) addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                v.pivotX = if (v.layoutDirection == View.LAYOUT_DIRECTION_RTL) v.width.toFloat() else 0f
            }
        }
        addView(tv, LayoutParams(LayoutParams.MATCH_PARENT, centerHeight, Gravity.TOP))
        Row(tv).also { row ->
            tv.setOnClickListener { row.index?.takeIf { it in lines.indices }?.let(onSync) }
        }
    }

    init {
        setPadding(context.dp(16), 0, context.dp(16), 0)
        clipChildren = true
        clipToPadding = true
    }

    fun render(newLines: List<Line>, index: Int, newStatus: String) {
        val next = if (index in newLines.indices) index else -1
        val sameTrack = lines === newLines
        if (sameTrack && target == next && (newLines.isNotEmpty() || status == newStatus) &&
            rows.any { it.index != null }) return

        val glide = sameTrack && LyricWaveMotion.canGlide(target, next, newLines.size) &&
            isAttachedToWindow && height > 0 && ValueAnimator.areAnimatorsEnabled()
        val retargeting = motion?.isRunning == true
        motion?.cancel()
        motion = null
        if (!sameTrack) rows.forEach { it.index = null }
        lines = newLines
        target = next
        status = newStatus

        if (glide && focus != next.toFloat()) {
            // Continue from the displayed position even if the next line arrives mid-glide.
            motion = ValueAnimator.ofFloat(focus, next.toFloat()).apply {
                duration = if (retargeting) LyricWaveMotion.RETARGET_MS else LyricWaveMotion.DURATION_MS
                interpolator = easing
                addUpdateListener {
                    focus = it.animatedValue as Float
                    drawRows()
                }
                start()
            }
        } else {
            focus = next.toFloat()
            drawRows()
        }
    }

    private fun drawRows() {
        val first = (floor(focus).toInt() - radius).coerceAtLeast(if (focus < 0f) -1 else 0)
        val end = (ceil(focus).toInt() + radius).coerceAtMost(lines.lastIndex)
        for (row in rows) {
            val i = row.index
            if (i == null || i < first || i > end) {
                row.index = null
                row.view.visibility = View.INVISIBLE
            }
        }
        for (i in first..end) {
            val row = rows.firstOrNull { it.index == i } ?: rows.first { it.index == null }.also { it.index = i }
            val tv = row.view
            val relative = i - focus
            val distance = abs(relative)
            val relativeScale = 0.75f + 0.25f * LyricWaveMotion.emphasis(distance)
            val alpha = LyricWaveMotion.opacity(distance, radius) * if (lines.isEmpty()) 0.7f else 1f
            val text = if (i == -1) {
                if (lines.isEmpty()) status.ifEmpty { "♪" } else "♪"
            } else lines[i].text.ifEmpty { "♪" }
            // New text is bound only when a row enters the viewport or the track changes.
            if (tv.text != text) tv.text = text
            tv.translationY = topPad + LyricWaveMotion.offset(relative, centerHeight.toFloat(), sideHeight.toFloat())
            tv.scaleX = relativeScale
            tv.scaleY = relativeScale
            tv.alpha = alpha
            tv.isClickable = i >= 0 && alpha >= 0.2f
            tv.visibility = if (alpha > 0f) View.VISIBLE else View.INVISIBLE
        }
    }

    override fun onDetachedFromWindow() {
        motion?.cancel()
        motion = null
        focus = target.toFloat()
        drawRows()
        super.onDetachedFromWindow()
    }
}
