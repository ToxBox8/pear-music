package app.libremusic.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class YTClientTest {

    private fun listItem(videoId: String, title: String, subtitleRuns: List<String>, viaWatchEndpoint: Boolean = false): JSONObject {
        fun runs(texts: List<String>) = JSONObject().put(
            "runs",
            JSONArray(texts.map { JSONObject().put("text", it) }),
        )
        fun column(texts: List<String>) = JSONObject().put(
            "musicResponsiveListItemFlexColumnRenderer",
            JSONObject().put("text", runs(texts)),
        )
        val renderer = JSONObject()
            .put("flexColumns", JSONArray(listOf(column(listOf(title)), column(subtitleRuns))))
            .put(
                "thumbnail",
                JSONObject().put(
                    "musicThumbnailRenderer",
                    JSONObject().put(
                        "thumbnail",
                        JSONObject().put(
                            "thumbnails",
                            JSONArray(
                                listOf(
                                    JSONObject().put("url", "https://lh3.example/a=w60-h60-l90-rj"),
                                    JSONObject().put("url", "https://lh3.example/a=w120-h120-l90-rj"),
                                ),
                            ),
                        ),
                    ),
                ),
            )
        if (viaWatchEndpoint) {
            renderer.put(
                "overlay",
                JSONObject().put("playNavigationEndpoint", JSONObject().put("watchEndpoint", JSONObject().put("videoId", videoId))),
            )
        } else {
            renderer.put("playlistItemData", JSONObject().put("videoId", videoId))
        }
        return JSONObject().put("musicResponsiveListItemRenderer", renderer)
    }

    @Test
    fun parsesSongsLikeTheIosClient() {
        val response = JSONObject().put(
            "contents",
            JSONArray(
                listOf(
                    listItem("abc", "Golden Hour", listOf("Canción", " • ", "JVKE", " • ", "this is what ____ feels like", " • ", "3:29")),
                    listItem("abc", "Duplicada", listOf("Canción", " • ", "Otro")),
                    listItem("def", "Midnight City", listOf("Vídeo", " • ", "M83", " y ", "Otro", " • ", "4:03"), viaWatchEndpoint = true),
                ),
            ),
        )

        val songs = YTClient.parseSongs(response)

        assertEquals(2, songs.size)
        assertEquals(Song("abc", "Golden Hour", "JVKE", "https://lh3.example/a=w120-h120-l90-rj"), songs[0])
        assertEquals("def", songs[1].id)
        assertEquals("M83 y Otro", songs[1].artist)
    }

    @Test
    fun picksOpusFirstThenAacWithDirectUrl() {
        val formats = JSONArray(
            listOf(
                JSONObject().put("mimeType", "audio/mp4; codecs=\"mp4a.40.5\"").put("bitrate", 48_000).put("url", "low"),
                JSONObject().put("mimeType", "audio/mp4; codecs=\"mp4a.40.2\"").put("bitrate", 130_000).put("url", "high"),
                JSONObject().put("mimeType", "audio/webm; codecs=\"opus\"").put("bitrate", 160_000).put("url", "opus"),
                JSONObject().put("mimeType", "audio/mp4").put("bitrate", 256_000), // cifrada, sin url
            ),
        )
        assertEquals("opus", YTClient.bestAudioUrl(formats, opus = true))
        assertEquals("high", YTClient.bestAudioUrl(formats, opus = false))
        assertEquals("low", YTClient.bestAudioUrl(formats, lowest = true, opus = false))
        assertNull(YTClient.bestAudioUrl(JSONArray()))
        assertNull(YTClient.bestAudioUrl(null))
    }

    @Test
    fun resizesThumbnails() {
        val song = Song("x", "t", "a", "https://lh3.example/a=w120-h120-l90-rj")
        assertEquals("https://lh3.example/a=w544-h544-l90-rj", song.thumb(544))
        assertEquals("https://i.ytimg.com/vi/x/hq.jpg", song.copy(thumbnail = "https://i.ytimg.com/vi/x/hq.jpg").thumb(544))
        assertNull(song.copy(thumbnail = null).thumb(544))
    }

    @Test
    fun songJsonRoundTrip() {
        val song = Song("x", "Título", "Artista", null)
        assertEquals(song, Song.fromJson(song.toJson()))
    }
}
