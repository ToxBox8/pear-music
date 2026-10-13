package app.libremusic.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.libremusic.R

// Letra. iOS usa SF Pro, que sólo se puede usar en sistemas de Apple; Inter (OFL) está
// dibujada con las mismas proporciones y es la más parecida. Los tamaños son los estilos
// de texto de iOS (Tokens.TypeSize) en sp, así que también crecen con el tamaño de letra del sistema.

val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)

/** Corte «display» para títulos grandes y el grotesco negro de Air (Helvetica Neue Bold en iOS). */
val InterDisplay = FontFamily(
    Font(R.font.inter_display_bold, FontWeight.Bold),
    Font(R.font.inter_display_heavy, FontWeight.ExtraBold),
)

private fun style(size: Float, weight: FontWeight = FontWeight.Normal, tracking: TextUnit = (-0.01).em) = TextStyle(
    fontFamily = Inter,
    fontSize = size.sp,
    fontWeight = weight,
    lineHeight = (size * 1.27f).sp,
    letterSpacing = tracking,
)

/** Los estilos de texto de iOS con su peso por defecto. Uso: `Typo.subheadline.semibold`. */
object Typo {
    val largeTitle = style(Tokens.TypeSize.LargeTitle, FontWeight.Bold, (-0.02).em)
    val title = style(Tokens.TypeSize.Title, FontWeight.Bold, (-0.02).em)
    val title2 = style(Tokens.TypeSize.Title2, FontWeight.Bold, (-0.015).em)
    val title3 = style(Tokens.TypeSize.Title3)
    val headline = style(Tokens.TypeSize.Headline, FontWeight.SemiBold)
    val body = style(Tokens.TypeSize.Body)
    val callout = style(Tokens.TypeSize.Callout)
    val subheadline = style(Tokens.TypeSize.Subheadline)
    val footnote = style(Tokens.TypeSize.Footnote, tracking = 0.em)
    val caption = style(Tokens.TypeSize.Caption, tracking = 0.em)
    val caption2 = style(Tokens.TypeSize.Caption2, tracking = 0.01.em)

    /** Título grande del tema: Air usa el grotesco negro y apretado; el resto, Inter Display. */
    fun display(size: Float, theme: AppTheme): TextStyle = TextStyle(
        fontFamily = InterDisplay,
        fontWeight = FontWeight.Bold,
        fontSize = size.sp,
        lineHeight = (size * 1.15f).sp,
        letterSpacing = if (theme == AppTheme.Air) (-0.025).em else (-0.02).em,
    )

    /** Texto de Air (Helvetica Neue en iOS). */
    fun air(size: Float, bold: Boolean = false): TextStyle = TextStyle(
        fontFamily = if (bold) InterDisplay else Inter,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        fontSize = size.sp,
        letterSpacing = if (bold) (-0.02).em else 0.em,
    )

    /** Monoespaciada (códigos del Jam, casete). */
    fun mono(size: Float, weight: FontWeight = FontWeight.Bold): TextStyle = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = weight,
        fontSize = size.sp,
    )
}

val TextStyle.medium get() = copy(fontWeight = FontWeight.Medium)
val TextStyle.semibold get() = copy(fontWeight = FontWeight.SemiBold)
val TextStyle.bold get() = copy(fontWeight = FontWeight.Bold)

/** Material3 se usa en diálogos y campos de texto: con Inter y los tamaños de iOS. */
val LibreTypography = Typography(
    displayLarge = Typo.largeTitle,
    headlineLarge = Typo.largeTitle,
    headlineMedium = Typo.title,
    headlineSmall = Typo.title2,
    titleLarge = Typo.title3.semibold,
    titleMedium = Typo.headline,
    titleSmall = Typo.subheadline.semibold,
    bodyLarge = Typo.body,
    bodyMedium = Typo.subheadline,
    bodySmall = Typo.footnote,
    labelLarge = Typo.subheadline.semibold,
    labelMedium = Typo.caption.medium,
    labelSmall = Typo.caption2,
)
