package app.libremusic.jam


import app.libremusic.L
import app.libremusic.data.Song
import org.json.JSONArray
import org.json.JSONObject

/** Mensajes del Jam v2. Especificación: docs/JAM_PROTOCOL.md (JSON, uno por línea). */
const val JAM_PROTOCOL_VERSION = 2

data class JamEntry(val song: Song, val by: String) {
    fun toJson(): JSONObject = JSONObject().put("song", song.toJson()).put("by", by)

    companion object {
        fun fromJson(o: JSONObject) = JamEntry(Song.fromJson(o.getJSONObject("song")), o.optString("by"))
    }
}

data class JamState(
    val name: String,
    val code: String,
    val host: String,
    val members: List<String>,
    val entries: List<JamEntry>,
    /** v2.1 (x.1.1): «altavoz» (suena sólo en el anfitrión) o «todos» (cada uno en su móvil, a la vez). */
    val mode: String = JamSync.SPEAKER,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("name", name)
        .put("code", code)
        .put("host", host)
        .put("members", JSONArray(members))
        .put("entries", JSONArray().apply { entries.forEach { put(it.toJson()) } })
        .put("mode", mode)

    companion object {
        fun fromJson(o: JSONObject): JamState {
            val members = o.optJSONArray("members")
            val entries = o.optJSONArray("entries")
            return JamState(
                name = o.optString("name"),
                code = o.optString("code"),
                host = o.optString("host"),
                members = (0 until (members?.length() ?: 0)).map { members!!.optString(it) },
                entries = (0 until (entries?.length() ?: 0)).mapNotNull { i ->
                    entries!!.optJSONObject(i)?.let { runCatching { JamEntry.fromJson(it) }.getOrNull() }
                },
                // Un anfitrión antiguo no lo manda: un altavoz, como siempre.
                mode = o.optString("mode").takeIf { it == JamSync.EVERYONE } ?: JamSync.SPEAKER,
            )
        }
    }
}

sealed class JamMessage {
    data class Hello(val name: String, val code: String) : JamMessage()
    data class State(val state: JamState) : JamMessage()
    data class Add(val entry: JamEntry) : JamMessage()
    data class Remove(val songId: String) : JamMessage()
    data object Ended : JamMessage()
    data class Error(val reason: String) : JamMessage()
    /**
     * v2.1: lo que suena en el anfitrión, con su hora ([atMs], su reloj). Sólo en modo «todos». [song] null = nada.
     * Cada móvil resuelve su propio audio: nunca se transmite sonido.
     */
    data class Play(val song: Song?, val positionMs: Long, val atMs: Long, val playing: Boolean) : JamMessage()
    /** v2.1: medir la diferencia de reloj con el anfitrión (como NTP): el invitado manda su hora y el anfitrión la suya. */
    data class Ping(val t0: Long) : JamMessage()
    data class Pong(val t0: Long, val th: Long) : JamMessage()

    /** Una línea JSON lista para enviar (sin el salto de línea). */
    fun encode(): String {
        val o = JSONObject().put("v", JAM_PROTOCOL_VERSION)
        when (this) {
            is Hello -> o.put("type", "hello").put("name", name).put("code", code)
            is State -> o.put("type", "state").put("state", state.toJson())
            is Add -> o.put("type", "add").put("entry", entry.toJson())
            is Remove -> o.put("type", "remove").put("songID", songId)
            Ended -> o.put("type", "ended")
            is Error -> o.put("type", "error").put("reason", reason)
            is Play -> o.put("type", "play").put("positionMs", positionMs).put("atMs", atMs).put("playing", playing)
                .apply { song?.let { put("song", it.toJson()) } }
            is Ping -> o.put("type", "ping").put("t0", t0)
            is Pong -> o.put("type", "pong").put("t0", t0).put("th", th)
        }
        return o.toString()
    }

    companion object {
        /** null si la línea no es un mensaje válido (se ignora, para tolerar versiones futuras). */
        fun decode(line: String): JamMessage? = runCatching {
            val o = JSONObject(line)
            when (o.optString("type")) {
                "hello" -> Hello(o.getString("name"), o.getString("code"))
                "state" -> State(JamState.fromJson(o.getJSONObject("state")))
                "add" -> Add(JamEntry.fromJson(o.getJSONObject("entry")))
                "remove" -> Remove(o.getString("songID"))
                "ended" -> Ended
                "error" -> Error(o.optString("reason"))
                "play" -> Play(o.optJSONObject("song")?.let { Song.fromJson(it) }, o.getLong("positionMs"), o.getLong("atMs"), o.optBoolean("playing"))
                "ping" -> Ping(o.getLong("t0"))
                "pong" -> Pong(o.getLong("t0"), o.getLong("th"))
                else -> null
            }
        }.getOrNull()
    }
}

/**
 * «Cada uno en su móvil» (v2.1, 2.6 de x.1.1): reloj y correcciones, sin red para poder probarlo. Igual que
 * `JamSync` en iOS.
 */
object JamSync {
    const val SPEAKER = "altavoz"
    const val EVERYONE = "todos"
    /** Más de esto, salto; entre [NUDGE_MS] y esto, se ajusta la velocidad unos segundos (sin saltos audibles). */
    const val SEEK_MS = 250L
    const val NUDGE_MS = 60L
    const val FASTER = 1.03f
    const val SLOWER = 0.97f
    /** Pings al entrar y luego cada tanto. */
    const val FIRST_PINGS = 4
    const val PING_EVERY_MS = 30_000L

    /** Una medida: ida y vuelta y diferencia de reloj (hora del anfitrión − la nuestra). */
    data class Sample(val rtt: Long, val offset: Long)

    fun sample(t0: Long, th: Long, t1: Long) = Sample(rtt = t1 - t0, offset = th - (t0 + t1) / 2)

    /** Diferencia de reloj: la media de las dos medidas más rápidas (las más fiables). null sin medidas. */
    fun offset(samples: List<Sample>): Long? =
        samples.sortedBy { it.rtt }.take(2).takeIf { it.isNotEmpty() }?.let { best -> best.sumOf { it.offset } / best.size }

    /** Dónde debería ir la canción ahora en este móvil. */
    fun expected(play: JamMessage.Play, localNow: Long, offset: Long): Long =
        if (play.playing) play.positionMs + (localNow + offset - play.atMs) else play.positionMs

    sealed class Correction {
        data object None : Correction()
        data class Seek(val toMs: Long) : Correction()
        data class Speed(val rate: Float) : Correction()
    }

    /** Qué hacer con un desfase: saltar, acelerar o frenar un poco, o nada (y velocidad normal). */
    fun correct(expectedMs: Long, actualMs: Long): Correction {
        val drift = expectedMs - actualMs
        return when {
            kotlin.math.abs(drift) > SEEK_MS -> Correction.Seek(expectedMs)
            kotlin.math.abs(drift) >= NUDGE_MS -> Correction.Speed(if (drift > 0) FASTER else SLOWER)
            else -> Correction.None
        }
    }
}

/** Reglas del anfitrión, separadas de la red para poder probarlas. */
object JamRules {
    const val MAX_PEOPLE = 16
    /** Topes contra abusos desde la red local (mismos que `JamV2` en iOS). */
    const val MAX_CONNECTIONS = 24
    const val MAX_LINE_CHARS = 256 * 1024
    const val MAX_ENTRIES = 500
    const val MAX_TEXT = 300

    /** Una canción con datos razonables (un invitado malicioso podría mandar textos enormes). */
    fun acceptable(e: JamEntry): Boolean =
        e.song.id.isNotEmpty() && e.song.id.length <= 64 && e.song.title.length <= MAX_TEXT &&
            e.song.artist.length <= MAX_TEXT && e.by.length <= MAX_TEXT

    fun add(state: JamState, entry: JamEntry): JamState =
        if (!acceptable(entry) || state.entries.size >= MAX_ENTRIES || state.entries.any { it.song.id == entry.song.id }) state
        else state.copy(entries = state.entries + entry)

    /** Un invitado sólo quita lo que añadió él (como en iOS); [by] null = el anfitrión, que puede quitar todo. */
    fun remove(state: JamState, songId: String, by: String? = null): JamState =
        state.copy(entries = state.entries.filterNot { it.song.id == songId && (by == null || it.by == by) })

    /** Lee una línea sin pasar de [max] caracteres; null al acabar la conexión. Una línea sin fin corta la conexión. */
    fun readLine(reader: java.io.Reader, max: Int = MAX_LINE_CHARS): String? {
        val sb = StringBuilder()
        while (true) {
            val c = reader.read()
            if (c == -1) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString()
            if (sb.length >= max) throw java.io.IOException(L("Línea demasiado larga"))
            sb.append(c.toChar())
        }
    }

    /** Nombre único dentro del Jam: «Ana», «Ana (2)»… */
    fun uniqueName(state: JamState, wanted: String): String {
        val base = wanted.trim().take(24).ifEmpty { "Invitado" }
        if (base !in state.members) return base
        var i = 2
        while ("$base ($i)" in state.members) i++
        return "$base ($i)"
    }
}
