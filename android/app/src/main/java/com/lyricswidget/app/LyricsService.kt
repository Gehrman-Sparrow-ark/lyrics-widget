package com.lyricswidget.app

import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat

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

        fun reconnect(context: Context) {
            if (!Prefs.enabled || instance?.isListening == true ||
                context.packageName !in NotificationManagerCompat.getEnabledListenerPackages(context)) return
            try {
                requestRebind(ComponentName(context, LyricsService::class.java))
            } catch (_: IllegalStateException) {
                // The notification service is not ready.
            } catch (_: SecurityException) {
                // The user may have just revoked access.
            }
        }
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
        reconnect(this)
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

    val isListening: Boolean get() = tracker != null

    fun refresh(rescan: Boolean = false) {
        if (rescan) tracker?.refresh()
        overlay?.evaluate()
    }

    fun showWidgetNow(): Boolean {
        val controller = overlay ?: return false
        Prefs.enabled = true
        controller.showNow()
        return true
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
