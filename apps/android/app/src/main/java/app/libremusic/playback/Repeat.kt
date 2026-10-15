@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.playback


import app.libremusic.L
import android.os.Bundle
import androidx.media3.common.Player
import androidx.media3.session.CommandButton
import androidx.media3.session.SessionCommand

/**
 * Bucle de tres estados (no / lista / canción). Se guarda como `repeatMode` = off / all / one,
 * el mismo valor que iOS (`RepeatMode` en Player.swift).
 */
object Repeat {
    const val ACTION = "app.libremusic.REPEAT"
    val command by lazy { SessionCommand(ACTION, Bundle.EMPTY) }

    fun next(mode: Int): Int = when (mode) {
        Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
        Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
        else -> Player.REPEAT_MODE_OFF
    }

    fun key(mode: Int): String = when (mode) {
        Player.REPEAT_MODE_ALL -> "all"
        Player.REPEAT_MODE_ONE -> "one"
        else -> "off"
    }

    fun fromKey(key: String?): Int = when (key) {
        "all" -> Player.REPEAT_MODE_ALL
        "one" -> Player.REPEAT_MODE_ONE
        else -> Player.REPEAT_MODE_OFF
    }

    fun label(mode: Int): String = when (mode) {
        Player.REPEAT_MODE_ALL -> L("Repetir lista")
        Player.REPEAT_MODE_ONE -> L("Repetir canción")
        else -> L("Repetir: no")
    }

    /** Botón de la notificación y la pantalla de bloqueo, con el icono del estado actual. */
    fun button(mode: Int): CommandButton = CommandButton.Builder(
        when (mode) {
            Player.REPEAT_MODE_ALL -> CommandButton.ICON_REPEAT_ALL
            Player.REPEAT_MODE_ONE -> CommandButton.ICON_REPEAT_ONE
            else -> CommandButton.ICON_REPEAT_OFF
        },
    )
        .setDisplayName(label(mode))
        .setSessionCommand(command)
        .build()
}
