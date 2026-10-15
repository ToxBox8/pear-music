package app.libremusic.ui.theme

import androidx.compose.ui.unit.dp

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.BeachAccess
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Celebration
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.DirectionsRun
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Flight
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.Hotel
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.LocalCafe
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Piano
import androidx.compose.material.icons.rounded.SportsEsports
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Thunderstorm
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Los iconos de playlist se guardan con el nombre del símbolo de iOS (SF Symbols) para que
 * library.json sea el mismo en las dos apps. SF Symbols sólo puede usarse en sistemas de Apple,
 * así que en Android se dibuja el icono equivalente de Material (estilo redondeado).
 */
object SfIcons {
    /** Mismo orden que PlaylistStyle.icons en iOS. */
    val playlistIcons: List<String> = listOf(
        "music.note.list", "heart.fill", "star.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
        "sun.max.fill", "car.fill", "figure.run", "dumbbell.fill", "headphones", "guitars.fill",
        "pianokeys", "mic.fill", "party.popper.fill", "cup.and.saucer.fill", "book.fill", "leaf.fill",
        "airplane", "gamecontroller.fill", "sparkles", "cloud.rain.fill", "beach.umbrella.fill", "bed.double.fill",
    )

    fun of(name: String?): ImageVector = when (name) {
        "music.note.list" -> Icons.AutoMirrored.Rounded.QueueMusic
        "heart.fill" -> Icons.Rounded.Favorite
        "star.fill" -> Icons.Rounded.Star
        "flame.fill" -> Icons.Rounded.LocalFireDepartment
        "bolt.fill" -> Icons.Rounded.Bolt
        "moon.stars.fill" -> Icons.Rounded.NightsStay
        "sun.max.fill" -> Icons.Rounded.WbSunny
        "car.fill" -> Icons.Rounded.DirectionsCar
        "figure.run" -> Icons.Rounded.DirectionsRun
        "dumbbell.fill" -> Icons.Rounded.FitnessCenter
        "headphones" -> Icons.Rounded.Headphones
        "guitars.fill" -> Icons.Rounded.LibraryMusic
        "pianokeys" -> Icons.Rounded.Piano
        "mic.fill" -> Icons.Rounded.Mic
        "party.popper.fill" -> Icons.Rounded.Celebration
        "cup.and.saucer.fill" -> Icons.Rounded.LocalCafe
        "book.fill" -> Icons.AutoMirrored.Rounded.MenuBook
        "leaf.fill" -> Icons.Rounded.Eco
        "airplane" -> Icons.Rounded.Flight
        "gamecontroller.fill" -> Icons.Rounded.SportsEsports
        "sparkles" -> Icons.Rounded.AutoAwesome
        "cloud.rain.fill" -> Icons.Rounded.Thunderstorm
        "beach.umbrella.fill" -> Icons.Rounded.BeachAccess
        "bed.double.fill" -> Icons.Rounded.Hotel
        "square.grid.2x2" -> Icons.Rounded.GridView
        else -> Icons.AutoMirrored.Rounded.QueueMusic
    }
}

/**
 * El icono del Jam: un grupo de tres personas, el mismo que usa SimpMusic para escuchar juntos (lo pidió Toxbox).
 * En iOS, `person.3` / `person.3.fill`. [filled] para el Jam activo.
 */
private fun jamVector(filled: Boolean): androidx.compose.ui.graphics.vector.ImageVector =
    if (filled) Icons.Rounded.Groups else Icons.Outlined.Groups

private val jamOutline by lazy { jamVector(false) }
private val jamFill by lazy { jamVector(true) }

fun JamIcon(filled: Boolean = false): androidx.compose.ui.graphics.vector.ImageVector = if (filled) jamFill else jamOutline
