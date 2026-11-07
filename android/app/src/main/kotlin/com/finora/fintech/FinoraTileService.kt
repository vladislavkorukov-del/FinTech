package com.finora.fintech

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Finora in the Quick Settings shade (1.27): a tap opens the app and she
 * listens straight away.
 */
class FinoraTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = "Финора"
            if (Build.VERSION.SDK_INT >= 29) subtitle = "Сказать"
            updateTile()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(FinoraBridge.launch(this, "voice", 1))
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra(FinoraBridge.EXTRA_ACTION, "voice")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
