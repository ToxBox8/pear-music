package app.libremusic.jam

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import app.libremusic.data.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArrayList

enum class JamPhase { Idle, Hosting, Searching, Joined, Lost }

data class JamUiState(
    val phase: JamPhase = JamPhase.Idle,
    val jam: JamState? = null,
    val isHost: Boolean = false,
    val myName: String = "",
    val joiningCode: String? = null,
    /** Motivo cuando phase == Lost (texto para el usuario). */
    val reason: String? = null,
)

/**
 * Jam v2 sin servidor: el anfitrión anuncia `_lm-jam2._tcp` por NSD (mDNS) con el código en el TXT
 * y acepta conexiones TCP; los invitados le mandan lo que añaden o quitan y él reparte la lista.
 * Especificación: docs/JAM_PROTOCOL.md.
 */
object JamService {
    const val SERVICE_TYPE = "_lm-jam2._tcp."

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val random = SecureRandom()

    private val _state = MutableStateFlow(JamUiState())
    val state: StateFlow<JamUiState> = _state.asStateFlow()

    private lateinit var appContext: Context
    private val nsd: NsdManager by lazy { appContext.getSystemService(Context.NSD_SERVICE) as NsdManager }
    private var multicastLock: WifiManager.MulticastLock? = null

    // Anfitrión
    private class Peer(val socket: Socket, val writer: BufferedWriter, var name: String? = null)
    private var server: ServerSocket? = null
    private val peers = CopyOnWriteArrayList<Peer>()
    private var registration: NsdManager.RegistrationListener? = null

    // Invitado
    private var hostSocket: Socket? = null
    private var hostWriter: BufferedWriter? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var searchTimeout: Job? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun makeCode(): String = String(CharArray(JamLink.CODE_LENGTH) { JamLink.ALPHABET[random.nextInt(JamLink.ALPHABET.length)] })

    // region Anfitrión

    fun host(jamName: String, myName: String) {
        leave()
        val code = makeCode()
        val name = jamName.trim().ifEmpty { "Jam de $myName" }.take(60)
        val jam = JamState(name = name, code = code, host = myName, members = listOf(myName), entries = emptyList())
        _state.value = JamUiState(JamPhase.Hosting, jam, isHost = true, myName = myName)
        scope.launch {
            try {
                val socket = ServerSocket(0)
                server = socket
                register(name, code, myName, socket.localPort)
                while (!socket.isClosed) {
                    val client = socket.accept()
                    scope.launch { servePeer(client) }
                }
            } catch (e: Exception) {
                if (server != null && _state.value.phase == JamPhase.Hosting) lose("No se pudo crear el Jam en esta red.")
            }
        }
    }

    private fun register(name: String, code: String, host: String, port: Int) {
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = SERVICE_TYPE
            this.port = port
            setAttribute("v", JAM_PROTOCOL_VERSION.toString())
            setAttribute("code", code)
            setAttribute("host", host.take(40))
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) = Unit
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) =
                lose("No se pudo anunciar el Jam en la Wi-Fi ($errorCode).")
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
        }
        registration = listener
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun servePeer(socket: Socket) {
        val peer = Peer(socket, BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)))
        peers += peer
        try {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            while (true) {
                val line = reader.readLine() ?: break
                val jam = _state.value.jam ?: break
                when (val msg = JamMessage.decode(line)) {
                    is JamMessage.Hello -> {
                        if (msg.code != jam.code) {
                            send(peer, JamMessage.Error("bad_code"))
                            break
                        }
                        if (jam.members.size >= JamRules.MAX_PEOPLE) {
                            send(peer, JamMessage.Error("full"))
                            break
                        }
                        val name = JamRules.uniqueName(jam, msg.name)
                        peer.name = name
                        updateHostJam { it.copy(members = it.members + name) }
                    }
                    is JamMessage.Add -> if (peer.name != null) updateHostJam { JamRules.add(it, msg.entry) }
                    is JamMessage.Remove -> if (peer.name != null) updateHostJam { JamRules.remove(it, msg.songId) }
                    else -> Unit
                }
            }
        } catch (_: Exception) {
            // conexión perdida
        } finally {
            peers -= peer
            runCatching { socket.close() }
            val name = peer.name
            if (name != null && _state.value.phase == JamPhase.Hosting) {
                updateHostJam { it.copy(members = it.members - name) }
            }
        }
    }

    @Synchronized
    private fun updateHostJam(change: (JamState) -> JamState) {
        val current = _state.value
        val jam = current.jam ?: return
        val next = change(jam)
        _state.value = current.copy(jam = next)
        broadcast(JamMessage.State(next))
    }

    private fun broadcast(msg: JamMessage) {
        peers.filter { it.name != null }.forEach { send(it, msg) }
    }

    private fun send(peer: Peer, msg: JamMessage) {
        runCatching {
            synchronized(peer.writer) {
                peer.writer.write(msg.encode())
                peer.writer.write("\n")
                peer.writer.flush()
            }
        }.onFailure { runCatching { peer.socket.close() } }
    }

    // endregion

    // region Invitado

    fun join(rawCode: String, myName: String) {
        val code = JamLink.normalize(rawCode)
        if (code.length != JamLink.CODE_LENGTH) return
        leave()
        _state.value = JamUiState(JamPhase.Searching, myName = myName, joiningCode = code)
        acquireMulticast()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) =
                lose("No se pudo buscar en la Wi-Fi ($errorCode).")
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (_state.value.phase == JamPhase.Searching) resolve(serviceInfo, code, myName, attempt = 0)
            }
        }
        discovery = listener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        searchTimeout = scope.launch {
            delay(30_000)
            if (_state.value.phase == JamPhase.Searching) {
                lose("No se encontró ningún Jam con el código $code. Comprobad que estáis en la misma Wi-Fi.")
            }
        }
    }

    @Suppress("DEPRECATION") // resolveService sigue siendo la vía compatible con Android 8+
    private fun resolve(info: NsdServiceInfo, code: String, myName: String, attempt: Int) {
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                // Android solo resuelve uno a la vez: reintento breve.
                if (errorCode == NsdManager.FAILURE_ALREADY_ACTIVE && attempt < 5) {
                    scope.launch {
                        delay(300L * (attempt + 1))
                        if (_state.value.phase == JamPhase.Searching) resolve(info, code, myName, attempt + 1)
                    }
                }
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                val txtCode = serviceInfo.attributes["code"]?.let { String(it, Charsets.UTF_8) }
                val host = serviceInfo.host ?: return
                if (txtCode != code || _state.value.phase != JamPhase.Searching) return
                stopDiscovery()
                scope.launch { connect(host.hostAddress ?: return@launch, serviceInfo.port, code, myName) }
            }
        })
    }

    private fun connect(address: String, port: Int, code: String, myName: String) {
        try {
            val socket = Socket()
            socket.connect(InetSocketAddress(address, port), 10_000)
            hostSocket = socket
            val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
            hostWriter = writer
            sendToHost(JamMessage.Hello(myName, code))
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            while (true) {
                val line = reader.readLine() ?: break
                when (val msg = JamMessage.decode(line)) {
                    is JamMessage.State -> _state.value = _state.value.copy(
                        phase = JamPhase.Joined,
                        jam = msg.state,
                        // El anfitrión puede haber cambiado nuestro nombre si estaba repetido.
                        myName = msg.state.members.lastOrNull { it == myName || it.startsWith("$myName (") } ?: myName,
                    )
                    JamMessage.Ended -> {
                        lose("El anfitrión ha terminado el Jam.")
                        return
                    }
                    is JamMessage.Error -> {
                        lose(if (msg.reason == "full") "El Jam está lleno." else "El código no es válido.")
                        return
                    }
                    else -> Unit
                }
            }
            if (_state.value.phase == JamPhase.Joined) lose("Se ha perdido la conexión con el anfitrión.")
        } catch (_: Exception) {
            val phase = _state.value.phase
            if (phase == JamPhase.Joined || phase == JamPhase.Searching) lose("No se pudo conectar con el Jam.")
        } finally {
            runCatching { hostSocket?.close() }
            hostSocket = null
            hostWriter = null
        }
    }

    private fun sendToHost(msg: JamMessage) {
        val writer = hostWriter ?: return
        scope.launch {
            runCatching {
                synchronized(writer) {
                    writer.write(msg.encode())
                    writer.write("\n")
                    writer.flush()
                }
            }
        }
    }

    // endregion

    // region Acciones comunes

    fun add(song: Song) {
        val s = _state.value
        val entry = JamEntry(song, s.myName)
        when (s.phase) {
            JamPhase.Hosting -> scope.launch { updateHostJam { JamRules.add(it, entry) } }
            JamPhase.Joined -> sendToHost(JamMessage.Add(entry))
            else -> Unit
        }
    }

    fun remove(songId: String) {
        when (_state.value.phase) {
            JamPhase.Hosting -> scope.launch { updateHostJam { JamRules.remove(it, songId) } }
            JamPhase.Joined -> sendToHost(JamMessage.Remove(songId))
            else -> Unit
        }
    }

    val isActive: Boolean get() = _state.value.phase.let { it == JamPhase.Hosting || it == JamPhase.Joined }

    /** Sale del Jam (o lo termina, si eres el anfitrión). La lista se conserva en Lost para guardarla. */
    fun leave() {
        val wasHost = _state.value.phase == JamPhase.Hosting
        if (wasHost) {
            val toNotify = peers.toList()
            scope.launch {
                toNotify.forEach { send(it, JamMessage.Ended) }
                toNotify.forEach { runCatching { it.socket.close() } }
            }
        }
        peers.clear()
        registration?.let { runCatching { nsd.unregisterService(it) } }
        registration = null
        runCatching { server?.close() }
        server = null
        stopDiscovery()
        runCatching { hostSocket?.close() }
        hostSocket = null
        hostWriter = null
        _state.value = JamUiState(myName = _state.value.myName)
    }

    /** Cierra la conexión pero conserva la lista para poder guardarla como playlist. */
    private fun lose(reason: String) {
        val jam = _state.value.jam
        val myName = _state.value.myName
        leave()
        _state.value = JamUiState(JamPhase.Lost, jam, myName = myName, reason = reason)
    }

    fun dismiss() {
        _state.value = JamUiState(myName = _state.value.myName)
    }

    private fun stopDiscovery() {
        searchTimeout?.cancel()
        searchTimeout = null
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discovery = null
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    /** Algunos móviles filtran el multicast de mDNS si nadie lo pide. */
    private fun acquireMulticast() {
        val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        multicastLock = wifi.createMulticastLock("libremusic-jam").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    // endregion
}
