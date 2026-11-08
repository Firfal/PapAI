package com.quentin.papai.aidant

import org.json.JSONArray

/**
 * Un poste de l'organisation suivi par ce support : un ordinateur, son espace et sa clé.
 * La liste vient du serveur (`GET /o/<jeton support>/spaces`) : rien ne s'ajoute ni ne se retire ici.
 */
data class Person(
    val server: String,
    val key: String,
    /** Prénom de l'employé (compte de l'ordinateur), sinon vide. */
    val name: String = "",
    /** Nom donné par le poste à son inscription (nom de l'ordinateur, service). */
    val label: String = "",
    val helperId: String = "",
)

object People {
    const val MAX = 500
    private val KEY = Regex("^[A-Za-z0-9_-]{1,200}$")
    private val asking = setOf("waiting_consent", "planning", "awaiting_approval", "awaiting_helper")

    /**
     * Postes renvoyés par `/o/<jeton>/spaces`, sans doublon ; ce qu'on savait déjà (prénom
     * appris par `hello`, identifiant de support) n'est pas effacé par du vide.
     */
    fun fromSpaces(spaces: JSONArray?, server: String, known: List<Person>): List<Person> {
        if (spaces == null) return emptyList()
        val seen = HashSet<String>()
        val out = ArrayList<Person>()
        for (i in 0 until spaces.length()) {
            val s = spaces.optJSONObject(i) ?: continue
            val k = s.opt("key") as? String ?: continue
            if (!KEY.matches(k) || !seen.add(k)) continue
            val old = known.firstOrNull { it.key == k }
            out.add(Person(
                server = "$server/k/$k",
                key = k,
                name = s.text("name").ifEmpty { old?.name.orEmpty() },
                label = s.text("label").ifEmpty { old?.label.orEmpty() },
                helperId = old?.helperId.orEmpty(),
            ))
            if (out.size >= MAX) break
        }
        return out
    }

    /** « Christine » : le prénom, sinon le nom du poste. */
    fun title(p: Person): String = p.name.ifEmpty { p.label.ifEmpty { "Poste" } }

    /** « Comptabilité » sous le prénom, seulement s'il dit autre chose. */
    fun detail(p: Person): String? = p.label.takeIf { it.isNotEmpty() && p.name.isNotEmpty() && it != p.name }

    /** Une demande attend le support : aide demandée, plan à valider, question de Holo. */
    fun isAsking(state: String?): Boolean = state in asking
}
