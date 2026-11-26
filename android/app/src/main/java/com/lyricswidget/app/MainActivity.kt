package com.lyricswidget.app

import android.Manifest
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.button.MaterialButtonToggleGroup
import com.google.android.material.color.MaterialColors
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.android.material.slider.Slider
import kotlin.math.roundToInt

/** The settings screen: every customization is here, with a live preview on top. */
class MainActivity : AppCompatActivity() {
    private lateinit var scroll: ScrollView
    private lateinit var content: LinearLayout
    private lateinit var previewHost: FrameLayout
    private lateinit var preview: LyricsCard
    private var nowText: TextView? = null
    private var offsetText: TextView? = null

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> refreshPreview() }
    private val storeListener: () -> Unit = { updateNow() }
    private val importLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) importLrc(uri)
    }

    private val lockNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
            Prefs.showLockLyrics = allowed
            buildContent()
        }

    private fun setLockLyrics(enabled: Boolean) {
        if (!enabled) {
            Prefs.showLockLyrics = false
        } else if (NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            Prefs.showLockLyrics = true
        } else if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            lockNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        }
        scroll.post { buildContent() }
    }

    private val bgSwatches = listOf("#000000", "#0B0B10", "#1B1410", "#16213E", "#1F2A1F", "#2B1B2E", "#3B1F1F", "#2B2B2B", "#FFFFFF")
    private val lineSwatches = listOf("", "#FFFFFF", "#E9D5BF", "#FFD166", "#FF8FA3", "#B39DDB", "#80DEEA", "#A5D6A7", "#FFAB91", "#1B1410")

    private fun themeColor(attr: Int): Int = MaterialColors.getColor(this, attr, 0xFF888888.toInt())
    private val cOnSurface get() = themeColor(com.google.android.material.R.attr.colorOnSurface)
    private val cPrimary get() = themeColor(androidx.appcompat.R.attr.colorPrimary)
    private val cSurface get() = themeColor(com.google.android.material.R.attr.colorSurface)
    private val cCard get() = themeColor(com.google.android.material.R.attr.colorSurfaceContainer)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Prefs.init(this)
        LyricsStore.init(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(cSurface)
        }
        previewHost = FrameLayout(this).apply {
            setPadding(0, dp(16), 0, dp(16))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(0xFF2A3350.toInt(), 0xFF8C8196.toInt(), 0xFFC9B79C.toInt())
            )
        }
        preview = LyricsCard(this)
        previewHost.addView(preview, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
        root.addView(previewHost, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(32))
        }
        scroll = ScrollView(this).apply { addView(content) }
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)

        buildContent()
        refreshPreview()
    }

    override fun onResume() {
        super.onResume()
        LyricsStore.appVisible = true
        Prefs.sp.registerOnSharedPreferenceChangeListener(prefListener)
        LyricsStore.addListener(storeListener)
        LyricsService.reconnect(this)
        LyricsService.instance?.refresh()
        val y = scroll.scrollY
        buildContent()
        scroll.post { scroll.scrollTo(0, y) }
        refreshPreview()
    }

    override fun onPause() {
        LyricsStore.appVisible = false
        Prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        LyricsStore.removeListener(storeListener)
        LyricsService.instance?.refresh(rescan = true)
        super.onPause()
    }

    private fun showWidgetNow() {
        val message = when {
            !notifAccess() -> "Allow Notification access in Setup first."
            !overlayOk() -> "Allow Display over other apps in Setup first."
            LyricsService.instance?.showWidgetNow() != true -> {
                Prefs.enabled = true
                LyricsService.reconnect(this)
                "Connecting to Android media. Try Show widget now again in a moment."
            }
            else -> {
                if (!moveTaskToBack(true)) finish()
                return
            }
        }
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    // ---- preview ----
    private fun demo() = CardState(
        "Song title", "Artist name", null,
        listOf(
            Line(0.0, "Your lyrics will look like this"),
            Line(5.0, "Lines before the one being sung"),
            Line(10.0, "The line being sung stands out"),
            Line(15.0, "Tap a line in the widget to fix timing"),
            Line(20.0, "Drag the top bar to move it"),
            Line(25.0, "Next lines wait below")
        ),
        2, "", true, 95.0, 230.0
    )

    private fun refreshPreview() {
        preview.rebuild()
        val w = (resources.displayMetrics.widthPixels * Prefs.widthPct / 100f).roundToInt()
        val p = preview.layoutParams as FrameLayout.LayoutParams
        if (p.width != w) {
            p.width = w
            preview.layoutParams = p
        }
        preview.render(demo())
    }

    // ---- small view helpers ----
    private fun label(text: String, size: Float = 14f, alpha: Float = 1f, bold: Boolean = false) =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(cOnSurface.withAlpha(alpha))
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

    private fun section(title: String, build: LinearLayout.() -> Unit) {
        content.addView(label(title, 13f, 0.7f, true).apply { setPadding(dp(4), dp(18), 0, dp(6)); setTextColor(cPrimary) })
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply { cornerRadius = dp(20).toFloat(); setColor(cCard) }
        }
        card.build()
        content.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun LinearLayout.gap(h: Int = 8) = addView(View(context), LinearLayout.LayoutParams(1, dp(h)))

    private fun LinearLayout.switchRow(title: String, sub: String?, get: () -> Boolean, set: (Boolean) -> Unit) {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val col = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        col.addView(label(title))
        if (sub != null) col.addView(label(sub, 12f, 0.6f))
        row.addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(MaterialSwitch(context).apply {
            isChecked = get()
            setOnCheckedChangeListener { _, v -> set(v) }
        })
        addView(row)
        gap()
    }

    private fun LinearLayout.sliderRow(title: String, from: Int, to: Int, initial: Int, unit: String, step: Int = 1, onChange: (Int) -> Unit) {
        val snapped = (from + ((initial.coerceIn(from, to) - from).toFloat() / step).roundToInt() * step).coerceIn(from, to)
        val head = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        val valueView = label("$snapped$unit", 13f, 0.7f)
        head.addView(label(title), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(valueView)
        addView(head)
        addView(Slider(context).apply {
            valueFrom = from.toFloat()
            valueTo = to.toFloat()
            stepSize = step.toFloat()
            this.value = snapped.toFloat()
            addOnChangeListener { _, v, fromUser ->
                if (fromUser) {
                    valueView.text = "${v.toInt()}$unit"
                    onChange(v.toInt())
                }
            }
        })
    }

    private fun LinearLayout.segmented(title: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
        addView(label(title))
        val group = MaterialButtonToggleGroup(context).apply { isSingleSelection = true; isSelectionRequired = true }
        val ids = ArrayList<Int>()
        for (o in options) {
            val b = MaterialButton(context, null, com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
                text = o
                id = View.generateViewId()
            }
            ids.add(b.id)
            group.addView(b)
        }
        group.check(ids[selected.coerceIn(0, ids.size - 1)])
        group.addOnButtonCheckedListener { _, id, checked -> if (checked) onSelect(ids.indexOf(id)) }
        addView(group)
        gap()
    }

    private fun LinearLayout.swatches(title: String, values: List<String>, current: String, glyphs: Map<String, String>, onPick: (String) -> Unit) {
        addView(label(title))
        val strip = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(6), 0, dp(6)) }
        val all = values + "custom"
        for (v in all) {
            val isCustom = v == "custom"
            val selected = !isCustom && v == current || isCustom && current !in values
            val fill = when {
                isCustom -> if (current !in values && current.startsWith("#")) parseColorOr(current, Color.GRAY) else Color.TRANSPARENT
                v == "" -> cPrimary
                else -> parseColorOr(v, Color.GRAY)
            }
            val dot = TextView(context).apply {
                gravity = Gravity.CENTER
                text = if (isCustom) "#" else glyphs[v] ?: ""
                textSize = 14f
                setTextColor(if (luminance(fill) > 0.6 && fill != Color.TRANSPARENT) Color.BLACK else Color.WHITE)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(fill)
                    setStroke(dp(if (selected) 3 else 1), if (selected) cPrimary else cOnSurface.withAlpha(0.35f))
                }
                setOnClickListener { if (isCustom) askHex(onPick) else onPick(v) }
            }
            strip.addView(dot, LinearLayout.LayoutParams(dp(36), dp(36)).apply { marginEnd = dp(10) })
        }
        addView(HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false; addView(strip) })
        gap()
    }

    private fun askHex(onPick: (String) -> Unit) {
        val et = EditText(this).apply {
            hint = "#RRGGBB"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            setSingleLine()
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("Custom colour")
            .setView(FrameLayout(this).apply { setPadding(dp(24), dp(8), dp(24), 0); addView(et) })
            .setPositiveButton("Use") { _, _ ->
                var t = et.text.toString().trim()
                if (!t.startsWith("#")) t = "#$t"
                try {
                    Color.parseColor(t)
                    onPick(t.uppercase())
                    buildContent()
                } catch (e: Exception) {
                    Toast.makeText(this, "Not a valid colour", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun LinearLayout.buttons(vararg items: Pair<String, () -> Unit>) {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        for ((t, a) in items) {
            row.addView(
                MaterialButton(context, null, com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
                    text = t
                    isAllCaps = false
                    setOnClickListener { a() }
                },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(6) }
            )
        }
        addView(row)
    }

    // ---- permissions ----
    private fun notifAccess() = NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
    private fun overlayOk() = Settings.canDrawOverlays(this)

    private fun LinearLayout.setupRow(title: String, sub: String, ok: Boolean, action: () -> Unit) {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val col = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        col.addView(label(title))
        col.addView(label(sub, 12f, 0.6f))
        row.addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (ok) {
            row.addView(label("✓ On", 13f, 0.8f, true).apply { setTextColor(cPrimary) })
        } else {
            row.addView(MaterialButton(context).apply { text = "Allow"; setOnClickListener { action() } })
        }
        addView(row)
        gap()
    }

    // ---- lyrics actions ----
    private fun updateNow() {
        val s = LyricsStore
        nowText?.text = if (s.hasPlayer) "${s.title}${if (s.artist.isNotEmpty()) " - " + s.artist else ""}\n" +
            (if (s.lines.isNotEmpty()) "Lyrics: ${s.srcLabel}" else s.status.ifEmpty { "No lyrics yet" })
        else "Nothing playing. Start a song in any music app."
        offsetText?.text = "Timing: ${if (s.offset > 0) "+" else ""}${"%.1f".format(s.offset)}s"
    }

    private fun importLrc(uri: Uri) {
        val text = try {
            contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        } catch (e: Exception) { null }
        val ok = text != null && LyricsStore.importLrc(text.removePrefix("\uFEFF"))
        Toast.makeText(this, if (ok) "Lyrics imported" else "That file has no timed lyrics (or nothing is playing)", Toast.LENGTH_LONG).show()
    }

    // ---- the screen ----
    private fun buildContent() {
        content.removeAllViews()
        val dm = resources.displayMetrics
        val screenDp = (dm.heightPixels / dm.density).toInt()

        section("Setup") {
            setupRow("Notification access", "Lets the app see the song and position", notifAccess()) {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
            setupRow("Display over other apps", "Needed to float the card on top", overlayOk()) {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            }
            buttons(
                "Battery settings" to { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) },
                "App info" to { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))) }
            )
            gap()
            addView(label("If Android blocks notification access: App info, three-dot menu, Allow restricted settings. Set battery to Unrestricted so the card keeps running.", 12f, 0.6f))
        }

        section("Widget") {
            switchRow("Show lyrics widget", "Also available as a Quick Settings tile", { Prefs.enabled }) {
                Prefs.enabled = it
                if (it) LyricsStore.undismiss()
            }
            buttons("Show widget now" to { showWidgetNow() })
            gap()
            switchRow("Lyrics on the lock screen", "Shows your song and current line in a notification others can see.",
                { Prefs.showLockLyrics }, ::setLockLyrics)
            switchRow("Hide when paused", "Hides 8 seconds after you pause", { Prefs.hideWhenPaused }) { Prefs.hideWhenPaused = it }
            switchRow("Hide when no lyrics found", null, { Prefs.hideNoLyrics }) { Prefs.hideNoLyrics = it }
        }

        section("Look") {
            addView(label("Presets"))
            gap(4)
            buttons(
                "Lyrics only" to { Prefs.applyPreset("lyrics"); buildContent() },
                "Default" to { Prefs.applyPreset("default"); buildContent() },
                "Player" to { Prefs.applyPreset("player"); buildContent() }
            )
            gap(12)
            swatches("Background", bgSwatches + "art", Prefs.bg, mapOf("art" to "♪")) { Prefs.bg = it; buildContent() }
            swatches("Lyrics colour", lineSwatches, Prefs.line, mapOf("" to "A")) { Prefs.line = it; buildContent() }
            sliderRow("Transparency", 0, 80, 100 - Prefs.bgOpacity, "%") { Prefs.bgOpacity = 100 - it }
            sliderRow("Text size", 70, 140, Prefs.textScale, "%", 5) { Prefs.textScale = it }
            sliderRow("Corner roundness", 0, 40, Prefs.radius, "dp") { Prefs.radius = it }
            sliderRow("Width", 60, 100, Prefs.widthPct, "%") { Prefs.widthPct = it }
            gap()
            segmented("Lyric lines shown", listOf("1", "3", "5"), when (Prefs.visibleLines) { 1 -> 0; 5 -> 2; else -> 1 }) {
                Prefs.visibleLines = intArrayOf(1, 3, 5)[it]
            }
            segmented("Alignment", listOf("Centre", "Left"), if (Prefs.alignLeft) 1 else 0) { Prefs.alignLeft = it == 1 }
        }

        section("Card contents") {
            switchRow("Album art", null, { Prefs.showArt }) { Prefs.showArt = it }
            switchRow("Song title and artist", null, { Prefs.showTitle }) { Prefs.showTitle = it }
            switchRow("Progress bar", "Drag it to seek", { Prefs.showProgress }) { Prefs.showProgress = it }
            switchRow("Previous / play / next buttons", null, { Prefs.showControls }) { Prefs.showControls = it }
        }

        section("Position") {
            addView(label("Drag the top bar of the widget to move it, or set it here.", 12f, 0.6f))
            gap()
            switchRow("Lock position", "Stops accidental dragging", { Prefs.lockPos }) { Prefs.lockPos = it }
            sliderRow("Distance from top", 0, (screenDp - 120).coerceAtLeast(100), if (Prefs.posY >= 0) Prefs.posY else defaultTopDp(this@MainActivity), "dp") { Prefs.posY = it }
            sliderRow("Left / right", -200, 200, Prefs.posX, "dp") { Prefs.posX = it }
            gap()
            buttons("Reset position" to { Prefs.posY = -1; Prefs.posX = 0; buildContent() })
        }

        section("This song") {
            nowText = label("", 13f, 0.85f)
            offsetText = label("", 13f, 0.7f)
            addView(nowText)
            gap(4)
            addView(offsetText)
            gap()
            buttons(
                "Choose lyrics" to { startActivity(Intent(this@MainActivity, PickerActivity::class.java)) },
                "Reload" to { LyricsStore.reload() }
            )
            gap(4)
            buttons(
                "Earlier 0.5s" to { LyricsStore.nudge(0.5) },
                "Later 0.5s" to { LyricsStore.nudge(-0.5) }
            )
            gap(4)
            buttons("Import .lrc file" to { importLauncher.launch(arrayOf("*/*")) })
            gap()
            addView(label("Tip: tap the line being sung in the widget to fix the timing. It is remembered for this song.", 12f, 0.6f))
        }

        section("About") {
            addView(label("Song titles and artists are sent to LRCLIB, Kugou and NetEase to find lyrics. Lyrics you pick are saved on this phone only.", 12f, 0.6f))
        }
        updateNow()
    }
}
