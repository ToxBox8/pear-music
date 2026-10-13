package app.libremusic.ui.theme

import androidx.compose.ui.unit.dp

import androidx.compose.material.icons.Icons
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
 * El icono del Jam de iOS (`person.2.wave.2`: dos personas con ondas a los lados), dibujado a mano
 * porque SF Symbols no se puede usar fuera de Apple y Material no tiene uno igual. [filled] para
 * el Jam activo (`person.2.wave.2.fill`).
 */
private fun jamVector(filled: Boolean): androidx.compose.ui.graphics.vector.ImageVector {
    val w = if (filled) 2.1f else 1.6f
    val ink = androidx.compose.ui.graphics.SolidColor(androidx.compose.ui.graphics.Color.Black)
    return androidx.compose.ui.graphics.vector.ImageVector.Builder(
        name = if (filled) "JamFill" else "Jam", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f,
    ).apply {
        val stroke: androidx.compose.ui.graphics.vector.ImageVector.Builder.(androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) -> Unit = { block ->
            addPath(
                androidx.compose.ui.graphics.vector.PathBuilder().apply(block).nodes,
                stroke = ink, strokeLineWidth = w,
                strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round,
                strokeLineJoin = androidx.compose.ui.graphics.StrokeJoin.Round,
            )
        }
        // Ondas a la izquierda y a la derecha.
        stroke { moveTo(5.9f, 7.7f); arcTo(7.5f, 7.5f, 0f, false, false, 5.9f, 16.3f) }
        stroke { moveTo(3.4f, 6.0f); arcTo(10.5f, 10.5f, 0f, false, false, 3.4f, 18.0f) }
        stroke { moveTo(18.1f, 7.7f); arcTo(7.5f, 7.5f, 0f, false, true, 18.1f, 16.3f) }
        stroke { moveTo(20.6f, 6.0f); arcTo(10.5f, 10.5f, 0f, false, true, 20.6f, 18.0f) }
        // Persona de delante: cabeza y hombros.
        stroke { moveTo(12.6f, 9.6f); arcTo(2.0f, 2.0f, 0f, true, true, 8.6f, 9.6f); arcTo(2.0f, 2.0f, 0f, true, true, 12.6f, 9.6f); close() }
        stroke { moveTo(7.4f, 16.4f); arcTo(3.2f, 3.0f, 0f, false, true, 13.8f, 16.4f) }
        // Persona de detrás, asomando a la derecha.
        stroke { moveTo(15.8f, 8.7f); arcTo(1.6f, 1.6f, 0f, true, false, 13.4f, 7.4f) }
        stroke { moveTo(14.7f, 12.3f); arcTo(2.6f, 2.6f, 0f, false, true, 16.7f, 15.2f) }
    }.build()
}

private val jamOutline by lazy { jamVector(false) }
private val jamFill by lazy { jamVector(true) }

fun JamIcon(filled: Boolean = false): androidx.compose.ui.graphics.vector.ImageVector = if (filled) jamFill else jamOutline
