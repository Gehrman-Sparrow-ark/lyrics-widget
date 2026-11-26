package com.lyricswidget.app

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: turns the floating lyrics card on or off. */
class LyricsTile : TileService() {
    override fun onStartListening() {
        update()
    }

    override fun onClick() {
        Prefs.init(this)
        Prefs.enabled = !Prefs.enabled
        if (Prefs.enabled) LyricsStore.undismiss()
        update()
    }

    private fun update() {
        Prefs.init(this)
        val tile = qsTile ?: return
        tile.state = if (Prefs.enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }
}
