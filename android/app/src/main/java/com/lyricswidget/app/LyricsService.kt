package com.lyricswidget.app

import android.content.res.Configuration
import android.service.notification.NotificationListenerService

/**
 * Notification access is what lets the app read the active media session.
 * The system keeps this service alive, and it hosts the overlay and the media tracker.
 */
class LyricsService : NotificationListenerService() {
    private var tracker: MediaTracker? = null
    private var overlay: OverlayController? = null

    companion object {
        @Volatile
        var instance: LyricsService? = null
    }

    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        LyricsStore.init(this)
        instance = this
    }

    override fun onListenerConnected() {
        startAll()
    }

    override fun onListenerDisconnected() {
        stopAll()
    }

    override fun onDestroy() {
        stopAll()
        instance = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        overlay?.relayout()
    }

    fun refresh() {
        overlay?.evaluate()
    }

    private fun startAll() {
        if (tracker != null) return
        tracker = MediaTracker(this).also { it.start() }
        overlay = OverlayController(this).also { it.start() }
    }

    private fun stopAll() {
        overlay?.stop()
        tracker?.stop()
        overlay = null
        tracker = null
    }
}
