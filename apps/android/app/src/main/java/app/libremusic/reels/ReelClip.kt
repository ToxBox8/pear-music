package app.libremusic.reels

/** Fragmento de 30 s de cada canción en Descubrir (mismas reglas que iOS). */
object ReelClip {
    const val CLIP_MS = 30_000L

    /** Hacia el 35 % suele estar el estribillo; las canciones cortas empiezan desde el principio. */
    fun start(durationMs: Long): Long =
        if (durationMs > CLIP_MS * 2) (durationMs * 0.35).toLong() else 0L

    fun end(start: Long, durationMs: Long): Long =
        if (durationMs > 0) minOf(start + CLIP_MS, durationMs - 400) else start + CLIP_MS
}
