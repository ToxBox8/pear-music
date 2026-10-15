package app.libremusic.ui

import app.libremusic.I18n
import app.libremusic.L
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import kotlin.math.cos
import kotlin.math.sin

/**
 * Elegir idioma (Cierre 1.0; lo pidió Toxbox): banderas, y al tocar la de España se despliegan español, catalán,
 * valenciano, gallego y euskera. Inglés (Reino Unido) y esperanto aparte. En la bienvenida y en Ajustes › Idioma.
 * Igual que `LanguagePicker` en iOS.
 */
@Composable
fun LanguagePicker() {
    val c = Libre.colors
    val context = LocalContext.current
    val current by I18n.lang.collectAsState()
    val spainLangs = I18n.LANGS.filter { it.spain }
    var spainOpen by rememberSaveable { mutableStateOf(current in spainLangs.map { it.code }) }
    val arrow by androidx.compose.animation.core.animateFloatAsState(if (spainOpen) 180f else 0f, uiEaseOut(260), label = "flecha")
    FormSection(null) {
        // España: la fila despliega sus idiomas.
        LangRow(
            flag = "es", title = L("España"), subtitle = spainLangs.joinToString(" · ") { it.name },
            selected = false,
            trailing = { Icon(Icons.Rounded.KeyboardArrowDown, null, tint = c.tertiaryLabel, modifier = Modifier.size(22.dp).rotate(arrow)) },
            onClick = { spainOpen = !spainOpen },
        )
        AnimatedVisibility(spainOpen, enter = expandVertically(uiEaseOut(300)) + fadeIn(uiEaseOut(300)), exit = shrinkVertically(uiEaseOut(220)) + fadeOut(uiEaseOut(180))) {
            Column {
                spainLangs.forEach { l ->
                    LangRow(l.code, l.name, null, selected = current == l.code, indent = true) { I18n.set(context, l.code) }
                }
            }
        }
        I18n.LANGS.filter { !it.spain }.forEach { l ->
            LangRow(l.code, l.name, null, selected = current == l.code, last = l.code == I18n.LANGS.last().code) { I18n.set(context, l.code) }
        }
    }
}

@Composable
private fun LangRow(
    flag: String, title: String, subtitle: String?, selected: Boolean, indent: Boolean = false, last: Boolean = false,
    trailing: (@Composable () -> Unit)? = null, onClick: () -> Unit,
) {
    val c = Libre.colors
    // Con el estilo de tarjetas por fila de Ajustes; sin él, con su línea de separación.
    val cards = LocalRowCards.current
    FormCustomRow { Column(Modifier.fillMaxWidth().rowHighlight(onClick = onClick)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = if (indent) 34.dp else 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Flag(flag, Modifier.size(34.dp, 24.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = Typo.body, color = c.label)
                if (subtitle != null) Text(subtitle, style = Typo.footnote, color = c.secondaryLabel)
            }
            when {
                trailing != null -> trailing()
                selected -> Icon(Icons.Rounded.Check, L("Elegido"), tint = c.accent, modifier = Modifier.size(22.dp))
            }
        }
        if (!last && !cards) Box(Modifier.fillMaxWidth().padding(start = if (indent) 82.dp else 64.dp).height(0.5.dp).background(c.separator))
    } }
}

/** Banderas dibujadas (sin emoji: se ven igual en todos los móviles). */
@Composable
fun Flag(code: String, modifier: Modifier) {
    Canvas(modifier.clip(RoundedCornerShape(4.dp))) {
        when (code) {
            "es" -> stripes(listOf(ES_RED to 1f, ES_YELLOW to 2f, ES_RED to 1f))
            "ca" -> senyera()
            "va" -> { senyera(); drawRect(VA_BLUE, size = Size(size.width * 0.26f, size.height)) }
            "gl" -> {
                drawRect(Color.White)
                val p = Path().apply {
                    moveTo(0f, 0f); lineTo(size.width * 0.16f, 0f); lineTo(size.width, size.height * 0.84f)
                    lineTo(size.width, size.height); lineTo(size.width * 0.84f, size.height); lineTo(0f, size.height * 0.16f); close()
                }
                drawPath(p, GL_BLUE)
            }
            "eu" -> {
                drawRect(EU_RED)
                val w = size.height * 0.16f
                drawLine(EU_GREEN, Offset(0f, 0f), Offset(size.width, size.height), w)
                drawLine(EU_GREEN, Offset(size.width, 0f), Offset(0f, size.height), w)
                drawLine(Color.White, Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), w)
                drawLine(Color.White, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), w)
            }
            "en" -> unionJack()
            "eo" -> {
                drawRect(EO_GREEN)
                val s = size.height / 2
                drawRect(Color.White, size = Size(s, s))
                star(Offset(s / 2, s / 2), s * 0.36f, EO_GREEN)
            }
        }
    }
}

private fun DrawScope.stripes(parts: List<Pair<Color, Float>>) {
    val total = parts.sumOf { it.second.toDouble() }.toFloat()
    var y = 0f
    parts.forEach { (color, weight) ->
        val h = size.height * weight / total
        drawRect(color, Offset(0f, y), Size(size.width, h + 0.5f))
        y += h
    }
}

private fun DrawScope.senyera() = stripes(List(9) { (if (it % 2 == 0) CA_YELLOW else CA_RED) to 1f })

private fun DrawScope.unionJack() {
    drawRect(UK_BLUE)
    val w = size.width; val h = size.height
    clipRect {
        drawLine(Color.White, Offset(0f, 0f), Offset(w, h), h * 0.2f)
        drawLine(Color.White, Offset(w, 0f), Offset(0f, h), h * 0.2f)
        drawLine(UK_RED, Offset(0f, 0f), Offset(w, h), h * 0.07f)
        drawLine(UK_RED, Offset(w, 0f), Offset(0f, h), h * 0.07f)
    }
    drawRect(Color.White, Offset(w / 2 - h * 0.17f, 0f), Size(h * 0.34f, h))
    drawRect(Color.White, Offset(0f, h / 2 - h * 0.17f), Size(w, h * 0.34f))
    drawRect(UK_RED, Offset(w / 2 - h * 0.1f, 0f), Size(h * 0.2f, h))
    drawRect(UK_RED, Offset(0f, h / 2 - h * 0.1f), Size(w, h * 0.2f))
}

private fun DrawScope.star(center: Offset, r: Float, color: Color) {
    val p = Path()
    for (i in 0 until 10) {
        val radius = if (i % 2 == 0) r else r * 0.42f
        val a = Math.toRadians(-90.0 + i * 36.0)
        val pt = Offset(center.x + radius * cos(a).toFloat(), center.y + radius * sin(a).toFloat())
        if (i == 0) p.moveTo(pt.x, pt.y) else p.lineTo(pt.x, pt.y)
    }
    p.close()
    drawPath(p, color)
}

private val ES_RED = Color(0xFFAA151B)
private val ES_YELLOW = Color(0xFFF1BF00)
private val CA_YELLOW = Color(0xFFFCDD09)
private val CA_RED = Color(0xFFDA121A)
private val VA_BLUE = Color(0xFF0B57A4)
private val GL_BLUE = Color(0xFF0099CC)
private val EU_RED = Color(0xFFD52B1E)
private val EU_GREEN = Color(0xFF009B48)
private val UK_BLUE = Color(0xFF012169)
private val UK_RED = Color(0xFFC8102E)
private val EO_GREEN = Color(0xFF009900)
