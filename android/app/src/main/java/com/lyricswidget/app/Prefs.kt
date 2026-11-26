package com.lyricswidget.app

import android.content.Context
import android.content.SharedPreferences
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

private class BoolP(val key: String, val def: Boolean) : ReadWriteProperty<Any?, Boolean> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): Boolean = Prefs.sp.getBoolean(key, def)
    override fun setValue(thisRef: Any?, property: KProperty<*>, value: Boolean) {
        Prefs.sp.edit().putBoolean(key, value).apply()
    }
}

private class IntP(val key: String, val def: Int) : ReadWriteProperty<Any?, Int> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): Int = Prefs.sp.getInt(key, def)
    override fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
        Prefs.sp.edit().putInt(key, value).apply()
    }
}

private class StrP(val key: String, val def: String) : ReadWriteProperty<Any?, String> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): String = Prefs.sp.getString(key, def) ?: def
    override fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        Prefs.sp.edit().putString(key, value).apply()
    }
}

/** Every customization lives here and is edited from the app's settings screen. */
object Prefs {
    lateinit var sp: SharedPreferences

    fun init(ctx: Context) {
        if (!::sp.isInitialized) {
            sp = ctx.applicationContext.getSharedPreferences("lyrics_widget", Context.MODE_PRIVATE)
        }
    }

    var enabled by BoolP("enabled", true)

    // Colours: "#RRGGBB", or for bg the special value "art" (tinted from the album cover).
    // line "" means automatic (light on dark, dark on light).
    var bg by StrP("bg", "#000000")
    var line by StrP("line", "")

    var bgOpacity by IntP("bgOpacity", 92)      // percent
    var textScale by IntP("textScale", 100)     // percent
    var visibleLines by IntP("visibleLines", 3) // 1, 3 or 5
    var radius by IntP("radius", 24)            // dp
    var widthPct by IntP("widthPct", 94)        // percent of screen width
    var alignLeft by BoolP("alignLeft", false)

    var showArt by BoolP("showArt", true)
    var showTitle by BoolP("showTitle", true)
    var showProgress by BoolP("showProgress", false)
    var showControls by BoolP("showControls", false)

    var hideWhenPaused by BoolP("hideWhenPaused", false)
    var hideNoLyrics by BoolP("hideNoLyrics", false)

    var lockPos by BoolP("lockPos", false)
    var posX by IntP("posX", 0)   // dp from horizontal centre
    var posY by IntP("posY", -1)  // dp from the top of the screen, -1 = just under the status bar

    fun applyPreset(name: String) {
        when (name) {
            "lyrics" -> { showArt = false; showTitle = false; showProgress = false; showControls = false; visibleLines = 3 }
            "player" -> { showArt = true; showTitle = true; showProgress = true; showControls = true; visibleLines = 1 }
            else -> { showArt = true; showTitle = true; showProgress = false; showControls = false; visibleLines = 3 }
        }
    }
}
