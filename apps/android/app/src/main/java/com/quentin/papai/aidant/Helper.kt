package com.quentin.papai.aidant

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

private const val TAG = "PapAI"

data class Question(val text: String, val options: List<String>)
data class AlertInfo(val title: String, val detail: String)
data class Lesson(val title: String, val steps: Int)

class DraftStep(instruction: String, val checkpoint: String?, val preview: ImageBitmap?) {
    var instruction by mutableStateOf(instruction)
}

enum class Screen { IDLE, WAITING, PLANNING, APPROVAL, ACTIVE, HELPER, DONE, STOPPED }

sealed interface AppSheet {
    data object Settings : AppSheet
}

/** Étape du plan : « Ouvrir le Finder — dans le Dock » → titre + détail. */
fun splitStep(raw: String): Pair<String, String?> {
    for (sep in listOf(" — ", " : ", ": ")) {
        val i = raw.indexOf(sep)
        if (i >= 0) return raw.substring(0, i) to raw.substring(i + sep.length)
    }
    return raw to null
}

/**
 * Tout l'état de l'app du support, comme `HelperModel` sur l'iPhone.
 * Les champs sont des états Compose ; on ne les modifie que sur le fil principal.
 */
@SuppressLint("StaticFieldLeak")
object Helper {
    private lateinit var ctx: Context
    private lateinit var prefs: SharedPreferences
    private val main = Handler(Looper.getMainLooper())
    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        // Ping toutes les 15 s : garde la connexion à travers les proxys et coupe une connexion morte.
        .pingInterval(15, TimeUnit.SECONDS)
        .build()
    private val rest = http.newBuilder().readTimeout(20, TimeUnit.SECONDS).build()

    // Poste suivi en détail (`<serveur>/k/<clé>` et sa clé), choisi parmi les postes de l'organisation.
    var serverURL by mutableStateOf("")
        private set
    var helperKey by mutableStateOf("")
        private set
    /** Nom affiché du support (restriction gérée `supportName`, facultative). */
    var helperName by mutableStateOf<String?>(null)
        private set
    /** Identifiant de ce support chez le serveur, par poste : il apparaît dans « Mon support » sur l'ordinateur. */
    private var helperId = ""
    var seniorName by mutableStateOf("")

    // Les postes de l'organisation : un seul suivi en détail à la fois, les autres surveillés.
    val people = mutableStateListOf<Person>()
    /** Pour les autres personnes : clé → ordinateur connecté / demande en attente. */
    val othersOnline = mutableStateMapOf<String, Boolean>()
    val othersAsking = mutableStateMapOf<String, Boolean>()
    private val watches = mutableMapOf<String, WebSocket>()

    // Connexion
    var connected by mutableStateOf(false)
    var linkError by mutableStateOf<String?>(null)
    var retryAt by mutableStateOf<Long?>(null)
    var keyRefused by mutableStateOf(false)

    var sheet by mutableStateOf<AppSheet?>(null)

    // Session
    var state by mutableStateOf<String?>(null)
    var sessionWhere by mutableStateOf<String?>(null)
    val webLive get() = sessionWhere == "web" && (state == "active" || state == "awaiting_helper")
    var task by mutableStateOf("")
    var plan by mutableStateOf<List<String>>(emptyList())
    var linkupVisible by mutableStateOf(false)
    var linkupPending by mutableStateOf(false)
    var linkupQuery by mutableStateOf("")
    var linkupText by mutableStateOf("")
    var linkupId by mutableStateOf("")
    var linkupSources by mutableStateOf<List<Pair<String, String>>>(emptyList())
    var linkupError by mutableStateOf(false)
    var linkupBusy by mutableStateOf(false)
    var planStep by mutableStateOf<Int?>(null)
    var doing by mutableStateOf<String?>(null)
    var question by mutableStateOf<Question?>(null)
    var questionToSenior by mutableStateOf(false)
    var liveDictation by mutableStateOf<String?>(null)
    var seniorPaused by mutableStateOf(false)
    private var sessionId = ""
    var requestStart by mutableStateOf(System.currentTimeMillis())
    var iRefusedPlan by mutableStateOf(false)
    var doneFresh by mutableStateOf(false)
    var doneAnswer by mutableStateOf<String?>(null)
    var pausing by mutableStateOf(false)
    var planBusy by mutableStateOf(false)

    // Capture
    var frame by mutableStateOf<ImageBitmap?>(null)
    private var frameId: String? = null
    private var lastNotified = ""
    private var hasProposedPlan = false
    var frameAt by mutableStateOf<Long?>(null)

    // Prise de main
    var aiming by mutableStateOf(false)
    /** Point visé, en coordonnées 0…1 de la capture. */
    var target by mutableStateOf<Offset?>(null)
    var sending by mutableStateOf(false)

    // Fiche (automatisme)
    var lessonBusy by mutableStateOf(false)
    var draftTitle by mutableStateOf("")
    val draftSteps = mutableStateListOf<DraftStep>()
    var draftTarget by mutableStateOf<String?>(null)
    var hasDraft by mutableStateOf(false)
    var savedTitle by mutableStateOf<String?>(null)
    var lessons by mutableStateOf<List<Lesson>>(emptyList())

    var toast by mutableStateOf<String?>(null)
    var sensitiveRefusal by mutableStateOf<String?>(null)
    var lastAlert by mutableStateOf<AlertInfo?>(null)

    /** L'app est au premier plan : pas besoin de notification, l'écran change déjà. */
    var foreground = false

    private var socket: WebSocket? = null
    /** Numéro de la connexion en cours : un rappel d'une ancienne connexion est ignoré. */
    private var generation = 0
    private var delay = 1L
    private var retry: Runnable? = null
    private var toastHide: Runnable? = null
    private var dictationClear: Runnable? = null
    const val FRAME_TTL_S = 30

    fun init(c: Context) {
        ctx = c.applicationContext
        prefs = ctx.getSharedPreferences("papai", Context.MODE_PRIVATE)
        // Restes de l'ancienne liaison poste par poste : plus rien de tout cela n'est lu.
        prefs.edit().remove("people").remove("orgs").remove("lastGoodServerURL").remove("lastGoodHelperKey")
            .remove("helperRelation").remove("helperName").remove("helperId").apply()
        org = loadSupportOrg(ctx)
        helperName = loadSupportName(ctx)
        // Le dernier poste suivi, s'il est bien sur le serveur de l'organisation : on s'y
        // reconnecte tout de suite, la liste des postes arrive juste après.
        val s = prefs.getString("serverURL", "") ?: ""
        val k = prefs.getString("helperKey", "") ?: ""
        val o = org
        if (o != null && k.isNotEmpty() && s == "${o.server}/k/$k") {
            serverURL = s; helperKey = k
            helperId = helperIds()[k] ?: ""
            seniorName = cleanText(prefs.getString("seniorName", ""))
        } else {
            prefs.edit().remove("serverURL").remove("helperKey").remove("seniorName").apply()
        }
    }

    val isConfigured get() = serverURL.isNotBlank() && helperKey.isNotBlank()

    // MARK: Organisation (service IT) : tous les postes inscrits, sans liaison.

    /** Jeton support et serveur déposés par l'administrateur ; null : rien n'est configuré. */
    var org by mutableStateOf<SupportOrg?>(null)
        private set
    var orgName by mutableStateOf<String?>(null)
        private set
    /** Dernier échec de lecture de la liste des postes (null si tout va bien). */
    var orgError by mutableStateOf<String?>(null)
        private set
    /** La liste des postes a été lue au moins une fois. */
    var orgLoaded by mutableStateOf(false)
        private set
    private var orgPoll: Runnable? = null
    private var orgFetching = false
    private val noRedirect = rest.newBuilder().followRedirects(false).followSslRedirects(false).build()

    val orgConfigured get() = org != null
    /** « Support IT · Acme », ou « Support IT » tant que le nom n'est pas connu. */
    val orgTitle get() = orgName?.let { "Support IT · $it" } ?: "Support IT"
    /** Hôte du serveur de l'organisation, pour les Réglages et les messages. */
    val orgHost get() = org?.let { hostOf(it.server) }

    private fun hostOf(server: String): String {
        val u = android.net.Uri.parse(server)
        val h = u.host ?: return server
        return if (u.port > 0) "$h:${u.port}" else h
    }

    /** Relit la liste des postes toutes les 30 s : un poste inscrit après coup apparaît seul. */
    private fun startOrg() {
        if (org == null || orgPoll != null) return
        orgPoll = object : Runnable {
            override fun run() {
                refreshOrg()
                main.postDelayed(this, 30_000)
            }
        }.also { main.post(it) }
    }

    /**
     * La configuration gérée a pu changer (l'administrateur l'a poussée après coup) :
     * on repart de zéro avec la nouvelle organisation.
     */
    private fun reloadConfig() {
        helperName = loadSupportName(ctx)
        val o = loadSupportOrg(ctx)
        if (o == org) return
        orgPoll?.let { main.removeCallbacks(it) }; orgPoll = null
        if (isConfigured) leaveCurrent()
        people.clear()
        watchOthers()
        org = o; orgName = null; orgError = null; orgLoaded = false
        if (o == null) LinkService.stop(ctx) else startOrg()
    }

    fun refreshOrg() {
        val o = org ?: return
        if (orgFetching) return
        val host = hostOf(o.server)
        val req = try { Request.Builder().url("${o.server}/o/${o.token}/spaces").build() }
        catch (_: IllegalArgumentException) { orgError = "Adresse du serveur invalide."; return }
        orgFetching = true
        noRedirect.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                main.post {
                    orgFetching = false
                    // Organisation changée pendant la requête : on relit tout de suite la nouvelle.
                    if (org == o) orgError = "Le serveur $host ne répond pas." else refreshOrg()
                }
            }

            override fun onResponse(call: Call, response: Response) {
                val code = response.code
                val body = try { response.use { it.body?.string() } } catch (_: IOException) { null }
                val r = try { JSONObject(body ?: "") } catch (_: Exception) { null }
                main.post {
                    orgFetching = false
                    if (org != o) { refreshOrg(); return@post }
                    if (code != 200 || r == null) {
                        orgError = if (code == 404 || code == 403)
                            "Jeton support refusé par $host. Contactez votre administrateur."
                        else "Le serveur $host répond une erreur $code."
                        return@post
                    }
                    orgError = null; orgLoaded = true
                    r.text("org").takeIf { it.isNotEmpty() && it != orgName }?.let { orgName = it; LinkService.refresh(ctx) }
                    val spaces = r.optJSONArray("spaces")
                    applySpaces(People.fromSpaces(spaces, o.server, people.toList()), spaces)
                }
            }
        })
    }

    /** La liste du serveur fait foi : un poste retiré de l'organisation disparaît d'ici. */
    private fun applySpaces(list: List<Person>, spaces: JSONArray?) {
        people.clear(); people.addAll(list)
        for (i in 0 until (spaces?.length() ?: 0)) {
            val s = spaces?.optJSONObject(i) ?: continue
            val k = s.opt("key") as? String ?: continue
            // Un canal de surveillance ouvert sait mieux ; sinon l'état renvoyé par la liste.
            if (k !in watches) othersOnline[k] = s.optBoolean("online", false)
        }
        val i = people.indexOfFirst { isCurrent(it) }
        if (i >= 0) {
            if (people[i].name.isEmpty()) people[i] = people[i].copy(name = seniorName) else setSenior(people[i].name)
        } else if (isConfigured) {
            leaveCurrent()
        }
        if (!isConfigured) people.firstOrNull()?.let { switchTo(it) }
        if (!isConfigured) LinkService.stop(ctx)
        watchOthers()
    }

    /** Quitte le poste suivi (retiré de l'organisation, ou plus aucun poste). */
    private fun leaveCurrent() {
        generation++
        socket?.cancel(); socket = null
        retry?.let { main.removeCallbacks(it) }; retry = null
        connected = false; keyRefused = false; linkError = null; retryAt = null
        serverURL = ""; helperKey = ""; seniorName = ""; helperId = ""
        prefs.edit().remove("serverURL").remove("helperKey").remove("seniorName").apply()
        clearSession()
    }

    private fun helperIds(): Map<String, String> = try {
        val o = JSONObject(prefs.getString("helperIds", null) ?: "{}")
        o.keys().asSequence().associateWith { o.text(it) }.filterValues { it.isNotEmpty() }
    } catch (_: Exception) { emptyMap() }

    private fun saveHelperId(key: String, id: String) {
        val o = try { JSONObject(prefs.getString("helperIds", null) ?: "{}") } catch (_: Exception) { JSONObject() }
        prefs.edit().putString("helperIds", o.put(key, id).toString()).apply()
    }

    /** Dans une phrase : « Rien à signaler pour Sophie », sinon « de l’utilisateur ». */
    val senior get() = seniorName.ifEmpty { "l’utilisateur" }
    /** En début de phrase : « Sophie a besoin de vous ». */
    val seniorTitle get() = seniorName.ifEmpty { "L’utilisateur" }
    val webBrowserTitle get() = seniorName.trim().split(Regex("\\s+")).firstOrNull()
        ?.let { "Chrome PapAI de $it" } ?: "Chrome PapAI"

    val screen: Screen
        get() = when (state) {
            "waiting_consent" -> Screen.WAITING
            "planning" -> Screen.PLANNING
            "awaiting_approval" -> Screen.APPROVAL
            "active" -> Screen.ACTIVE
            "awaiting_helper" -> Screen.HELPER
            "done" -> if (doneFresh) Screen.DONE else Screen.IDLE
            "stopped" -> Screen.STOPPED
            else -> Screen.IDLE
        }

    // MARK: Réglages et connexion

    private val baseHTTP: String
        get() {
            var s = serverURL.trim().trimEnd('/')
            if (!s.contains("://")) s = "http://$s"
            return s
        }

    private val wsURL: String
        get() = baseHTTP.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") +
            "/ws/aidant/" + helperKey.trim()

    /** Hôte affiché dans les messages (sans la clé famille du chemin). */
    val displayHost: String
        get() {
            val u = android.net.Uri.parse(baseHTTP)
            val h = u.host ?: return serverURL
            return if (u.port > 0) "$h:${u.port}" else h
        }

    // MARK: Postes

    /** Garde ce qu'on a appris du poste suivi (prénom, identifiant de support). */
    private fun rememberCurrent() {
        if (!isConfigured) return
        val i = people.indexOfFirst { isCurrent(it) }
        if (i < 0) return
        var p = people[i]
        if (seniorName.isNotEmpty()) p = p.copy(name = seniorName)
        if (helperId.isNotEmpty()) p = p.copy(helperId = helperId)
        if (p != people[i]) people[i] = p
    }

    fun isCurrent(p: Person) = p.key == helperKey.trim()

    /** Suivre un autre poste : la connexion détaillée change, les autres restent surveillés. */
    fun switchTo(p: Person) {
        sensitiveRefusal = null
        if (isCurrent(p)) return
        rememberCurrent()
        serverURL = p.server; helperKey = p.key; seniorName = p.name
        helperId = p.helperId.ifEmpty { helperIds()[p.key] ?: "" }
        prefs.edit().putString("serverURL", p.server).putString("helperKey", p.key).putString("seniorName", p.name).apply()
        clearSession()
        reconnect()
        LinkService.start(ctx)
        LinkService.refresh(ctx)
    }

    private fun clearSession() {
        clearLinkup()
        state = null; sessionWhere = null; sessionId = ""; task = ""; plan = emptyList(); planStep = null
        doing = null; question = null; questionToSenior = false; liveDictation = null
        frame = null; frameId = null; frameAt = null; aiming = false; target = null
        lessons = emptyList(); lastAlert = null; doneFresh = false; hasDraft = false; savedTitle = null
        clearHelpNotification()
    }

    private fun wsFor(server: String, key: String): String {
        var s = server.trim().trimEnd('/')
        if (!s.contains("://")) s = "http://$s"
        return s.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + "/ws/aidant/" + key.trim()
    }

    /** Un canal discret par autre personne, pour savoir qui demande une assistance. */
    fun watchOthers() {
        val others = people.filter { !isCurrent(it) }.associateBy { it.key }
        (watches.keys - others.keys).forEach { k ->
            watches.remove(k)?.cancel(); othersOnline.remove(k); othersAsking.remove(k)
        }
        others.values.forEach { p -> if (p.key !in watches) watch(p) }
    }

    private fun watch(p: Person) {
        val req = try { Request.Builder().url(wsFor(p.server, p.key)).build() } catch (_: IllegalArgumentException) { return }
        watches[p.key] = http.newWebSocket(req, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val m = try { JSONObject(text) } catch (_: Exception) { return }
                main.post {
                    if (watches[p.key] !== webSocket) return@post
                    val who = people.firstOrNull { it.key == p.key }
                        ?.let { it.name.ifEmpty { it.label } }?.ifEmpty { null } ?: "Un utilisateur"
                    when (m.text("type")) {
                        "refused" -> {
                            watches.remove(p.key); othersOnline[p.key] = false
                            webSocket.close(1000, null)
                        }
                        "hello" -> {
                            othersOnline[p.key] = m.optBoolean("bridge"); othersAsking[p.key] = false
                            renamePerson(p.key, m.text("senior"))
                        }
                        "senior" -> renamePerson(p.key, m.text("name"))
                        "status" -> {
                            val was = othersAsking[p.key] == true
                            val now = People.isAsking(m.text("state"))
                            othersAsking[p.key] = now
                            if (now && !was) {
                                showToast("$who demande une assistance.")
                                notifyLocal("$who demande une assistance",
                                    m.text("task").ifEmpty { "Ouvrez PapAI pour voir la demande." }, otherNotificationId(p.key))
                            }
                        }
                        "alert_cleared" -> othersAsking[p.key] = false
                        "alert" -> {
                            othersAsking[p.key] = true
                            notifyLocal("$who : ${m.text("title").ifEmpty { "alerte" }}", m.text("detail"), otherNotificationId(p.key))
                        }
                    }
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                if (SupportConfig.accessRevoked(code)) main.post { unwatch(p, webSocket) }
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { rewatch(p, webSocket) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val refused = response?.code == 401 || response?.code == 403
                main.post { if (refused) unwatch(p, webSocket) else rewatch(p, webSocket) }
            }
        })
    }

    /** Accès retiré à ce poste : on le laisse, sans réessayer ; la prochaine liste valide le rouvrira. */
    private fun unwatch(p: Person, ws: WebSocket) {
        if (watches[p.key] !== ws) return
        watches.remove(p.key); othersOnline[p.key] = false
    }

    private fun rewatch(p: Person, ws: WebSocket) {
        if (watches[p.key] !== ws) return
        watches.remove(p.key); othersOnline[p.key] = false
        main.postDelayed({
            if (p.key !in watches && people.any { it.key == p.key && !isCurrent(it) }) watch(p)
        }, 10_000)
    }

    private fun renamePerson(key: String, name: String) {
        val n = cleanText(name)
        val i = people.indexOfFirst { it.key == key }
        if (n.isEmpty() || i < 0 || people[i].name == n) return
        people[i] = people[i].copy(name = n)
    }

    private fun otherNotificationId(key: String) = 100 + (key.hashCode() and 0x3ff)

    fun start() {
        startOrg()
        watchOthers()
        if (!isConfigured || socket != null || retry != null) return
        connect()
        loadLessons()
    }

    fun reconnect() {
        generation++
        socket?.cancel(); socket = null
        retry?.let { main.removeCallbacks(it) }; retry = null
        connected = false; keyRefused = false; linkError = null; retryAt = null; delay = 1; linkupBusy = false
        start()
    }

    /** Retour au premier plan : on n'attend pas la fin du délai d'attente. */
    fun wakeUp() {
        reloadConfig()
        if (org == null) return
        startOrg()
        if (!isConfigured) { refreshOrg(); return }
        if (!connected && (retry != null || keyRefused)) { reconnect(); return }
        if (connected) loadLessons()
        start()
    }

    private fun connect() {
        val gen = ++generation
        val host = displayHost
        val req = try {
            Request.Builder().url(wsURL).build()
        } catch (e: IllegalArgumentException) {
            linkError = "Adresse du serveur invalide."; return
        }
        Log.i(TAG, "ouverture vers $host")
        socket = http.newWebSocket(req, object : WebSocketListener() {
            var hello = false

            override fun onMessage(webSocket: WebSocket, text: String) {
                val msg = try { JSONObject(text) } catch (_: Exception) { return }
                // Les captures se décodent hors du fil principal.
                val img = if (msg.text("type") == "frame") decode(msg.text("png_b64")) else null
                main.post {
                    if (gen != generation) return@post
                    if (!hello) {
                        if (msg.text("type") == "refused") {
                            keyRefused = true
                            val reason = msg.text("reason").takeIf { it.isNotEmpty() }
                            linkError = "Accès refusé par $host" + (reason?.let { " ($it)" } ?: "") + "."
                            webSocket.close(1000, null)
                            return@post
                        }
                        hello = true; connected = true; linkError = null; retryAt = null; delay = 1; linkupBusy = false
                        Log.i(TAG, "connecté à $host")
                    }
                    handle(msg, img)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                if (SupportConfig.accessRevoked(code)) main.post {
                    if (gen == generation) { keyRefused = true; linkError = "Accès retiré par votre administrateur." }
                }
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { lost(gen, if (hello) "Connexion coupée" else "Le serveur ne répond pas à $host") }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val http = response?.code ?: 0
                Log.w(TAG, "fermée : http $http ${t.javaClass.simpleName} ${t.message}")
                main.post {
                    if (gen != generation) return@post
                    val e = when {
                        http == 401 || http == 403 -> { keyRefused = true; "Accès refusé par $host." }
                        http == 404 -> "Poste introuvable sur $host."
                        http >= 400 -> "Le serveur $host répond une erreur $http."
                        hello -> "Connexion coupée"
                        t is UnknownHostException && !online() -> "Ce téléphone n'a pas de connexion internet."
                        else -> "Le serveur ne répond pas à $host"
                    }
                    lost(gen, e)
                }
            }
        })
    }

    private fun lost(gen: Int, error: String) {
        if (gen != generation) return
        socket = null; connected = false; linkupBusy = false
        if (linkError == null || !keyRefused) linkError = error
        // Poste retiré de l'organisation ? La liste des postes le dira.
        if (keyRefused) { retryAt = null; refreshOrg(); return }
        val d = delay
        retryAt = System.currentTimeMillis() + d * 1000
        retry = Runnable { retry = null; retryAt = null; if (gen == generation) connect() }.also { main.postDelayed(it, d * 1000) }
        delay = minOf(d * 2, 8)   // backoff jusqu'à 8 s
    }

    private fun online(): Boolean {
        val cm = ctx.getSystemService(android.net.ConnectivityManager::class.java) ?: return true
        return cm.activeNetwork != null
    }

    private fun decode(b64: String): ImageBitmap? = try {
        val bytes = Base64.decode(b64, Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
    } catch (_: Exception) { null }

    // MARK: Utilisateur

    fun setSenior(name: String?) {
        val n = cleanText(name)
        if (n.isEmpty() || n == seniorName) return
        seniorName = n
        prefs.edit().putString("seniorName", n).apply()
        rememberCurrent()
        LinkService.refresh(ctx)
    }

    fun send(o: JSONObject) {
        val s = socket
        if (s == null || !connected) {
            planBusy = false; sending = false; linkupBusy = false
            showToast("Pas de connexion au serveur."); return
        }
        if (o.text("type") != "helper_hello") sensitiveRefusal = null
        if (!s.send(o.toString()) && o.text("type") == "linkup_search") {
            linkupBusy = false; linkupError = true
        }
    }

    private fun send(vararg kv: Pair<String, Any?>) = send(JSONObject().apply { kv.forEach { (k, v) -> put(k, v) } })

    fun loadLessons() {
        if (!isConfigured) return
        val req = try { Request.Builder().url("$baseHTTP/lessons").build() } catch (_: Exception) { return }
        rest.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {}
            override fun onResponse(call: Call, response: Response) {
                val arr = try { JSONArray(response.body?.string() ?: "[]") } catch (_: Exception) { return }
                val list = (0 until arr.length()).mapNotNull { i ->
                    val o = arr.optJSONObject(i) ?: return@mapNotNull null
                    Lesson(o.text("title"), o.optJSONArray("steps")?.length() ?: 0)
                }
                main.post { lessons = list }
            }
        })
    }

    fun showToast(s: String) {
        toast = s
        toastHide?.let { main.removeCallbacks(it) }
        toastHide = Runnable { toast = null }.also { main.postDelayed(it, 4000) }
    }

    // MARK: Messages

    private fun strings(a: JSONArray?): List<String> =
        if (a == null) emptyList() else (0 until a.length()).map { a.text(it) }

    private fun handle(m: JSONObject, img: ImageBitmap?) {
        when (m.text("type")) {
            "hello" -> {
                setSenior(m.text("senior"))
                // Le serveur renvoie status et capture juste après s'il y a une session :
                // sans session (serveur redémarré), il ne reste rien de l'ancienne demande.
                state = null; frame = null; frameId = null; frameAt = null
                // On se présente : l'ordinateur voit son support dans « Mon support ».
                send("type" to "helper_hello", "id" to helperId, "name" to (helperName ?: orgTitle),
                    "relation" to "le service informatique")
            }

            "helper_id" -> m.text("id").takeIf { it.isNotEmpty() }?.let {
                helperId = it; saveHelperId(helperKey.trim(), it)
                rememberCurrent()
            }

            "dictation" -> {
                val t = m.text("text")
                liveDictation = t.ifEmpty { null }
                dictationClear?.let { main.removeCallbacks(it) }
                // Sans nouvelle demande dans la minute, on efface le texte affiché.
                dictationClear = Runnable { liveDictation = null }.also { main.postDelayed(it, 60_000) }
            }

            "senior" -> setSenior(m.text("name"))

            "status" -> {
                val newState = m.text("state").ifEmpty { null }
                val newWhere = m.text("where").ifEmpty { null }
                val sid = m.text("session")
                var wasWebLive = webLive
                if (sid != sessionId) {
                    clearLinkup()
                    wasWebLive = false
                    liveDictation = null
                    sessionId = sid; requestStart = System.currentTimeMillis(); iRefusedPlan = false
                    sessionWhere = null
                    hasProposedPlan = false
                    doneAnswer = null; hasDraft = false; savedTitle = null; lessonBusy = false
                    pausing = false; doneFresh = false
                    frame = null; frameId = null; frameAt = null
                }
                val newWebLive = newWhere == "web" && (newState == "active" || newState == "awaiting_helper")
                if (newWebLive && !wasWebLive) {
                    aiming = false; target = null; sending = false
                    frame = null; frameId = null; frameAt = null
                }
                if (wasWebLive && !newWebLive) {
                    frame = null; frameId = null; frameAt = null
                    target = null; sending = false
                }
                sessionWhere = newWhere
                val q = m.optJSONObject("question")
                val toSenior = q?.text("to") == "senior"
                if (newState != state) {
                    // Une reconnexion renvoie le même état : on ne sonne pas deux fois pour la même attente.
                    val key = "$sid:$newState"
                    val waits = newState == "awaiting_approval" || (newState == "awaiting_helper" && !toSenior)
                    if (!waits) lastNotified = ""
                    if (waits && key != lastNotified) {
                        lastNotified = key
                        notifyHelp(newState, q?.text("question"), m.text("task"))
                    }
                    if (newState == "done") { doneFresh = true; loadLessons() }
                    if (newState == "active") { pausing = false; planBusy = false }
                    if (newState != "awaiting_helper") { aiming = false; target = null; sending = false }
                    if (newState == "awaiting_approval") planBusy = false
                    if (newState != "awaiting_approval" && newState != "awaiting_helper") clearHelpNotification()
                }
                state = newState
                if (newState == "awaiting_approval") hasProposedPlan = true
                task = m.text("task").ifEmpty { task }
                plan = strings(m.optJSONArray("plan"))
                planStep = if (m.has("plan_step") && !m.isNull("plan_step")) m.optInt("plan_step") else null
                doing = m.text("doing").ifEmpty { null }
                seniorPaused = m.optBoolean("paused", false)
                if (q != null && q.text("question").isNotEmpty()) {
                    question = Question(q.text("question"), strings(q.optJSONArray("options")))
                    questionToSenior = toSenior
                } else if (newState != "awaiting_helper") question = null
            }

            "frame" -> if (img != null) {
                frame = img; frameId = m.text("frame_id").ifEmpty { null }
                frameAt = System.currentTimeMillis(); target = null
            }

            "question" -> m.text("question").takeIf { it.isNotEmpty() }?.let {
                question = Question(it, strings(m.optJSONArray("options")))
            }

            "linkup_proposed" -> if (m.text("session") == sessionId) {
                linkupVisible = true; linkupPending = true; linkupQuery = m.text("query")
                linkupText = ""; linkupId = ""; linkupSources = emptyList(); linkupError = false
            }
            "linkup_result" -> if (m.text("session") == sessionId) {
                linkupVisible = true; linkupBusy = false; linkupError = m.has("error")
                linkupText = m.text("summary"); linkupId = m.text("id")
                val sources = m.optJSONArray("sources")
                linkupSources = (0 until (sources?.length() ?: 0)).mapNotNull { i ->
                    val s = sources?.optJSONObject(i) ?: return@mapNotNull null
                    val url = s.text("url")
                    if (url.startsWith("https://") || url.startsWith("http://")) s.text("name") to url else null
                }
            }
            "linkup_answer", "answer" -> doneAnswer = m.text("content").ifEmpty { null }

            "alert" -> {
                val t = m.text("title").ifEmpty { "Alerte" }
                val d = m.text("detail")
                lastAlert = AlertInfo(t, d)
                notifyLocal(t, d, ALERT_ID)
                showToast(t)
            }

            "refused" -> {
                if (m.text("blocked") == "sensitive") {
                    sensitiveRefusal = m.text("reason").ifEmpty { "Cette fenêtre est protégée (réglages ou mots de passe)." }
                    toast = null
                } else showToast(m.text("reason").ifEmpty { "Refusé" })
                sending = false; planBusy = false; lessonBusy = false; linkupBusy = false
            }

            "ack" -> when (m.text("what")) {
                "click" -> {
                    sending = false; aiming = false; target = null
                    showToast("Clic transmis à l'ordinateur de $senior.")
                }
                "pause" -> pausing = true
            }

            "lesson_pending" -> lessonBusy = true

            "lesson_draft" -> {
                lessonBusy = false
                val l = m.optJSONObject("lesson") ?: return
                draftTitle = l.text("title")
                draftTarget = shortcutLabel(l.optJSONObject("shortcut"))
                val previews = m.optJSONObject("preview")
                draftSteps.clear()
                val steps = l.optJSONArray("steps") ?: JSONArray()
                for (i in 0 until steps.length()) {
                    val s = steps.optJSONObject(i)
                    if (s == null) { draftSteps.add(DraftStep(steps.text(i), null, null)); continue }
                    val f = s.text("frame")
                    val preview = previews?.text(f)?.takeIf { f.isNotEmpty() && it.isNotEmpty() }?.let { decode(it) }
                    draftSteps.add(DraftStep(s.text("instruction"), s.text("checkpoint").ifEmpty { null }, preview))
                }
                hasDraft = true
            }

            "lesson_saved" -> {
                hasDraft = false; lessonBusy = false
                savedTitle = m.optJSONObject("lesson")?.text("title")?.ifEmpty { null } ?: draftTitle
                loadLessons()
            }
        }
    }

    private fun shortcutLabel(s: JSONObject?): String? {
        val folder = s?.text("folder")?.ifEmpty { null } ?: return null
        val names = mapOf("downloads" to "Téléchargements", "pictures" to "Images", "documents" to "Documents",
            "desktop" to "Bureau", "videos" to "Vidéos", "music" to "Musique")
        val sub = s.text("subfolder")
        val root = names[folder.lowercase()] ?: folder
        return if (sub.isEmpty()) root else "$root › $sub"
    }

    // MARK: Notifications

    private const val HELP_ID = 10
    private const val ALERT_ID = 11

    private fun notifyHelp(state: String, question: String?, task: String) {
        val who = seniorTitle
        if (state == "awaiting_approval") {
            notifyLocal(if (hasProposedPlan) "Nouveau plan proposé" else "$who demande de l'aide",
                if (task.isEmpty()) "Un plan attend votre accord." else "« $task » : un plan attend votre accord.", HELP_ID)
        } else {
            notifyLocal("$who a besoin de vous", question?.ifEmpty { null } ?: "Holo attend votre aide.", HELP_ID)
        }
    }

    private fun clearHelpNotification() = NotificationManagerCompat.from(ctx).cancel(HELP_ID)

    private fun notifyLocal(title: String, body: String, id: Int) {
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            android.os.Build.VERSION.SDK_INT >= 33) return
        val intent = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(ctx, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(ctx, PapAIApp.CHANNEL_HELP)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(NotificationCompat.Builder(ctx, PapAIApp.CHANNEL_HELP)
                .setSmallIcon(R.drawable.ic_notif)
                .setContentTitle("PapAI : une demande d'aide vous attend")
                .setContentIntent(pi)
                .build())
            .setSmallIcon(R.drawable.ic_notif)
            .setColor(0xFF1F5BE8.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .apply { if (!foreground) setFullScreenIntent(pi, true) }
            .build()
        try { NotificationManagerCompat.from(ctx).notify(id, n) } catch (_: SecurityException) {}
    }

    // MARK: Actions

    fun approvePlan() { planBusy = true; send("type" to "approve_plan") }
    fun clearLinkup() {
        linkupVisible = false; linkupPending = false; linkupQuery = ""; linkupText = ""
        linkupId = ""; linkupSources = emptyList(); linkupError = false; linkupBusy = false
    }
    fun openLinkup() { clearLinkup(); linkupVisible = true; linkupQuery = task }
    fun searchLinkup() {
        linkupBusy = true; linkupId = ""; linkupText = ""; linkupSources = emptyList(); linkupError = false
        send("type" to "linkup_search", "session" to sessionId, "query" to linkupQuery)
    }
    fun approveLinkup() = send("type" to "linkup_approve", "session" to sessionId,
        "id" to linkupId, "approved" to true, "text" to linkupText)
    fun refuseLinkup() {
        if (linkupPending) send("type" to "linkup_approve", "session" to sessionId, "approved" to false)
        else clearLinkup()
    }
    fun refinePlan(text: String) { planBusy = true; send("type" to "refine_plan", "text" to text) }
    fun refusePlan() { iRefusedPlan = true; send("type" to "refuse_plan") }
    fun answer(t: String) = send("type" to "answer", "text" to t)
    fun pause() { pausing = true; send("type" to "pause"); showToast("Pause demandée : l'action en cours se termine.") }
    fun refresh() = send("type" to "refresh")

    fun setAimingOn(on: Boolean) {
        aiming = on && state == "awaiting_helper"
        target = null
        if (aiming) refresh()   // la dernière image date du dernier pas de Holo
    }

    fun confirmClick() {
        val t = target ?: return
        val id = frameId ?: return
        if (sending) return
        sending = true
        send("type" to "click", "frame_id" to id, "x" to t.x.toDouble(), "y" to t.y.toDouble())
    }

    fun requestLesson() { lessonBusy = true; send("type" to "draft_lesson") }

    fun approveLesson() {
        val steps = JSONArray()
        draftSteps.forEach { steps.put(JSONObject().put("instruction", it.instruction.trim())) }
        send("type" to "approve_lesson", "lesson" to JSONObject().put("title", draftTitle.trim()).put("steps", steps))
    }
}
