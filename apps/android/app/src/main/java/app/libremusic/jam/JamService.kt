package app.libremusic.jam


import app.libremusic.L
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
    /** Anfitrión: su dirección en la Wi-Fi («IP:puerto») para el QR, que así entra al momento (Fase 3.2). */
    val direct: String? = null,
    /** Invitado en modo «todos»: si suena también en este móvil (se puede quitar, p. ej. si está al lado del altavoz). */
    val listenHere: Boolean = true,
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
    /** Direcciones directas vistas en enlaces o QR, por código (Fase 3.2). */
    private val directHints = java.util.concurrent.ConcurrentHashMap<String, Pair<String, Int>>()
    /** Gana el primer camino que conecta (directo o búsqueda en la Wi-Fi). */
    private val connecting = java.util.concurrent.atomic.AtomicBoolean(false)
    /** Android resuelve un anuncio a la vez: cola en vez de reintentos que podían perder el bueno. */
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var joinStartedAt = 0L

    // «Cada uno en su móvil» (v2.1, 2.6 de x.1.1)
    /** Invitado: lo último que suena en el anfitrión. La raíz de la app lo sigue con el reproductor. */
    private val _remotePlay = MutableStateFlow<JamMessage.Play?>(null)
    val remotePlay: StateFlow<JamMessage.Play?> = _remotePlay.asStateFlow()
    private val clockSamples = CopyOnWriteArrayList<JamSync.Sample>()
    private var pinger: Job? = null
    /** Diferencia de reloj con el anfitrión (su hora − la nuestra), o null si aún no se ha medido. */
    val clockOffset: Long? get() = JamSync.offset(clockSamples.toList())
    private fun now() = System.currentTimeMillis()
    /** Anfitrión: lo último que mandó, para quien entra a mitad de canción. */
    @Volatile private var lastPlay: JamMessage.Play? = null

    /** Recuerda la dirección directa de un enlace o QR (`libremusic://jam/CÓDIGO?h=IP:puerto`). */
    fun rememberLink(text: String?) {
        val code = JamLink.codeFrom(text) ?: return
        JamLink.directFrom(text)?.let { directHints[code] = it }
    }

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
                localIpv4()?.let { ip -> _state.value = _state.value.copy(direct = "$ip:${socket.localPort}") }
                while (!socket.isClosed) {
                    val client = socket.accept()
                    // Tope de conexiones: más que el máximo del Jam sólo puede ser alguien abusando de la red.
                    if (peers.size >= JamRules.MAX_CONNECTIONS) { runCatching { client.close() }; continue }
                    scope.launch { servePeer(client) }
                }
            } catch (e: Exception) {
                if (server != null && _state.value.phase == JamPhase.Hosting) lose(L("No se pudo crear el Jam en esta red."))
            }
        }
    }

    private fun register(name: String, code: String, host: String, port: Int) {
        val info = NsdServiceInfo().apply {
            // El código en el nombre: los invitados resuelven primero el que coincide (Fase 3.2).
            serviceName = "${name.take(48)} · $code"
            serviceType = SERVICE_TYPE
            this.port = port
            setAttribute("v", JAM_PROTOCOL_VERSION.toString())
            setAttribute("code", code)
            setAttribute("host", host.take(40))
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) = Unit
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) =
                lose(L("No se pudo anunciar el Jam en la Wi-Fi ({0}).", errorCode))
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
            // Quien no se presenta con el código en 15 s, fuera; después ya puede estar callado lo que quiera.
            socket.soTimeout = 15_000
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            while (true) {
                val line = JamRules.readLine(reader) ?: break
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
                        socket.soTimeout = 0
                        updateHostJam { it.copy(members = it.members + name) }
                        if (_state.value.jam?.mode == JamSync.EVERYONE) lastPlay?.let { send(peer, it) }
                    }
                    is JamMessage.Add -> if (peer.name != null) updateHostJam { JamRules.add(it, msg.entry) }
                    is JamMessage.Ping -> if (peer.name != null) send(peer, JamMessage.Pong(msg.t0, now()))
                    is JamMessage.Remove -> peer.name?.let { who -> updateHostJam { JamRules.remove(it, msg.songId, who) } }
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
        joinStartedAt = android.os.SystemClock.elapsedRealtime()
        connecting.set(false)
        synchronized(resolveQueue) { resolveQueue.clear(); resolving = false }
        acquireMulticast()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) =
                lose(L("No se pudo buscar en la Wi-Fi ({0}).", errorCode))
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (_state.value.phase != JamPhase.Searching) return
                synchronized(resolveQueue) {
                    // El que lleva el código en el nombre, delante.
                    if (serviceInfo.serviceName.endsWith(" · $code")) resolveQueue.addFirst(serviceInfo) else resolveQueue.addLast(serviceInfo)
                }
                resolveNext(code, myName)
            }
        }
        discovery = listener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        // Atajo del QR: conexión directa a la vez que la búsqueda en la Wi-Fi; gana el primero.
        directHints[code]?.let { (ip, port) -> scope.launch { connect(ip, port, code, myName, direct = true) } }
        searchTimeout = scope.launch {
            delay(30_000)
            if (_state.value.phase == JamPhase.Searching) {
                lose(L("No se encontró ningún Jam con el código {0}. Comprobad que estáis en la misma Wi-Fi.", code))
            }
        }
    }

    /** Resuelve el siguiente anuncio de la cola (uno a la vez, como exige Android). */
    @Suppress("DEPRECATION") // resolveService sigue siendo la vía compatible con Android 8+
    private fun resolveNext(code: String, myName: String) {
        val info = synchronized(resolveQueue) {
            if (resolving || _state.value.phase != JamPhase.Searching) return
            resolveQueue.removeFirstOrNull()?.also { resolving = true } ?: return
        }
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                synchronized(resolveQueue) {
                    resolving = false
                    // Otro resolve seguía activo (de otra app): se vuelve a poner a la cola, al final.
                    if (errorCode == NsdManager.FAILURE_ALREADY_ACTIVE) resolveQueue.addLast(info)
                }
                scope.launch { delay(150); resolveNext(code, myName) }
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                synchronized(resolveQueue) { resolving = false }
                val txtCode = serviceInfo.attributes["code"]?.let { String(it, Charsets.UTF_8) }
                val host = serviceInfo.host?.hostAddress
                if (txtCode != code || host == null || _state.value.phase != JamPhase.Searching) {
                    resolveNext(code, myName)
                    return
                }
                scope.launch { connect(host, serviceInfo.port, code, myName) }
            }
        })
    }

    /** La IPv4 privada de este móvil en la Wi-Fi (para el QR), o null. */
    private fun localIpv4(): String? = runCatching {
        java.net.NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .sortedByDescending { it.name.startsWith("wlan") }
            .flatMap { it.inetAddresses.toList() }
            .firstOrNull { it is java.net.Inet4Address && it.isSiteLocalAddress }?.hostAddress
    }.getOrNull()

    private fun connect(address: String, port: Int, code: String, myName: String, direct: Boolean = false) {
        if (connecting.get()) return
        var owned = false
        try {
            val socket = Socket()
            // Directo (QR) con poco margen: si la IP ya no vale, la búsqueda en la Wi-Fi sigue por su lado.
            socket.connect(InetSocketAddress(address, port), if (direct) 2_000 else 10_000)
            // Gana el primero que conecta; el otro se cierra sin ruido.
            if (!connecting.compareAndSet(false, true)) { runCatching { socket.close() }; return }
            owned = true
            stopDiscovery()
            app.libremusic.data.Logs.i("LMJam", "join_ms=${android.os.SystemClock.elapsedRealtime() - joinStartedAt} via=${if (direct) "directo" else "wifi"}")
            hostSocket = socket
            val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
            hostWriter = writer
            sendToHost(JamMessage.Hello(myName, code))
            // Reloj: unas medidas seguidas al entrar y luego una cada 30 s (sólo cuentan las más rápidas).
            clockSamples.clear()
            pinger?.cancel()
            pinger = scope.launch {
                repeat(JamSync.FIRST_PINGS) { sendToHost(JamMessage.Ping(now())); kotlinx.coroutines.delay(300) }
                while (true) { kotlinx.coroutines.delay(JamSync.PING_EVERY_MS); sendToHost(JamMessage.Ping(now())) }
            }
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            while (true) {
                val line = JamRules.readLine(reader) ?: break
                when (val msg = JamMessage.decode(line)) {
                    is JamMessage.State -> _state.value = _state.value.copy(
                        phase = JamPhase.Joined,
                        jam = msg.state,
                        // El anfitrión puede haber cambiado nuestro nombre si estaba repetido.
                        myName = msg.state.members.lastOrNull { it == myName || it.startsWith("$myName (") } ?: myName,
                    )
                    is JamMessage.Play -> _remotePlay.value = msg
                    is JamMessage.Pong -> {
                        clockSamples += JamSync.sample(msg.t0, msg.th, now())
                        if (clockSamples.size > 12) clockSamples.removeAt(0)
                    }
                    JamMessage.Ended -> {
                        lose(L("El anfitrión ha terminado el Jam."))
                        return
                    }
                    is JamMessage.Error -> {
                        lose(if (msg.reason == "full") L("El Jam está lleno.") else L("El código no es válido."))
                        return
                    }
                    else -> Unit
                }
            }
            if (_state.value.phase == JamPhase.Joined) lose(L("Se ha perdido la conexión con el anfitrión."))
        } catch (_: Exception) {
            // Si falló el atajo directo antes de conectar, la búsqueda en la Wi-Fi sigue; no es un error todavía.
            if (direct && !connecting.get()) return
            val phase = _state.value.phase
            if (phase == JamPhase.Joined || phase == JamPhase.Searching) lose(L("No se pudo conectar con el Jam."))
        } finally {
            // Sólo limpia quien ganó: un intento perdedor no puede cerrar la conexión buena.
            if (owned) {
                runCatching { hostSocket?.close() }
                hostSocket = null
                hostWriter = null
            }
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
        pinger?.cancel()
        pinger = null
        clockSamples.clear()
        _remotePlay.value = null
        _state.value = JamUiState(myName = _state.value.myName)
    }

    /** Anfitrión: un altavoz o cada uno en su móvil (2.6 de x.1.1). */
    fun setMode(mode: String) {
        if (_state.value.phase != JamPhase.Hosting) return
        scope.launch { updateHostJam { it.copy(mode = if (mode == JamSync.EVERYONE) JamSync.EVERYONE else JamSync.SPEAKER) } }
    }

    /** Anfitrión en modo «todos»: lo que suena aquí, para que los demás lo sigan. Lo llama la raíz de la app. */
    fun hostPlayback(song: app.libremusic.data.Song?, positionMs: Long, playing: Boolean) {
        val s = _state.value
        if (s.phase != JamPhase.Hosting || s.jam?.mode != JamSync.EVERYONE) return
        val msg = JamMessage.Play(song, positionMs, now(), playing)
        lastPlay = msg
        scope.launch { broadcast(msg) }
    }

    /** Invitado: escuchar también aquí o no. */
    fun setListenHere(on: Boolean) { _state.value = _state.value.copy(listenHere = on) }

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
