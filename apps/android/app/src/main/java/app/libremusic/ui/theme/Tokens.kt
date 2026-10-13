// Generado por shared/design/gen_tokens.py desde shared/design/tokens.json. No editar a mano.
package app.libremusic.ui.theme

import androidx.compose.ui.graphics.Color

object Tokens {
    object Brand {
        val Violet = Color(0xFF8B5CF6)
        val VioletDeep = Color(0xFF5B21B6)
        val Magenta = Color(0xFFEC4899)
        val Amber = Color(0xFFF59E0B)
        val Night = Color(0xFF07070A)
    }
    val ArtworkFallback = listOf(Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B))

    data class ThemeSpec(
        val name: String,
        val blurb: String,
        val accent: Color,
        val onAccent: Color,
        /** "light", "dark" o null (el que elija el usuario). */
        val scheme: String?,
        val rounded: Boolean,
        val maxRadius: Float,
    )
    val Themes: Map<String, ThemeSpec> = mapOf(
        "air" to ThemeSpec("Aire", "Plata con Helvetica negra y un anillo de puntos.", Color(0xFF111111), Color(0xFFFFFFFF), "light", false, 40f),
        "glass" to ThemeSpec("Cristal", "Luz difusa con los colores de la carátula.", Color(0xFF8B5CF6), Color(0xFFFFFFFF), null, false, 40f),
        "neon" to ThemeSpec("Neón", "Rejilla synthwave que avanza mientras suena.", Color(0xFFFF2BD6), Color(0xFFFFFFFF), "dark", true, 40f),
        "plain" to ThemeSpec("Sistema", "Sin efectos ni fondos animados.", Color(0xFF8B5CF6), Color(0xFFFFFFFF), null, false, 40f),
    )
    val ThemeOrder = listOf("glass", "air", "neon", "plain")
    const val DefaultTheme = "glass"

    object Radius {
        const val Row = 14f
        const val Card = 16f
        const val ArtworkSmall = 12f
        const val ArtworkCard = 16f
        const val ArtworkPlayer = 22f
        const val Pill = 14f
        const val Sheet = 28f
        const val PlaylistCard = 28f
        const val MiniPlayer = 22f
        const val FormGroup = 26f
    }
    object TypeSize {
        const val LargeTitle = 34f
        const val Title = 28f
        const val Title2 = 22f
        const val Title3 = 20f
        const val Headline = 17f
        const val Body = 17f
        const val Callout = 16f
        const val Subheadline = 15f
        const val Footnote = 13f
        const val Caption = 12f
        const val Caption2 = 11f
        const val DisplayLibrary = 40f
        const val DisplayScreen = 30f
        const val DisplaySection = 24f
    }
    object SysLight {
        val Background = Color(0xFFFFFFFF)
        val GroupedBackground = Color(0xFFF2F2F7)
        val SecondaryGroupedBackground = Color(0xFFFFFFFF)
        val Label = Color(0xFF000000)
        val SecondaryLabel = Color(0x993C3C43)
        val TertiaryLabel = Color(0x4D3C3C43)
        val Separator = Color(0x493C3C43)
        val Fill = Color(0x33787880)
    }
    object SysDark {
        val Background = Color(0xFF000000)
        val GroupedBackground = Color(0xFF000000)
        val SecondaryGroupedBackground = Color(0xFF1C1C1E)
        val Label = Color(0xFFFFFFFF)
        val SecondaryLabel = Color(0x99EBEBF5)
        val TertiaryLabel = Color(0x4DEBEBF5)
        val Separator = Color(0x99545458)
        val Fill = Color(0x5C787880)
    }
    val PlaylistPalettes: List<List<Color>> = listOf(
        listOf(Color(0xFFFF5C8C), Color(0xFFFA994D)),
        listOf(Color(0xFF8C59FF), Color(0xFFF266D9)),
        listOf(Color(0xFF3380FF), Color(0xFF59D9FF)),
        listOf(Color(0xFF26BF8C), Color(0xFF99F273)),
        listOf(Color(0xFFFF9E1A), Color(0xFFFFD94D)),
        listOf(Color(0xFFF2334D), Color(0xFF8C1A73)),
        listOf(Color(0xFF404066), Color(0xFF8080B3)),
        listOf(Color(0xFF1AB3BF), Color(0xFF4D66F2)),
    )
    val HoloRainbow = listOf(Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFFFFE600), Color(0xFF34C759), Color(0xFF00C7FF), Color(0xFF3D5BFF), Color(0xFFB34DFF))
    object AirLight {
        val Paper = Color(0xFFE7E9EC)
        val Panel = Color(0xFFD6D9DE)
        val Wheel = Color(0xFFF8F9FB)
        val Hub = Color(0xFFC9CDD3)
        val Ink = Color(0xFF111214)
        val Muted = Color(0xFF62666D)
        val DotOff = Color(0xFFA9AEB5)
    }
    object AirDark {
        val Paper = Color(0xFF111112)
        val Panel = Color(0xFF1E1E20)
        val Wheel = Color(0xFF2C2C2F)
        val Hub = Color(0xFF19191B)
        val Ink = Color(0xFFFFFFFF)
        val Muted = Color(0xFF9A9A9E)
        val DotOff = Color(0xFF4A4A4E)
    }
    object Motion {
        val EaseOut = floatArrayOf(0.23f, 1f, 0.32f, 1f)
        const val FastMs = 150
        const val NormalMs = 250
        const val SlowMs = 420
    }
}
