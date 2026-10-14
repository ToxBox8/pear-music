package app.libremusic.data

import android.media.MediaCodecList
import android.media.MediaFormat

/** ¿Tiene el móvil decodificador de Opus? Android lo trae desde la 5.0, pero algún fabricante podría quitarlo. */
object OpusSupport {
    val available: Boolean by lazy {
        runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                !info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_AUDIO_OPUS, ignoreCase = true) }
            }
        }.getOrDefault(false)
    }
}
