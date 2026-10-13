package app.libremusic.jam

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
) {
    fun toJson(): JSONObject = JSONObject()
        .put("name", name)
        .put("code", code)
        .put("host", host)
        .put("members", JSONArray(members))
        .put("entries", JSONArray().apply { entries.forEach { put(it.toJson()) } })

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
                else -> null
            }
        }.getOrNull()
    }
}

/** Reglas del anfitrión, separadas de la red para poder probarlas. */
object JamRules {
    const val MAX_PEOPLE = 16

    fun add(state: JamState, entry: JamEntry): JamState =
        if (state.entries.any { it.song.id == entry.song.id }) state else state.copy(entries = state.entries + entry)

    fun remove(state: JamState, songId: String): JamState =
        state.copy(entries = state.entries.filterNot { it.song.id == songId })

    /** Nombre único dentro del Jam: «Ana», «Ana (2)»… */
    fun uniqueName(state: JamState, wanted: String): String {
        val base = wanted.trim().ifEmpty { "Invitado" }
        if (base !in state.members) return base
        var i = 2
        while ("$base ($i)" in state.members) i++
        return "$base ($i)"
    }
}
