package app.libremusic.data


import app.libremusic.L
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.LocalDate

/**
 * Copia automática de la biblioteca: una vez al día (al abrir o salir de la app), `library.json` se copia a una carpeta
 * que elige la persona (Google Drive, Nextcloud, una tarjeta…) como `PearMusic-copia-AAAA-MM-DD.json`, y se dejan las
 * 7 últimas. Es el mismo archivo que «Exportar copia», así que se recupera con «Importar copia». Igual que iOS.
 */
object AutoBackup {
    const val PREFIX = "PearMusic-copia-"
    const val KEEP = 7

    data class State(val folder: Uri? = null, val folderName: String? = null, val lastDay: String? = null, val error: String? = null)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)

    /** Al abrir o salir de la app: la copia de hoy, si toca y hay carpeta. */
    fun backupSoon(context: Context, library: Library) {
        if (_state.value.folder == null) return
        val app = context.applicationContext
        scope.launch { backup(app, library) }
    }

    fun fileName(day: LocalDate) = "$PREFIX$day.json"

    /** Las copias que sobran (las más antiguas) de [names], dejando [keep]. */
    fun toPrune(names: List<String>, keep: Int = KEEP): List<String> =
        names.filter { it.startsWith(PREFIX) && it.endsWith(".json") }.sortedDescending().drop(keep)

    private fun sp(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun init(context: Context) {
        val sp = sp(context)
        val folder = sp.getString("backupFolder", null)?.let(Uri::parse)
        _state.value = State(folder, sp.getString("backupFolderName", null), sp.getString("backupLast", null))
    }

    /** Guarda la carpeta elegida (con permiso permanente) y hace la primera copia. */
    suspend fun setFolder(context: Context, library: Library, uri: Uri) {
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val name = runCatching { DocumentsContract.getTreeDocumentId(uri).substringAfterLast(':').substringAfterLast('/').ifEmpty { null } }.getOrNull()
        sp(context).edit().putString("backupFolder", uri.toString()).putString("backupFolderName", name).remove("backupLast").apply()
        _state.value = State(uri, name)
        backup(context, library, force = true)
    }

    fun disable(context: Context) {
        _state.value.folder?.let { runCatching { context.contentResolver.releasePersistableUriPermission(it, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } }
        sp(context).edit().remove("backupFolder").remove("backupFolderName").remove("backupLast").apply()
        _state.value = State()
    }

    /** Hace la copia de hoy si toca (o siempre, con [force]). Devuelve true si se ha escrito. */
    // Al abrir y salir seguidos podían correr dos copias a la vez y crear «… (1).json».
    private val lock = kotlinx.coroutines.sync.Mutex()

    suspend fun backup(context: Context, library: Library, force: Boolean = false): Boolean = lock.withLock { backupLocked(context, library, force) }

    private suspend fun backupLocked(context: Context, library: Library, force: Boolean): Boolean = withContext(Dispatchers.IO) {
        val st = _state.value
        val folder = st.folder ?: return@withContext false
        val today = LocalDate.now()
        if (!force && st.lastDay == today.toString()) return@withContext false
        val ok = runCatching {
            val cr = context.contentResolver
            val tree = DocumentsContract.buildDocumentUriUsingTree(folder, DocumentsContract.getTreeDocumentId(folder))
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(folder, DocumentsContract.getTreeDocumentId(folder))
            val existing = mutableMapOf<String, Uri>()
            cr.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
                while (c.moveToNext()) existing[c.getString(1)] = DocumentsContract.buildDocumentUriUsingTree(folder, c.getString(0))
            }
            val name = fileName(today)
            val target = existing[name] ?: DocumentsContract.createDocument(cr, tree, "application/json", name)!!
            cr.openOutputStream(target, "wt")!!.use { it.write(library.exportJson().toByteArray()) }
            toPrune(existing.keys.toList() + name).forEach { old -> existing[old]?.let { DocumentsContract.deleteDocument(cr, it) } }
        }
        if (ok.isSuccess) {
            sp(context).edit().putString("backupLast", today.toString()).apply()
            _state.value = st.copy(lastDay = today.toString(), error = null)
        } else {
            _state.value = st.copy(error = L("No se pudo guardar la copia. Vuelve a elegir la carpeta."))
        }
        ok.isSuccess
    }
}
