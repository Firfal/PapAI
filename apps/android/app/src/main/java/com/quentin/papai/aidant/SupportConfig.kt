package com.quentin.papai.aidant

import android.content.Context
import android.content.RestrictionsManager
import java.net.URI

/**
 * L'organisation du support, déposée par le service informatique : rien ne se saisit dans l'app.
 * Avec le jeton support (`sup-…`), le support voit d'office tous les postes de l'organisation
 * (`GET /o/<jeton>/spaces`) et reçoit leurs demandes. Pas de liaison poste par poste.
 *
 * Sources, dans l'ordre (la première qui porte un jeton valide l'emporte) :
 * - restrictions gérées (EMM / Android Enterprise) : `supportToken`, `server`, `supportName`,
 *   déclarées dans `res/xml/app_restrictions.xml` ;
 * - démo sans EMM : `BuildConfig.PAPAI_SUPPORT_TOKEN` / `PAPAI_SERVER`, lus à la compilation dans
 *   le fichier local non suivi `apps/android/support.local.properties` (voir le README).
 */
data class SupportOrg(val server: String, val token: String)

/** Validation et choix de la source, sans dépendance Android : testés sur la JVM. */
object SupportConfig {
    const val OFFICIAL_SERVER = "https://papai-450417131702.europe-west1.run.app"

    /** `sup-` puis des caractères d'URL, 14 à 104 caractères en tout. */
    private val TOKEN = Regex("^sup-[A-Za-z0-9_-]{10,100}$")

    /** Jeton support valide, sinon null. */
    fun token(raw: Any?): String? = (raw as? String)?.trim()?.takeIf { TOKEN.matches(it) }

    /**
     * `https://hôte[:port]`, sans chemin ni identifiants ; null si ce n'est pas une adresse http(s).
     * La valeur vient de l'administrateur (restriction gérée), pas d'un lien reçu.
     */
    fun server(raw: Any?): String? {
        val s = (raw as? String)?.trim().orEmpty()
        if (s.isEmpty()) return null
        val u = try { URI(s) } catch (_: Exception) { return null }
        val scheme = u.scheme?.lowercase() ?: return null
        if (scheme != "https" && scheme != "http") return null
        val host = u.host?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        if (u.rawUserInfo != null || u.port > 65535) return null
        return "$scheme://$host" + if (u.port == -1) "" else ":${u.port}"
    }

    /**
     * Première source qui porte un jeton valide ; le serveur vient de la même source
     * (serveur PapAI officiel s'il est absent ou invalide).
     */
    fun resolve(sources: List<Map<String, Any?>>): SupportOrg? {
        for (s in sources) {
            val t = token(s["supportToken"]) ?: continue
            return SupportOrg(server(s["server"]) ?: OFFICIAL_SERVER, t)
        }
        return null
    }

    /** Nom affiché du support (facultatif) : texte court, sinon null. */
    fun name(raw: Any?): String? = cleanText(raw as? String).take(80).ifEmpty { null }
}

private fun managedRestrictions(ctx: Context): Map<String, Any?> {
    val b = try {
        ctx.getSystemService(RestrictionsManager::class.java)?.applicationRestrictions
    } catch (_: Exception) { null } ?: return emptyMap()
    return mapOf("supportToken" to b.getString("supportToken"), "server" to b.getString("server"),
        "supportName" to b.getString("supportName"))
}

/** Organisation configurée sur ce téléphone, ou null : écran « Aucune organisation configurée ». */
fun loadSupportOrg(ctx: Context): SupportOrg? = SupportConfig.resolve(listOf(
    managedRestrictions(ctx),
    mapOf("supportToken" to BuildConfig.PAPAI_SUPPORT_TOKEN, "server" to BuildConfig.PAPAI_SERVER),
))

/** Nom du support géré par l'administrateur (`supportName`), sinon null. */
fun loadSupportName(ctx: Context): String? = SupportConfig.name(managedRestrictions(ctx)["supportName"])
