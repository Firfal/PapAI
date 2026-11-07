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
    const val MAX = 200
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

/** Une organisation (service IT) suivie par ce support : son jeton liste tous ses postes. */
data class Org(val server: String, val token: String, val name: String = "")

object Orgs {
    private val TOKEN = Regex("^sup-[A-Za-z0-9_-]{10,100}$")

    /** Lien donné par l'IT : `https://…/o/sup-…`, `papai://org?u=…&t=sup-…`, ou le jeton seul. */
    fun parse(input: String, officialHost: String): Org? {
        val s = input.trim()
        if (TOKEN.matches(s)) return Org("https://$officialHost", s)
        val u = try { java.net.URI(s) } catch (_: Exception) { return null }
        if (u.scheme == "papai" && u.host == "org") {
            val q = (u.rawQuery ?: "").split("&").mapNotNull { kv ->
                val p = kv.split("=", limit = 2)
                if (p.size == 2) p[0] to java.net.URLDecoder.decode(p[1], "UTF-8") else null
            }.toMap()
            val base = q["u"]?.trimEnd('/') ?: return null
            val t = q["t"] ?: return null
            return if (TOKEN.matches(t) && (base.startsWith("https://") || base.startsWith("http://"))) Org(base, t) else null
        }
        if ((u.scheme == "https" || u.scheme == "http") && u.host != null) {
            val parts = (u.path ?: "").trim('/').split("/")
            if (parts.size == 2 && parts[0] == "o" && TOKEN.matches(parts[1])) {
                val port = if (u.port == -1) "" else ":${u.port}"
                return Org("${u.scheme}://${u.host}$port", parts[1])
            }
        }
        return null
    }

    fun decode(raw: String?): List<Org> = try {
        val a = JSONArray(raw ?: "[]")
        (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            val s = o.text("server"); val t = o.text("token")
            if (s.isEmpty() || !TOKEN.matches(t)) null else Org(s, t, o.text("name"))
        }.distinctBy { it.token }.take(10)
    } catch (_: Exception) { emptyList() }

    fun encode(list: List<Org>): String = JSONArray().apply {
        list.take(10).forEach { put(JSONObject().put("server", it.server).put("token", it.token).put("name", it.name)) }
    }.toString()
}
