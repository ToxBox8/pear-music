/*
 * Adaptado de SimpMusic (maxrave-dev/SimpMusic, GPL-3.0): LiquidGlassAppBottomNavigationBar.android.kt.
 * Copiado de Open Menus (~/Proyectos/open-menus, sesión «simpmusic rea») para Pear Music: mismo vidrio, tamaños y
 * animaciones. Sólo cambian el paquete, las pestañas, los colores y el mini reproductor (datos de Pear).
 */
package app.libremusic.ui.simpbar


import app.libremusic.L
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import androidx.constraintlayout.compose.ConstraintLayout
import androidx.constraintlayout.compose.ConstraintSet
import androidx.constraintlayout.compose.Dimension
import app.libremusic.data.Song
import app.libremusic.ui.CoverImage
import app.libremusic.ui.Tab
import app.libremusic.ui.icon
import app.libremusic.ui.theme.Libre
import androidx.compose.ui.graphics.Color
import com.kyant.backdrop.backdrops.LayerBackdrop

// Lo que tarda la barra en transformarse entre la barra de pestañas y el círculo plegado.
private const val BAR_MORPH_MS = 300
private val BarEdgePadding = 16.dp
private val SearchGap = 12.dp
private val SearchSize = 56.dp
private val MiniPlayerPadding = 12.dp
private val MiniPlayerGap = 12.dp

/** Cómo se pliega la barra: tal como lo hace cada versión publicada de SimpMusic. */
enum class FoldStyle(
    val label: String,
) {
    /** La barra se cambia de golpe por un círculo de vidrio aparte; solo se anima su posición. */
    V220("2.2.0"),

    /** La cápsula se encoge hasta ser el círculo y las pestañas se recortan mientras tanto. */
    V230("2.3"),
}

/**
 * Barra inferior completa: cápsula de pestañas + botón de buscar de vidrio + mini-reproductor.
 * Con scroll hacia abajo (o en Buscar) se pliega en un círculo con la pestaña activa y el
 * mini-reproductor se coloca a su lado; tocar el círculo la despliega.
 */
@Composable
fun GlassBottomBar(
    foldStyle: FoldStyle,
    barTabs: List<Tab>,
    selected: Tab,
    onSelect: (Tab) -> Unit,
    isScrolledToTop: Boolean,
    backdrop: LayerBackdrop,
    glass: Boolean,
    nowPlaying: Song?,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    isLiked: Boolean,
    onToggleLike: () -> Unit,
    onOpenPlayer: () -> Unit,
    modifier: Modifier = Modifier,
    /** Pestaña fraccionaria mientras se desliza el contenido (null si no): la gota acompaña al dedo. */
    follow: () -> Float? = { null },
) {
    val player: @Composable (Modifier, State<Float>) -> Unit = { playerModifier, luminance ->
        if (nowPlaying != null) MiniPlayer(nowPlaying, isPlaying, onTogglePlay, isLiked, onToggleLike, onOpenPlayer, backdrop, luminance, glass, playerModifier)
    }
    when (foldStyle) {
        FoldStyle.V220 -> BottomBarV220(barTabs, selected, onSelect, isScrolledToTop, backdrop, glass, player, modifier, follow)
        FoldStyle.V230 -> BottomBarV230(barTabs, selected, onSelect, isScrolledToTop, backdrop, glass, player, modifier, follow)
    }
}

/** SimpMusic 2.3 (rama dev): la cápsula se despliega desde el círculo a la vez que el mini-reproductor. */
@Composable
private fun BottomBarV230(
    barTabs: List<Tab>,
    selected: Tab,
    onSelect: (Tab) -> Unit,
    isScrolledToTop: Boolean,
    backdrop: LayerBackdrop,
    glass: Boolean,
    player: @Composable (Modifier, State<Float>) -> Unit,
    modifier: Modifier,
    follow: () -> Float?,
) {
    val layer = rememberGraphicsLayer()
    val searchInteraction = rememberGlassInteraction()
    // Solo el vidrio lee lo que hay detrás.
    val luminance = rememberGlassLuminance(layer, enabled = glass)

    var isExpanded by rememberSaveable { mutableStateOf(true) }
    val inSearch = selected == Tab.Search

    LaunchedEffect(inSearch) { isExpanded = !inSearch }
    LaunchedEffect(isScrolledToTop) { if (!inSearch) isExpanded = isScrolledToTop }

    val constraintSet = remember(isExpanded) { decoupledConstraints(isExpanded) }

    val collapsedCircle: @Composable () -> Unit = {
        Box(
            modifier = Modifier.fillMaxSize().clickable(enabled = !isExpanded) { isExpanded = true },
            contentAlignment = Alignment.Center,
        ) {
            CompositionLocalProvider(LocalContentColor provides Libre.colors.accent) {
                Icon(selected.icon(), contentDescription = L("Desplegar barra ({0})", selected.title))
            }
        }
    }

    BoxWithConstraints(
        modifier =
            modifier
                .fillMaxWidth()
                .padding(WindowInsets.navigationBars.asPaddingValues())
                .padding(bottom = 8.dp),
    ) {
        val capsuleBudget = maxWidth - BarEdgePadding * 2 - SearchGap - SearchSize
        val capsuleWidth = liquidGlassTabBarWidth(barTabs.size, capsuleBudget)
        ConstraintLayout(
            constraintSet = constraintSet,
            modifier = Modifier.fillMaxWidth(),
            animateChangesSpec = tween(BAR_MORPH_MS),
        ) {
            // ConstraintLayout anima el marco de la barra desde el círculo hasta el ancho completo y la
            // mide en cada ancho intermedio: la cápsula recibe ese crecimiento, así que se abre desde el
            // borde a la vez que el mini-reproductor.
            Layout(
                modifier = Modifier.layoutId("toolbar"),
                content = {
                    LiquidGlassTabBar(
                        tabs = barTabs,
                        selectedTab = barTabs.indexOf(selected),
                        backdrop = backdrop,
                        layer = layer,
                        luminance = luminance,
                        glass = glass,
                        availableWidth = capsuleBudget,
                        onTabSelected = { position -> onSelect(barTabs[position]) },
                        follow = follow,
                        collapsedContent = collapsedCircle,
                    )
                    Box(
                        modifier =
                            Modifier
                                .size(SearchSize)
                                .then(
                                    if (glass) {
                                        // Solo la cápsula graba la muestra compartida: Buscar no debe pisarla.
                                        Modifier.drawInteractiveGlass(backdrop, null, { luminance.value }, CircleShape, searchInteraction)
                                    } else {
                                        Modifier.flatSurface(CircleShape)
                                    },
                                ).clickable { onSelect(Tab.Search) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Tab.Search.icon(),
                            contentDescription = Tab.Search.title,
                            tint = if (inSearch) Libre.colors.accent else BarContent,
                        )
                    }
                },
            ) { measurables, constraints ->
                val folded = CollapsedBarSize.roundToPx()
                val capsule = capsuleWidth.roundToPx()
                val gap = SearchGap.roundToPx()
                val search = SearchSize.roundToPx()
                val expanded = capsule + gap + search
                val width = if (constraints.hasFixedWidth) constraints.maxWidth else expanded.coerceIn(constraints.minWidth, constraints.maxWidth)
                val height =
                    if (constraints.hasFixedHeight) {
                        constraints.maxHeight
                    } else {
                        BarHeight.roundToPx().coerceIn(constraints.minHeight, constraints.maxHeight)
                    }
                val progress = ((width - folded).toFloat() / (expanded - folded).coerceAtLeast(1)).coerceIn(0f, 1f)
                val bar = measurables[0].measure(Constraints.fixed(lerp(folded, capsule, progress), height))
                val fab = measurables[1].measure(Constraints.fixed(search, search))
                val fabAlpha = ((progress - 0.5f) / 0.5f).coerceIn(0f, 1f)
                layout(width, height) {
                    bar.placeRelative(0, 0)
                    // Sin colocar mientras está oculto, para que no quede un botón invisible.
                    if (fabAlpha > 0f) {
                        fab.placeRelativeWithLayer(capsule + gap, (height - search) / 2) {
                            alpha = fabAlpha
                            scaleX = lerp(0.8f, 1f, fabAlpha)
                            scaleY = scaleX
                        }
                    }
                }
            }
            player(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = MiniPlayerPadding)
                    .height(56.dp)
                    .layoutId("miniPlayer"),
                luminance,
            )
        }
    }
}

/**
 * SimpMusic 2.2.0: plegada, la barra se cambia de golpe por un círculo de vidrio aparte y solo se
 * anima la posición de las piezas (ConstraintLayout, 300 ms). Muestrea el fondo cada segundo.
 */
@Composable
private fun BottomBarV220(
    barTabs: List<Tab>,
    selected: Tab,
    onSelect: (Tab) -> Unit,
    isScrolledToTop: Boolean,
    backdrop: LayerBackdrop,
    glass: Boolean,
    player: @Composable (Modifier, State<Float>) -> Unit,
    modifier: Modifier,
    follow: () -> Float?,
) {
    val layer = rememberGraphicsLayer()
    val toolbarInteraction = rememberGlassInteraction()
    val searchInteraction = rememberGlassInteraction()
    val luminance = rememberGlassLuminance(layer, enabled = glass, intervalMs = 1_000L)

    var isExpanded by rememberSaveable { mutableStateOf(true) }
    val inSearch = selected == Tab.Search

    LaunchedEffect(inSearch) { isExpanded = !inSearch }
    LaunchedEffect(isScrolledToTop) { if (!inSearch) isExpanded = isScrolledToTop }

    // Como en 2.2.0: el ConstraintSet se rehace cuando la barra cambia de tamaño (tras pasar de pestañas a círculo o
    // al revés), para que la animación de ConstraintLayout parta del tamaño real del contenido recién cambiado. Antes
    // se rehacía con cada cambio de posición, es decir, en cada fotograma del plegado, y la barra iba a tirones.
    var updateConstraints by remember { mutableStateOf(true) }
    var constraintSet by remember { mutableStateOf(constraintsV220(isExpanded)) }
    LaunchedEffect(isExpanded) {
        constraintSet = constraintsV220(isExpanded)
        updateConstraints = false
    }
    LaunchedEffect(updateConstraints) {
        if (updateConstraints) {
            constraintSet = constraintsV220(isExpanded)
            updateConstraints = false
        }
    }
    // Lo que entra (la cápsula o el círculo) no aparece de golpe: crece y se funde en ~250 ms mientras ConstraintLayout
    // lo lleva a su sitio. Sólo toca graphicsLayer, así que no vuelve a medir nada.
    val reduce = app.libremusic.ui.theme.LocalReduceMotion.current
    val reveal = remember { Animatable(1f) }
    var firstFold by remember { mutableStateOf(true) }
    LaunchedEffect(isExpanded) {
        if (firstFold || reduce) { firstFold = false; reveal.snapTo(1f); return@LaunchedEffect }
        reveal.snapTo(0f)
        reveal.animateTo(1f, spring(dampingRatio = 0.82f, stiffness = 420f))
    }

    ConstraintLayout(
        constraintSet = constraintSet,
        modifier =
            modifier
                .fillMaxWidth()
                .padding(WindowInsets.navigationBars.asPaddingValues())
                .padding(bottom = 8.dp),
        // Muelle sin rebote (amortiguamiento 1): arranca rápido y frena sin el corte final del tween, y si se
        // interrumpe a medias (bajar y subir enseguida) sigue desde donde está.
        animateChangesSpec = spring(dampingRatio = 1f, stiffness = Spring.StiffnessMediumLow),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
            modifier =
                Modifier
                    .then(
                        if (isExpanded) {
                            Modifier.fillMaxWidth().padding(horizontal = BarEdgePadding)
                        } else {
                            Modifier.padding(start = BarEdgePadding).wrapContentSize()
                        },
                    ).layoutId("toolbar")
                    .onSizeChanged { updateConstraints = true },
        ) {
            if (isExpanded) {
                BoxWithConstraints(
                    Modifier.weight(1f, fill = false).graphicsLayer {
                        alpha = reveal.value
                        scaleX = 0.92f + 0.08f * reveal.value
                        scaleY = scaleX
                        transformOrigin = TransformOrigin(0f, 0.5f)
                    },
                ) {
                    LiquidGlassTabBar(
                        tabs = barTabs,
                        selectedTab = barTabs.indexOf(selected),
                        backdrop = backdrop,
                        layer = layer,
                        luminance = luminance,
                        glass = glass,
                        availableWidth = maxWidth,
                        onTabSelected = { position -> onSelect(barTabs[position]) },
                        follow = follow,
                        collapsedContent = {},
                    )
                }
                Spacer(Modifier.size(SearchGap))
                Box(
                    modifier =
                        Modifier
                            .graphicsLayer {
                                alpha = reveal.value
                                scaleX = 0.7f + 0.3f * reveal.value
                                scaleY = scaleX
                            }
                            .size(SearchSize)
                            .then(
                                if (glass) {
                                    Modifier.drawInteractiveGlass(backdrop, layer, { luminance.value }, CircleShape, searchInteraction)
                                } else {
                                    Modifier.flatSurface(CircleShape)
                                },
                            ).clickable { onSelect(Tab.Search) },
                    contentAlignment = Alignment.Center,
                ) {
                    // Con color propio: sin él hereda el del tema y en el tema claro salía negro sobre el vidrio oscuro.
                    Icon(Tab.Search.icon(), contentDescription = Tab.Search.title, tint = if (inSearch) Libre.colors.accent else BarContent)
                }
            } else {
                Box(
                    modifier =
                        Modifier
                            .graphicsLayer {
                                alpha = reveal.value
                                scaleX = 0.7f + 0.3f * reveal.value
                                scaleY = scaleX
                            }
                            .size(CollapsedBarSize)
                            .then(
                                if (glass) {
                                    Modifier.drawInteractiveGlass(backdrop, layer, { luminance.value }, CircleShape, toolbarInteraction)
                                } else {
                                    Modifier.flatSurface(CircleShape)
                                },
                            ).clickable { isExpanded = true },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(selected.icon(), contentDescription = L("Desplegar barra ({0})", selected.title), tint = Libre.colors.accent)
                }
            }
        }
        player(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MiniPlayerPadding)
                .height(56.dp)
                .layoutId("miniPlayer"),
            luminance,
        )
    }
}

private fun constraintsV220(isExpanded: Boolean): ConstraintSet =
    ConstraintSet {
        val toolbar = createRefFor("toolbar")
        constrain(toolbar) {
            bottom.linkTo(parent.bottom)
            height = Dimension.wrapContent
            if (!isExpanded) {
                width = Dimension.wrapContent
                start.linkTo(parent.start)
            } else {
                width = Dimension.fillToConstraints
                start.linkTo(parent.start)
                end.linkTo(parent.end)
            }
        }
        val miniPlayer = createRefFor("miniPlayer")
        constrain(miniPlayer) {
            if (!isExpanded) {
                start.linkTo(toolbar.end)
                end.linkTo(parent.end)
                top.linkTo(toolbar.top)
                bottom.linkTo(toolbar.bottom)
                width = Dimension.fillToConstraints
            } else {
                start.linkTo(parent.start)
                end.linkTo(parent.end)
                bottom.linkTo(toolbar.top, margin = MiniPlayerGap)
                width = Dimension.matchParent
            }
        }
    }

private fun decoupledConstraints(isExpanded: Boolean): ConstraintSet =
    ConstraintSet {
        val toolbar = createRefFor("toolbar")
        constrain(toolbar) {
            bottom.linkTo(parent.bottom)
            start.linkTo(parent.start, margin = BarEdgePadding)
            if (!isExpanded) {
                // Marco fijo, nunca el tamaño del contenido: si no, salta a mitad de animación.
                width = Dimension.value(CollapsedBarSize)
                height = Dimension.value(CollapsedBarSize)
            } else {
                end.linkTo(parent.end, margin = BarEdgePadding)
                width = Dimension.wrapContent
                height = Dimension.value(BarHeight)
            }
        }
        val miniPlayer = createRefFor("miniPlayer")
        constrain(miniPlayer) {
            if (!isExpanded) {
                start.linkTo(toolbar.start, margin = CollapsedBarSize + MiniPlayerGap - MiniPlayerPadding)
                end.linkTo(parent.end)
                top.linkTo(toolbar.top)
                bottom.linkTo(toolbar.bottom)
                width = Dimension.fillToConstraints
            } else {
                start.linkTo(parent.start)
                end.linkTo(parent.end)
                bottom.linkTo(toolbar.top, margin = MiniPlayerGap)
                width = Dimension.matchParent
            }
        }
    }

@Composable
private fun MiniPlayer(
    song: Song,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    isLiked: Boolean,
    onToggleLike: () -> Unit,
    onOpen: () -> Unit,
    backdrop: LayerBackdrop,
    luminance: State<Float>,
    glass: Boolean,
    modifier: Modifier = Modifier,
) {
    val interaction = rememberGlassInteraction()
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier =
            modifier.then(
                if (glass) {
                    // Superficie ancha: el 1.12 compartido abulta demasiado, aquí se escala menos.
                    Modifier.drawInteractiveGlass(backdrop, null, { luminance.value }, shape, interaction, pressedScale = 1.04f)
                } else {
                    Modifier.flatSurface(shape)
                },
            ).clickable(onClickLabel = L("Abrir reproductor"), onClick = onOpen),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.width(8.dp))
        CoverImage(song.thumb(120), Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)))
        Column(
            Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(song.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BarContent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(song.artist, style = MaterialTheme.typography.bodySmall, color = Color(0xFFCAC4D0), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onClick = onToggleLike) {
            Icon(
                if (isLiked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                contentDescription = if (isLiked) L("Quitar de favoritos") else L("Añadir a favoritos"),
                tint = if (isLiked) Libre.colors.accent else BarContent,
            )
        }
        IconButton(onClick = onTogglePlay) {
            Icon(
                if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = if (isPlaying) L("Pausa") else L("Reproducir"),
                tint = BarContent,
            )
        }
        Spacer(Modifier.width(4.dp))
    }
}
