package app.libremusic.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.libremusic.L
import app.libremusic.data.Playlist
import app.libremusic.data.PlaylistShare
import app.libremusic.data.YTClient
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** QR en blanco y negro (corrección baja: el enlace de una playlist es largo y así los cuadros son más grandes). */
fun qrBitmap(text: String, size: Int = 720): Bitmap {
    val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L, EncodeHintType.MARGIN to 1)
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
    val pixels = IntArray(size * size) { i -> if (m[i % size, i / size]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt() }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}

/**
 * «Compartir con QR» de una playlist (0.6 de x.1.1): el QR, cuántas canciones viajan y «Compartir enlace». Una foto
 * propia no viaja (no cabe); se dice. Igual que `SharePlaylistSheet` en iOS.
 */
@Composable
fun SharePlaylistContent(p: Playlist, hasPhoto: Boolean) {
    val c = Libre.colors
    val context = LocalContext.current
    val link = remember(p) { PlaylistShare.link(p.name, p.songs.map { it.id }, p.icon, p.tint) }
    val qr = remember(link) { link?.let { qrBitmap(it).asImageBitmap() } }
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(p.name, style = Typo.title2, color = c.label, textAlign = TextAlign.Center)
        if (qr == null) {
            Text(
                if (p.songs.isEmpty()) L("Esta playlist está vacía.") else L("Tiene demasiadas canciones para un QR (como mucho {0}).", PlaylistShare.MAX_SONGS),
                style = Typo.body, color = c.secondaryLabel, textAlign = TextAlign.Center,
            )
            return@Column
        }
        // Siempre sobre blanco, también en modo oscuro: así lo lee cualquier cámara.
        Box(Modifier.background(Color.White, RoundedCornerShape(20.dp)).padding(14.dp)) {
            Image(qr, L("Código QR de {0}", p.name), Modifier.size(280.dp))
        }
        Text(
            L("Escanéalo con la cámara de otro móvil con Pear Music. Viajan el nombre, las {0} canciones y su orden.", p.songs.size) +
                if (hasPhoto) L(" La foto de la portada no cabe en el QR.") else "",
            style = Typo.footnote, color = c.secondaryLabel, textAlign = TextAlign.Center,
        )
        PillButton(L("Compartir enlace"), Icons.Rounded.Share, prominent = false, modifier = Modifier.fillMaxWidth()) {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
            context.startActivity(Intent.createChooser(send, null))
        }
    }
}

/**
 * Al abrir un enlace de playlist (0.6 de x.1.1): vista previa y «Añadir a la biblioteca». Los títulos se piden a
 * YouTube Music en ese momento (el QR sólo lleva los ids).
 */
@Composable
fun SharedPlaylistContent(payload: PlaylistShare.Payload, onDone: (Playlist?) -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(L("Playlist compartida"), style = Typo.caption.copy(), color = c.secondaryLabel)
        Text(payload.name.ifBlank { L("Sin nombre") }, style = Typo.title2, color = c.label, textAlign = TextAlign.Center)
        Text(songCount(payload.ids.size), style = Typo.body, color = c.secondaryLabel)
        error?.let { Text(it, style = Typo.footnote, color = c.destructive, textAlign = TextAlign.Center) }
        Spacer(Modifier.height(4.dp))
        PillButton(if (busy) L("Añadiendo…") else L("Añadir a la biblioteca"), Icons.Rounded.Download, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = !busy) {
            busy = true
            error = null
            scope.launch {
                val songs = withContext(Dispatchers.IO) { runCatching { YTClient.songs(payload.ids) }.getOrDefault(emptyList()) }
                busy = false
                if (songs.isEmpty()) { error = L("No se pudieron cargar las canciones. Revisa la conexión y vuelve a intentarlo."); return@launch }
                val p = env.library.importShared(payload.name, songs, payload.icon, payload.tint)
                if (songs.size < payload.ids.size) env.app.toast = L("{0} canciones no están en YouTube Music y se han quedado fuera.", payload.ids.size - songs.size)
                onDone(p)
            }
        }
        Row { Text(L("Ahora no"), style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = L("Ahora no")) { onDone(null) }.padding(10.dp)) }
    }
}
