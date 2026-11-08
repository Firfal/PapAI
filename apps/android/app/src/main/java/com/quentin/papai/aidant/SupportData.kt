package com.quentin.papai.aidant

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// Données de l'accueil du support (tickets, bibliothèque d'automates), comme
// `SupportData.swift` sur l'iPhone et le mode support du Mac. Aucun écran ici.

private val json = "application/json".toMediaType()
private val supportHttp by lazy {
    OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).build()
}
private val pool by lazy { Executors.newFixedThreadPool(4) }
private val mainThread by lazy { Handler(Looper.getMainLooper()) }

/** Adresse HTTP de l'espace d'un utilisateur (`<serveur>/k/<clé>`). */
fun spaceBase(p: Person): String {
    var s = p.server.trim().trimEnd('/')
    if (!s.contains("://")) s = "http://$s"
    return s
}

/** Ton des pastilles d'état, mêmes couleurs que `TonPastille` (Mac, iPhone). */
enum class Tone { BLUE, VIOLET, GREEN, ORANGE, GRAY }

/** Un ticket d'un utilisateur (`GET …/k/<clé>/tickets`), avec la personne d'où il vient. */
data class SupportTicket(
    val tid: String,
    val number: Int,
    val task: String,
    val status: String,
    val updated: Double,
    val rdv: Double?,
    val assignee: String,
    val person: Person,
) {
    val id get() = person.key + "/" + tid
    val label get() = String.format(Locale.ROOT, "T-%04d", number)
    val isOpen get() = status != "resolu"
    /** « Prendre en charge » et « Clore » : ticket ouvert, hors assistance en cours. */
    val canTake get() = isOpen && status != "en_cours"
    val personName get() = People.title(person)

    val statut: Pair<String, Tone>
        get() = when (status) {
            "nouveau" -> "Nouveau" to Tone.BLUE
            "en_attente" -> "En attente" to Tone.ORANGE
            "rdv" -> "Rendez-vous" to Tone.VIOLET
            "en_cours" -> "En cours" to Tone.GREEN
            "a_reprendre" -> "À reprendre" to Tone.ORANGE
            "resolu" -> "Résolu" to Tone.GRAY
            else -> status to Tone.GRAY
        }

    val quand: String
        get() {
            val f = SimpleDateFormat("d MMM 'à' HH:mm", Locale.FRANCE)
            if (status == "rdv" && rdv != null) return "Rendez-vous le " + f.format(Date((rdv * 1000).toLong()))
            return "Mis à jour le " + f.format(Date((updated * 1000).toLong()))
        }

    companion object {
        fun from(d: JSONObject, person: Person): SupportTicket? {
            val id = d.opt("id") as? String ?: return null
            val updated = d.optDouble("updated", 0.0).takeUnless { it.isNaN() } ?: 0.0
            return SupportTicket(
                tid = id,
                number = d.optInt("number", 0),
                task = d.text("task"),
                status = d.text("status").ifEmpty { "nouveau" },
                updated = updated,
                rdv = if (d.has("rdv") && !d.isNull("rdv")) d.optDouble("rdv") else null,
                assignee = d.text("assignee"),
                person = person,
            )
        }

        /** Tous les tickets de tous les utilisateurs, les plus récents d'abord. */
        fun merge(lists: List<List<SupportTicket>>): List<SupportTicket> = lists.flatten().sortedByDescending { it.updated }
    }
}

/** Tous les tickets formulés par tous les utilisateurs suivis, et les actions dessus. */
object TicketBoard {
    val tickets = mutableStateListOf<SupportTicket>()
    var loading by mutableStateOf(false)
    val errors = mutableStateListOf<String>()
    /** Ticket dont une action est en cours d'envoi. */
    var busy by mutableStateOf<String?>(null)

    val openCount get() = tickets.count { it.isOpen }

    fun load(people: List<Person>) {
        if (people.isEmpty()) { tickets.clear(); errors.clear(); return }
        loading = true
        pool.execute {
            val results = pool.invokeAll(people.map { p -> Callable { fetch(p) } }).map { it.get() }
            val all = SupportTicket.merge(results.map { it.first })
            val errs = results.mapNotNull { it.second }.sorted()
            mainThread.post {
                tickets.clear(); tickets.addAll(all)
                errors.clear(); errors.addAll(errs)
                loading = false
            }
        }
    }

    private fun fetch(p: Person): Pair<List<SupportTicket>, String?> {
        val fail = "Tickets de ${p.name.ifEmpty { "un utilisateur" }} indisponibles"
        return try {
            val req = Request.Builder().url(spaceBase(p) + "/tickets").build()
            supportHttp.newCall(req).execute().use { r ->
                if (r.code != 200) return emptyList<SupportTicket>() to fail
                val list = JSONObject(r.body?.string() ?: "").optJSONArray("tickets") ?: return emptyList<SupportTicket>() to fail
                (0 until list.length()).mapNotNull { i -> list.optJSONObject(i)?.let { SupportTicket.from(it, p) } } to null
            }
        } catch (_: Exception) { emptyList<SupportTicket>() to fail }
    }

    /** `take`, `close` ou `reopen`, puis relit la liste. `done` reçoit le message d'erreur, ou null. */
    fun act(t: SupportTicket, action: String, by: String, people: List<Person>, done: (String?) -> Unit) {
        busy = t.id
        pool.execute {
            val error = try {
                val body = JSONObject().put("action", action).put("by", by).toString().toRequestBody(json)
                val req = Request.Builder().url(spaceBase(t.person) + "/tickets/" + t.tid).post(body).build()
                supportHttp.newCall(req).execute().use { r ->
                    if (r.code == 200) null
                    else (try { JSONObject(r.body?.string() ?: "").text("error") } catch (_: Exception) { "" }).ifEmpty { "Action refusée" }
                }
            } catch (_: Exception) { "Serveur injoignable" }
            mainThread.post { busy = null; done(error); load(people) }
        }
    }
}

/** Un automate de la bibliothèque du support : le pack `.papai` tel quel, et chez qui il est appliqué. */
data class AutomateEntry(val id: String, val pack: String, val applied: List<String>, val created: Long) {
    private val obj: JSONObject get() = try { JSONObject(pack) } catch (_: Exception) { JSONObject() }
    val title get() = obj.text("title").ifEmpty { "Sans titre" }
    val detail get() = obj.text("description")
    val publisher get() = obj.text("publisher")
    val platforms: List<String> get() = obj.optJSONArray("platforms")?.let { a -> (0 until a.length()).map { a.text(it) } } ?: emptyList()
    val stepCount get() = obj.optJSONArray("steps")?.length() ?: 0
    val firstAction get() = obj.optJSONArray("actions")?.optJSONObject(0)?.text("do") ?: ""

    fun toJson(): JSONObject = JSONObject().put("id", id).put("pack", pack)
        .put("applied", JSONArray(applied)).put("created", created)

    companion object {
        /** Un `.papai` valide : `"papai": 1` et un titre. */
        fun isPack(text: String): Boolean = try {
            val o = JSONObject(text)
            o.optInt("papai", 0) == 1 && o.opt("title") is String
        } catch (_: Exception) { false }

        fun fromJson(o: JSONObject): AutomateEntry? {
            val id = o.opt("id") as? String ?: return null
            val pack = o.opt("pack") as? String ?: return null
            val a = o.optJSONArray("applied")
            return AutomateEntry(id, pack, a?.let { (0 until it.length()).map { i -> it.text(i) } } ?: emptyList(), o.optLong("created"))
        }
    }
}

/**
 * « Mes automates » : la bibliothèque du support, gardée sur ce téléphone (`automates.json`),
 * comme `AutomateLibrary` sur Mac et iPhone. Appliquer = importer le pack dans l'espace de
 * chaque utilisateur choisi (`POST …/k/<clé>/automations`), ce qui le valide côté serveur.
 */
object AutomateLibrary {
    val entries = mutableStateListOf<AutomateEntry>()
    /** Automate dont la feuille « Appliquer… » est ouverte (affichée par `Root`, au-dessus de tout). */
    var applying by mutableStateOf<AutomateEntry?>(null)
    private var file: File? = null

    fun init(ctx: Context) {
        val f = File(ctx.filesDir, "automates.json").also { file = it }
        val loaded = try {
            JSONArray(f.readText()).let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(AutomateEntry::fromJson) } }
        } catch (_: Exception) { null }
        entries.clear()
        if (loaded != null) entries.addAll(loaded) else seedExamples(ctx)
    }

    /** Premier lancement : les exemples livrés avec l'app (dossier `automations/` du dépôt). */
    private fun seedExamples(ctx: Context) {
        val names = try { ctx.assets.list("automates")?.filter { it.endsWith(".papai") }?.sorted() } catch (_: Exception) { null }
        names.orEmpty().reversed().forEach { n ->
            try { ctx.assets.open("automates/$n").bufferedReader().use { add(it.readText(), save = false) } } catch (_: Exception) {}
        }
        save()
    }

    fun add(pack: String, save: Boolean = true): AutomateEntry? {
        if (!AutomateEntry.isPack(pack)) return null
        val e = AutomateEntry(UUID.randomUUID().toString(), pack, emptyList(), System.currentTimeMillis() / 1000)
        entries.add(0, e)
        if (save) save()
        return e
    }

    fun remove(e: AutomateEntry) { entries.removeAll { it.id == e.id }; save() }

    private fun markApplied(e: AutomateEntry, keys: Collection<String>) {
        val i = entries.indexOfFirst { it.id == e.id }
        if (i < 0 || keys.isEmpty()) return
        entries[i] = entries[i].copy(applied = (entries[i].applied + keys).distinct())
        save()
    }

    /** Applique l'automate chez chacun ; `done` reçoit, par clé, "" si appliqué ou le message d'erreur. */
    fun apply(e: AutomateEntry, people: List<Person>, done: (Map<String, String>) -> Unit) {
        pool.execute {
            val results = people.associate { it.key to (applyTo(e, it) ?: "") }
            mainThread.post {
                markApplied(e, results.filterValues { it.isEmpty() }.keys)
                done(results)
            }
        }
    }

    private fun applyTo(e: AutomateEntry, p: Person): String? = try {
        val req = Request.Builder().url(spaceBase(p) + "/automations").post(e.pack.toRequestBody(json)).build()
        supportHttp.newCall(req).execute().use { r ->
            if (r.code == 200) null
            else (try { JSONObject(r.body?.string() ?: "").text("error") } catch (_: Exception) { "" }).ifEmpty { "Refusé par le serveur" }
        }
    } catch (_: Exception) { "Serveur injoignable" }

    private fun save() {
        val f = file ?: return
        try { f.writeText(JSONArray(entries.map { it.toJson() }).toString()) } catch (_: Exception) {}
    }
}
