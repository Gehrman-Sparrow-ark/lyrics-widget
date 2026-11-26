package com.lyricswidget.app

import android.app.Application
import com.google.android.material.color.DynamicColors

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        LyricsStore.init(this)
        // Settings screens follow the phone's wallpaper colours on Android 12+.
        DynamicColors.applyToActivitiesIfAvailable(this)
    }
}
