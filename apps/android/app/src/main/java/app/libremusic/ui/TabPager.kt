package app.libremusic.ui

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Deslizar entre pestañas (como Instagram). Todo es estado que se lee al dibujar: arrastrar no recompone pantallas.
 *
 * - [offset]: píxeles que se ha movido la pestaña actual (negativo = hacia la siguiente, a la izquierda).
 * - Al soltar, [settle] sigue un muelle que arranca con la velocidad del dedo (antes era siempre un tween de 320 ms,
 *   que frenaba en seco un gesto rápido y alargaba uno lento).
 * - Un toque durante esa animación la atrapa ([catchSettle]) y el dedo sigue desde donde está la pantalla.
 * - Las barras leen [position] (pestaña fraccionaria) para que la gota o la píldora acompañen al dedo.
 */
@Stable
class TabPager {
    /** Ancho del contenido en píxeles. */
    var width by mutableFloatStateOf(1f)

    /** Índice de la pestaña actual dentro de las de la barra (-1 si la actual no está en la barra). */
    var index by mutableIntStateOf(0)

    var offset by mutableFloatStateOf(0f)
        private set

    private var settleJob: Job? = null
    private var settleTarget: Tab? = null

    /** Pestaña fraccionaria que se está viendo (2.4 = 40 % camino de la 2 a la 3); null si no se desliza. */
    fun position(): Float? = if (offset == 0f || index < 0) null else index - offset / width

    /** Dónde dibujar la pantalla de [tab] (null = no se ve). */
    fun screenX(
        tab: Tab,
        current: Tab,
        tabs: List<Tab>,
    ): Float? {
        if (tab == current) return offset
        val i = tabs.indexOf(tab)
        if (i < 0 || index < 0) return null
        return when {
            offset < 0f && i == index + 1 -> offset + width
            offset > 0f && i == index - 1 -> offset - width
            else -> null
        }
    }

    fun dragBy(
        dx: Float,
        tabs: List<Tab>,
    ) {
        val next = offset + dx
        val neighbor = if (next < 0f) index + 1 else index - 1
        offset =
            if (neighbor in tabs.indices) {
                next.coerceIn(-width, width)
            } else {
                // Sin pestaña a ese lado se resiste, como el final de una lista.
                (offset + dx * 0.3f).coerceIn(-width * 0.2f, width * 0.2f)
            }
    }

    fun settle(
        scope: CoroutineScope,
        velocity: Float,
        density: Float,
        reduceMotion: Boolean,
        tabs: List<Tab>,
        commit: (Tab) -> Unit,
    ): Job {
        val w = width
        val fling = 500f * density
        val towardNext = offset < 0f && index + 1 in tabs.indices
        val towardPrev = offset > 0f && index - 1 in tabs.indices
        // Va si pasa de la mitad o si el dedo sale lanzado hacia ese lado; un lanzamiento hacia atrás lo devuelve.
        val goes =
            (towardNext && velocity < fling && (offset < -w * 0.5f || velocity < -fling)) ||
                (towardPrev && velocity > -fling && (offset > w * 0.5f || velocity > fling))
        val target = if (!goes) null else tabs[if (offset < 0f) index + 1 else index - 1]
        val end = if (!goes) 0f else if (offset < 0f) -w else w
        settleTarget = target
        return scope.launch {
                // Muelle sin rebote: llega con la velocidad del gesto y no se pasa de la pantalla vecina.
                val spec = if (reduceMotion) tween<Float>(120) else spring(dampingRatio = 1f, stiffness = 500f, visibilityThreshold = 0.5f)
                animate(offset, end, initialVelocity = if (reduceMotion) 0f else velocity, animationSpec = spec) { v, _ ->
                    offset = v.coerceIn(-w, w)
                }
                settleTarget = null
                if (target != null) {
                    // Mismo fotograma: la pestaña nueva pasa a ser la actual y deja de haber desplazamiento.
                    index = tabs.indexOf(target)
                    offset = 0f
                    commit(target)
                }
            }.also { settleJob = it }
    }

    /** Un dedo nuevo durante la animación de soltar: se para y, si iba a otra pestaña, se da por hecha. */
    fun catchSettle(commit: (Tab) -> Unit) {
        val job = settleJob ?: return
        if (!job.isActive) return
        job.cancel()
        val target = settleTarget ?: return
        settleTarget = null
        // La pestaña vecina pasa a ser la actual sin moverse en pantalla.
        if (offset < 0f) {
            index += 1
            offset += width
        } else {
            index -= 1
            offset -= width
        }
        commit(target)
    }
}
