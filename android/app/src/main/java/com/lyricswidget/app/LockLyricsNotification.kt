package com.lyricswidget.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** An opt-in notification, not an overlay over Android's security UI. */
internal class LockLyricsNotification(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private var posted: Pair<String, String>? = null

    fun update(state: CardState) {
        if (!manager.areNotificationsEnabled()) {
            clear()
            return
        }
        val title = state.title.ifBlank { "Lyrics Widget" }.take(200)
        val line = (state.lines.getOrNull(state.idx)?.text ?: state.status.ifBlank {
            if (state.lines.isNotEmpty()) "Lyrics ready" else "Waiting for playback…"
        }).take(500)
        val content = title to line
        if (posted == content) return

        manager.createNotificationChannel(NotificationChannel(
            CHANNEL, "Lock-screen lyrics", NotificationManager.IMPORTANCE_LOW
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        })
        if (manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) return

        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        val close = PendingIntent.getBroadcast(context, 0, Intent(context, CloseLyricsReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_note)
            .setContentTitle(title)
            .setContentText(line)
            .setStyle(Notification.BigTextStyle().bigText(line))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_STATUS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Close lyrics", close).build())
            .build()
        try {
            manager.notify(ID, notification)
            posted = content
        } catch (_: SecurityException) {
            // Notifications may have been disabled after the permission check.
        }
    }

    fun clear(force: Boolean = false) {
        if (force || posted != null) manager.cancel(ID)
        posted = null
    }

    companion object {
        private const val CHANNEL = "lock_lyrics"
        private const val ID = 17
    }
}

class CloseLyricsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LyricsStore.dismiss()
        LockLyricsNotification(context).clear(force = true)
    }
}
