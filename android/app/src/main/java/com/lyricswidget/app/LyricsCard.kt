package com.lyricswidget.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.widget.TextViewCompat
import kotlin.math.roundToInt

/** Everything the card needs to draw one frame. */
class CardState(
    val title: String,
    val artist: String,
    val art: Bitmap?,
    val lines: List<Line>,
    val idx: Int,
    val status: String,
    val playing: Boolean,
    val pos: Double,
    val length: Double
)

/** Thin seek bar, drawn by hand so it matches the card colours. */
class SeekBarView(ctx: Context) : View(ctx) {
    var fraction = 0f
        set(v) { field = v; invalidate() }
    var ink = Color.WHITE
    var onSeek: ((Float) -> Unit)? = null
    var dragging = false
        private set
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(c: Canvas) {
        val h = context.dp(4).toFloat()
        val cy = height / 2f
        paint.color = ink.withAlpha(0.25f)
        c.drawRoundRect(0f, cy - h / 2, width.toFloat(), cy + h / 2, h / 2, h / 2, paint)
        val x = width * fraction.coerceIn(0f, 1f)
        paint.color = ink
        c.drawRoundRect(0f, cy - h / 2, x, cy + h / 2, h / 2, h / 2, paint)
        c.drawCircle(x, cy, context.dp(6).toFloat(), paint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (onSeek == null || width == 0) return false
        val f = (e.x / width).coerceIn(0f, 1f)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragging = true
                parent?.requestDisallowInterceptTouchEvent(true)
                fraction = f
            }
            MotionEvent.ACTION_MOVE -> if (dragging) fraction = f
            MotionEvent.ACTION_UP -> {
                if (dragging) onSeek?.invoke(f)
                dragging = false
            }
            MotionEvent.ACTION_CANCEL -> dragging = false
        }
        return true
    }
}

/**
 * The lyrics card: album art, title, a few lyric lines, optional progress and buttons.
 * Used both in the floating overlay and in the settings preview. Looks are read from [Prefs].
 */
class LyricsCard(ctx: Context) : LinearLayout(ctx) {
    var onPicker: (() -> Unit)? = null
    var onReload: (() -> Unit)? = null
    var onClose: (() -> Unit)? = null
    var onSync: ((Int) -> Unit)? = null
    var onPrev: (() -> Unit)? = null
    var onToggle: (() -> Unit)? = null
    var onNext: (() -> Unit)? = null
    var onSeek: ((Float) -> Unit)? = null
    var onDragStart: (() -> Unit)? = null
    var onDrag: ((Float, Float) -> Unit)? = null
    var onDragEnd: (() -> Unit)? = null

    private var last: CardState? = null
    private var ink = Color.WHITE
    private var bgDrawable = GradientDrawable()
    private var slots: List<TextView> = emptyList()
    private var lyricsBox: LinearLayout? = null
    private var artView: ImageView? = null
    private var titleView: TextView? = null
    private var artistView: TextView? = null
    private var seek: SeekBarView? = null
    private var timeLeft: TextView? = null
    private var timeRight: TextView? = null
    private var playBtn: ImageView? = null

    private var artShown: Bitmap? = null
    private var artDirty = true
    private var bgArt: Bitmap? = null
    private var bgDirty = true
    private var lastIdx = Int.MIN_VALUE
    private var downX = 0f
    private val seekHandler: (Float) -> Unit = { f -> onSeek?.invoke(f) }
    private var downY = 0f
    private var dragCandidate = false
    private var movingCard = false
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var lastPlaying: Boolean? = null

    private fun d(v: Number): Int = context.dp(v)

    init {
        rebuild()
    }

    // ---- colours ----
    private fun inkColor(): Int {
        if (Prefs.line.isNotEmpty()) return parseColorOr(Prefs.line, Color.WHITE)
        if (Prefs.bg == "art") return Color.WHITE
        val bg = parseColorOr(Prefs.bg, Color.BLACK)
        return if (luminance(bg) > 0.6) 0xFF1B1410.toInt() else Color.WHITE
    }

    private fun bgBase(art: Bitmap?): Int {
        if (Prefs.bg != "art") return parseColorOr(Prefs.bg, Color.BLACK)
        if (art == null) return 0xFF1B1410.toInt()
        return try {
            val px = Bitmap.createScaledBitmap(art, 1, 1, true).getPixel(0, 0)
            val hsv = FloatArray(3)
            Color.colorToHSV(px, hsv)
            hsv[1] = hsv[1].coerceAtMost(0.7f)
            hsv[2] = (hsv[2] * 0.4f).coerceIn(0.08f, 0.3f)
            Color.HSVToColor(hsv)
        } catch (e: Exception) {
            0xFF1B1410.toInt()
        }
    }

    // ---- layout ----
    private fun iconButton(res: Int, size: Int, pad: Int, onClick: () -> Unit): ImageView =
        ImageView(context).apply {
            setImageDrawable(ContextCompat.getDrawable(context, res))
            setColorFilter(ink.withAlpha(0.75f))
            setPadding(pad, pad, pad, pad)
            background = RippleDrawable(ColorStateList.valueOf(ink.withAlpha(0.2f)), null, null)
            layoutParams = LinearLayout.LayoutParams(size, size)
            setOnClickListener { onClick() }
        }

    fun rebuild() {
        lyricsBox?.animate()?.cancel()
        removeAllViews()
        lastPlaying = null
        orientation = VERTICAL
        val scale = Prefs.textScale / 100f
        ink = inkColor()

        bgDrawable = GradientDrawable().apply { cornerRadius = d(Prefs.radius).toFloat() }
        background = bgDrawable
        clipToOutline = true
        bgDirty = true
        artDirty = true
        lastIdx = Int.MIN_VALUE

        // Drag zone: grip bar + header. Dragging anywhere here moves the card.
        val zone = LinearLayout(context).apply { orientation = VERTICAL }
        val gripWrap = FrameLayout(context)
        val grip = View(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = 100f
                setColor(ink.withAlpha(0.3f))
            }
        }
        gripWrap.addView(
            grip,
            FrameLayout.LayoutParams(d(36), d(4), Gravity.CENTER).apply {
            }
        )
        zone.addView(gripWrap, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, d(28)))

        val header = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(d(12), 0, d(6), 0)
        }
        artView = null
        titleView = null
        artistView = null
        if (Prefs.showArt) {
            val iv = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                outlineProvider = object : ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, d(10).toFloat())
                    }
                }
                clipToOutline = true
                background = GradientDrawable().apply { setColor(ink.withAlpha(0.12f)) }
            }
            header.addView(iv, LinearLayout.LayoutParams(d(40), d(40)).apply { marginEnd = d(10) })
            artView = iv
        }
        val texts = LinearLayout(context).apply { orientation = VERTICAL }
        if (Prefs.showTitle) {
            val t = TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }
            val a = TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(ink.withAlpha(0.65f))
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }
            texts.addView(t)
            texts.addView(a)
            titleView = t
            artistView = a
        }
        header.addView(texts, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(iconButton(R.drawable.ic_list, d(34), d(7)) { onPicker?.invoke() })
        header.addView(iconButton(R.drawable.ic_refresh, d(34), d(7)) { onReload?.invoke() })
        header.addView(iconButton(R.drawable.ic_close, d(34), d(8)) { onClose?.invoke() })
        zone.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        addView(zone, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // Lyric lines
        var n = Prefs.visibleLines.coerceIn(1, 5)
        if (n % 2 == 0) n += 1
        val center = n / 2
        val box = LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(d(16), d(4), d(16), d(2))
        }
        val list = ArrayList<TextView>()
        for (k in 0 until n) {
            val isCenter = k == center
            val tv = TextView(context).apply {
                gravity = (if (Prefs.alignLeft) Gravity.START else Gravity.CENTER_HORIZONTAL) or Gravity.CENTER_VERTICAL
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                if (isCenter) {
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(ink)
                    TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                        this, 11, (20 * scale).roundToInt().coerceAtLeast(14), 1, TypedValue.COMPLEX_UNIT_SP
                    )
                } else {
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f * scale)
                    setTextColor(ink.withAlpha(if (kotlin.math.abs(k - center) == 1) 0.6f else 0.3f))
                }
                setOnClickListener {
                    val st = last
                    if (st != null) {
                        val i = st.idx + (k - center)
                        if (st.lines.isNotEmpty() && i in st.lines.indices) onSync?.invoke(i)
                    }
                }
            }
            box.addView(tv, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, d((if (isCenter) 40f else 28f) * scale)))
            list.add(tv)
        }
        slots = list
        lyricsBox = box
        addView(box, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // Progress
        seek = null
        timeLeft = null
        timeRight = null
        if (Prefs.showProgress) {
            val row = LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(d(16), d(2), d(16), 0)
            }
            val tl = TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setTextColor(ink.withAlpha(0.65f))
            }
            val tr = TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setTextColor(ink.withAlpha(0.65f))
            }
            val sb = SeekBarView(context).apply {
                ink = this@LyricsCard.ink
                onSeek = { f -> this@LyricsCard.onSeek?.invoke(f) }
            }
            row.addView(tl)
            row.addView(sb, LinearLayout.LayoutParams(0, d(20), 1f).apply { marginStart = d(8); marginEnd = d(8) })
            row.addView(tr)
            addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            seek = sb
            timeLeft = tl
            timeRight = tr
        }

        // Playback buttons
        playBtn = null
        if (Prefs.showControls) {
            val row = LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER
                setPadding(0, d(2), 0, 0)
            }
            val gap = d(18)
            row.addView(iconButton(R.drawable.ic_prev, d(46), d(10)) { onPrev?.invoke() },
                LinearLayout.LayoutParams(d(46), d(46)).apply { marginEnd = gap })
            val pb = iconButton(R.drawable.ic_pause, d(52), d(12)) { onToggle?.invoke() }
            row.addView(pb, LinearLayout.LayoutParams(d(52), d(52)))
            row.addView(iconButton(R.drawable.ic_next, d(46), d(10)) { onNext?.invoke() },
                LinearLayout.LayoutParams(d(46), d(46)).apply { marginStart = gap })
            addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            playBtn = pb
        }

        addView(View(context), LinearLayout.LayoutParams(1, d(8)))
        last?.let { render(it) }
    }

    // Buttons and the seek slider keep their own gestures; lyric taps still sync.
    private fun onControl(v: View, x: Float, y: Float): Boolean {
        if (v.visibility != View.VISIBLE) return false
        if (v is SeekBarView || (v is ImageView && v.isClickable)) {
            val xy = IntArray(2)
            v.getLocationOnScreen(xy)
            return x >= xy[0] && x < xy[0] + v.width && y >= xy[1] && y < xy[1] + v.height
        }
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) if (onControl(v.getChildAt(i), x, y)) return true
        }
        return false
    }

    private fun startGesture(e: MotionEvent) {
        movingCard = false
        downX = e.rawX
        downY = e.rawY
        dragCandidate = onDrag != null && !Prefs.lockPos && !onControl(this, downX, downY)
    }

    private fun moveGesture(e: MotionEvent): Boolean {
        if (!dragCandidate || e.pointerCount != 1) return movingCard
        val dx = e.rawX - downX
        val dy = e.rawY - downY
        if (!movingCard && dx * dx + dy * dy > touchSlop.toFloat() * touchSlop) {
            movingCard = true
            onDragStart?.invoke()
        }
        if (movingCard) onDrag?.invoke(dx, dy)
        return movingCard
    }

    private fun endGesture() {
        if (movingCard) onDragEnd?.invoke()
        dragCandidate = false
        movingCard = false
    }

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> startGesture(e)
            MotionEvent.ACTION_MOVE -> return moveGesture(e)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_DOWN -> endGesture()
        }
        return false
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (onDrag == null) return super.onTouchEvent(e) // settings preview
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                startGesture(e)
                return dragCandidate
            }
            MotionEvent.ACTION_MOVE -> moveGesture(e)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_DOWN -> endGesture()
        }
        return true
    }

    // ---- drawing a frame ----
    fun render(s: CardState) {
        val previous = last
        last = s

        if (bgDirty || s.art !== bgArt) {
            bgDirty = false
            bgArt = s.art
            bgDrawable.setColor(bgBase(s.art).withAlpha(Prefs.bgOpacity / 100f))
        }

        val title = s.title.ifEmpty { "Nothing playing" }
        titleView?.let { if (it.text != title) it.text = title }
        artistView?.let { if (it.text != s.artist) it.text = s.artist }

        val iv = artView
        if (iv != null && (artDirty || s.art !== artShown)) {
            artDirty = false
            artShown = s.art
            if (s.art != null) {
                iv.setPadding(0, 0, 0, 0)
                iv.clearColorFilter()
                iv.setImageBitmap(s.art)
            } else {
                iv.setPadding(d(10), d(10), d(10), d(10))
                iv.setImageDrawable(ContextCompat.getDrawable(context, R.drawable.ic_note))
                iv.setColorFilter(ink.withAlpha(0.6f))
            }
        }

        val n = slots.size
        val c = n / 2
        for (k in 0 until n) {
            val i = s.idx + (k - c)
            val text = when {
                s.lines.isEmpty() -> if (k == c) s.status.ifEmpty { "♪" } else ""
                k == c -> if (s.idx in s.lines.indices) s.lines[s.idx].text.ifEmpty { "♪" } else "♪"
                i in s.lines.indices -> s.lines[i].text.ifEmpty { "♪" }
                else -> ""
            }
            val tv = slots[k]
            if (tv.text.toString() != text) tv.text = text
            if (k == c) tv.setTextColor(ink.withAlpha(if (s.lines.isEmpty()) 0.7f else 1f))
        }
        if (s.idx != lastIdx || previous?.lines !== s.lines) {
            val step = s.idx - lastIdx
            lyricsBox?.let { box ->
                box.animate().cancel()
                box.translationY = 0f
                box.alpha = 1f
                if (previous?.lines === s.lines && lastIdx in s.lines.indices &&
                    s.idx in s.lines.indices && (step == 1 || step == -1)) {
                    box.translationY = d(14).toFloat() * step
                    box.alpha = 0.65f
                    box.animate().translationY(0f).alpha(1f).setDuration(250)
                        .setInterpolator(DecelerateInterpolator()).start()
                }
            }
            lastIdx = s.idx
        }

        val sb = seek
        if (sb != null) {
            if (!sb.dragging) sb.fraction = if (s.length > 0) (s.pos / s.length).toFloat() else 0f
            val currentTime = fmtTime(s.pos)
            val totalTime = if (s.length > 0) fmtTime(s.length) else "--:--"
            timeLeft?.let { if (it.text != currentTime) it.text = currentTime }
            timeRight?.let { if (it.text != totalTime) it.text = totalTime }
            sb.onSeek = if (s.length > 0) seekHandler else null
        }
        if (lastPlaying != s.playing) {
            lastPlaying = s.playing
            playBtn?.setImageDrawable(
                ContextCompat.getDrawable(context, if (s.playing) R.drawable.ic_pause else R.drawable.ic_play)
            )
        }
    }
}
