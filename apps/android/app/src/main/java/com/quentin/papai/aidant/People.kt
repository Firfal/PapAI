package com.quentin.papai.aidant

import org.json.JSONArray
import org.json.JSONObject

/** Une personne aidée suivie par ce support : un ordinateur, son espace et sa clé. */
data class Person(
    val server: String,
    val key: String,
    val name: String = "",
    val helperId: String = "",
    val relation: String = "",
)

object People {
    const val MAX = 50
    private val asking = setOf("waiting_consent", "planning", "awaiting_approval", "awaiting_helper")

    fun decode(raw: String?): List<Person> = try {
        val a = JSONArray(raw ?: "[]")
        (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            val s = o.text("server")
            val k = o.text("key")
            if (s.isEmpty() || k.isEmpty()) null
            else Person(s, k, o.text("name"), o.text("helperId"), o.text("relation"))
        }.distinctBy { it.key }.take(MAX)
    } catch (_: Exception) { emptyList() }

    fun encode(list: List<Person>): String = JSONArray().apply {
        list.take(MAX).forEach { p ->
            put(JSONObject().put("server", p.server).put("key", p.key).put("name", p.name)
                .put("helperId", p.helperId).put("relation", p.relation))
        }
    }.toString()

    /** Ajoute ou met à jour la personne de même clé, sans effacer par du vide ce qu'on savait. */
    fun upsert(list: List<Person>, p: Person): List<Person> {
        val i = list.indexOfFirst { it.key == p.key }
        if (i < 0) return (list + p).take(MAX)
        val old = list[i]
        val merged = p.copy(
            name = p.name.ifEmpty { old.name },
            helperId = p.helperId.ifEmpty { old.helperId },
            relation = p.relation.ifEmpty { old.relation },
        )
        return list.toMutableList().also { it[i] = merged }
    }

    /** Une demande attend le support : aide demandée, plan à valider, question de Holo. */
    fun isAsking(state: String?): Boolean = state in asking
}
