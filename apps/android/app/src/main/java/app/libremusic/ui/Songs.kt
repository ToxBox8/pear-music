package app.libremusic.ui

import androidx.compose.material.icons.rounded.MoreHoriz

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.HeartBroken
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.QueuePlayNext
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.data.Song
import app.libremusic.jam.JamPhase
import app.libremusic.jam.JamService
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface

// Filas y tarjetas de canción: SongRowV11, CardLabel y QuickPicks de iOS.

/** Acciones de una canción (menú contextual), en el mismo orden que SongMenuItems en iOS. */
@Composable
fun songMenu(song: Song): List<MenuEntry> {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloads by env.library.downloads.collectAsState()
    val jam by JamService.state.collectAsState()
    val fav = data.favorites.any { it.id == song.id }
    val st = downloads[song.id]
    val jamActive = jam.phase == JamPhase.Hosting || jam.phase == JamPhase.Joined
    val inJam = jam.jam?.entries?.any { it.song.id == song.id } == true
    val coverVersion by env.library.coverVersion.collectAsState()
    return buildList {
        if (jamActive) add(MenuEntry.Action(if (inJam) "Ya está en el Jam" else "Añadir al Jam", app.libremusic.ui.theme.JamIcon(), enabled = !inJam) { JamService.add(song) })
        add(MenuEntry.Action("Reproducir a continuación", Icons.Rounded.QueuePlayNext) { env.player.playNext(song) })
        add(MenuEntry.Action("Añadir a la cola", Icons.AutoMirrored.Rounded.QueueMusic) { env.player.addToQueue(song) })
        add(
            MenuEntry.Action(if (fav) "Quitar de favoritos" else "Añadir a favoritos", if (fav) Icons.Rounded.HeartBroken else Icons.Rounded.FavoriteBorder) {
                env.library.toggleFavorite(song)
            },
        )
        if (data.userPlaylists.isNotEmpty()) {
            add(
                MenuEntry.Sub(
                    "Añadir a playlist", Icons.AutoMirrored.Rounded.PlaylistAdd,
                    // Con la portada de cada playlist, para reconocerlas de un vistazo.
                    data.userPlaylists.map { p ->
                        MenuEntry.Action(
                            p.name, checked = p.songs.any { it.id == song.id },
                            image = { PlaylistCover(p, 28.dp, 6.dp, env.library.coverFile(p.id), coverVersion) },
                        ) { env.library.addToPlaylist(p.id, song) }
                    },
                ),
            )
        }
        if (st?.isDone == true) {
            add(MenuEntry.Action("Eliminar descarga", Icons.Rounded.Delete, destructive = true) { env.library.removeDownload(song) })
        } else {
            add(MenuEntry.Action("Descargar", Icons.Outlined.ArrowCircleDown, enabled = st?.isActive != true) { env.library.toggleDownload(song) })
        }
    }
}

/** Vista previa de una canción en el menú contextual: la fila, elevada sobre el fondo desenfocado. */
@Composable
fun SongPreview(song: Song) {
    val c = Libre.colors
    Row(
        Modifier.fillMaxSize().background(if (c.dark) Color(0xFF1C1C1E) else Color.White).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(Tokens.Radius.ArtworkSmall.dp))) { CoverImage(song.thumb(256), Modifier.fillMaxSize()) }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(song.title, style = Typo.callout.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(song.artist, style = Typo.subheadline, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Fila de canción: tocar reproduce; a la derecha, favorito y descarga; mantener pulsado abre el menú. */
@Composable
fun SongRow(
    song: Song,
    context: List<Song>,
    modifier: Modifier = Modifier,
    /** Resultados de búsqueda: «⋯» (menú al primer toque) en vez del botón de descarga, que está en el menú. */
    more: Boolean = false,
) {
    val c = Libre.colors
    val env = LocalEnv.current
    val player by env.player.state.collectAsState()
    val isCurrent = player.current?.id == song.id
    var menu by remember { mutableStateOf(false) }
    Row(modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
            Row(
                Modifier.fillMaxWidth().tactile(label = "${song.title}, ${song.artist}", onLongClick = { menu = true }) {
                    env.player.play(context, context.indexOfFirst { it.id == song.id }.coerceAtLeast(0))
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(52.dp).clip(RoundedCornerShape(Tokens.Radius.ArtworkSmall.dp))) {
                    CoverImage(song.thumb(256), Modifier.fillMaxSize())
                    if (isCurrent) {
                        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f)), contentAlignment = Alignment.Center) {
                            Icon(if (player.isPlaying) Icons.AutoMirrored.Rounded.VolumeUp else Icons.Rounded.Pause, null, tint = Color.White, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        song.title, style = Typo.callout.copy(fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.SemiBold),
                        color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(song.artist, style = Typo.footnote, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            ContextMenu(menu, { menu = false }, songMenu(song), preview = { SongPreview(song) })
        }
        Spacer(Modifier.width(4.dp))
        FavoriteGlyphButton(song)
        if (more) IconTap(Icons.Rounded.MoreHoriz, "Más opciones de ${song.title}", tint = c.secondaryLabel) { menu = true }
        else DownloadGlyphButton(song)
    }
}

@Composable
fun FavoriteGlyphButton(song: Song) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val fav = data.favorites.any { it.id == song.id }
    val scale by animateFloatAsState(if (fav) 1.08f else 1f, uiEaseOut(200), label = "fav")
    Box(Modifier.size(44.dp).tactile(label = if (fav) "Quitar de favoritos" else "Añadir a favoritos") { env.library.toggleFavorite(song) }, contentAlignment = Alignment.Center) {
        Icon(
            if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null,
            tint = if (fav) c.accent else c.secondaryLabel, modifier = Modifier.size(22.dp).scale(scale),
        )
    }
}

/** Estado de descarga como botón circular: flecha → anillo de progreso → check (DownloadGlyphButton). */
@Composable
fun DownloadGlyphButton(song: Song) {
    val c = Libre.colors
    val env = LocalEnv.current
    val downloads by env.library.downloads.collectAsState()
    val st = downloads[song.id]
    val done = st?.isDone == true
    val busy = st?.isActive == true
    val failed = st?.isFailed == true
    val label = when {
        done -> "Descargada"
        busy -> "Descargando"
        failed -> "Reintentar descarga"
        else -> "Descargar"
    }
    Box(
        Modifier.size(44.dp).tactile(enabled = !done && !busy, label = label) { env.library.toggleDownload(song) },
        contentAlignment = Alignment.Center,
    ) {
        when {
            done -> Icon(Icons.Rounded.CheckCircle, null, tint = c.accent, modifier = Modifier.size(28.dp))
            busy -> {
                val pct = ((st?.percent ?: 0f) / 100f).coerceIn(0.04f, 1f)
                Canvas(Modifier.size(22.dp)) {
                    val w = 2.5.dp.toPx()
                    drawCircle(c.label.copy(alpha = 0.15f), radius = size.minDimension / 2 - w / 2, style = Stroke(w))
                    drawArc(c.accent, -90f, 360f * pct, false, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w, cap = StrokeCap.Round))
                }
                Icon(Icons.Rounded.ArrowDownward, null, tint = c.accent, modifier = Modifier.size(10.dp))
            }
            failed -> Icon(Icons.Rounded.Refresh, null, tint = c.destructive, modifier = Modifier.size(28.dp))
            else -> Icon(Icons.Outlined.ArrowCircleDown, null, tint = c.secondaryLabel, modifier = Modifier.size(28.dp))
        }
    }
}

// MARK: Tarjetas del inicio ---------------------------------------------------------------------

@Composable
fun CardLabel(url: String?, title: String, subtitle: String, size: Dp = 150.dp) {
    val c = Libre.colors
    val shape = RoundedCornerShape(Tokens.Radius.ArtworkCard.dp)
    Column(Modifier.width(size)) {
        Box(
            Modifier.size(size)
                .shadowSoft(8.dp, shape)
                .clip(shape)
                .border(1.dp, Color.White.copy(alpha = 0.18f), shape),
        ) { CoverImage(url, Modifier.fillMaxSize()) }
        Spacer(Modifier.height(6.dp))
        Text(title, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitle, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Sombra suave (como `.shadow(color: .black.opacity(0.18), radius:)` de SwiftUI). */
fun Modifier.shadowSoft(elevation: Dp, shape: androidx.compose.ui.graphics.Shape, alpha: Float = 0.18f) =
    this.shadow(elevation, shape, clip = false, ambientColor = Color.Black.copy(alpha), spotColor = Color.Black.copy(alpha))

/**
 * Sombra como la de SwiftUI: una copia difuminada de la forma, desplazada, debajo del contenido. La
 * elevación de Android dibuja un anillo que se transparenta bajo carátulas translúcidas (el marcador).
 */
fun Modifier.dropShadow(shape: androidx.compose.ui.graphics.Shape, color: Color, blur: Dp, offsetY: Dp = 0.dp) = this.drawBehind {
    val outline = shape.createOutline(size, layoutDirection, this)
    val paint = androidx.compose.ui.graphics.Paint().apply {
        this.color = color
        // El radio de SwiftUI es la desviación típica del desenfoque; BlurMaskFilter usa sigma ≈ radio × 0,577.
        if (blur > 0.dp) asFrameworkPaint().maskFilter = android.graphics.BlurMaskFilter(blur.toPx() * 1.73f, android.graphics.BlurMaskFilter.Blur.NORMAL)
    }
    drawIntoCanvas { canvas ->
        canvas.save()
        canvas.translate(0f, offsetY.toPx())
        canvas.drawOutline(outline, paint)
        canvas.restore()
    }
}

/** Carrusel horizontal de canciones (Escuchado recientemente). */
@Composable
fun SongCardsRow(list: List<Song>) {
    val songs = list.distinctBy { it.id }
    val env = LocalEnv.current
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        items(songs, key = { it.id }) { s ->
            var menu by remember { mutableStateOf(false) }
            Box(Modifier.tactile(label = s.title, onLongClick = { menu = true }) { env.player.play(songs, songs.indexOf(s)) }) {
                CardLabel(s.thumb(400), s.title, s.artist)
                ContextMenu(menu, { menu = false }, songMenu(s), preview = { SongPreview(s) })
            }
        }
    }
}

/** Rejilla horizontal de 4 filas, como las «Selecciones rápidas» de YouTube Music. */
@Composable
fun QuickPicks(list: List<Song>) {
    val songs = list.distinctBy { it.id }
    val c = Libre.colors
    val env = LocalEnv.current
    val rows = songs.size.coerceIn(1, 4)
    LazyHorizontalGrid(
        rows = GridCells.Fixed(rows),
        modifier = Modifier.fillMaxWidth().height((rows * 58 + (rows - 1) * 8).dp),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(songs, key = { it.id }) { s ->
            var menu by remember { mutableStateOf(false) }
            Box {
                Row(
                    Modifier.width(280.dp).height(58.dp)
                        .themeSurface(Tokens.Radius.Row.dp, c)
                        .tactile(label = s.title, onLongClick = { menu = true }) { env.player.play(songs, songs.indexOf(s)) }
                        .padding(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CoverImage(s.thumb(120), Modifier.size(50.dp).clip(RoundedCornerShape(9.dp)))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.title, style = Typo.subheadline.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(s.artist, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                ContextMenu(menu, { menu = false }, songMenu(s), preview = { SongPreview(s) })
            }
        }
    }
}
