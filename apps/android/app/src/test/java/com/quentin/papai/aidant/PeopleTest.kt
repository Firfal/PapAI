package com.quentin.papai.aidant

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PeopleTest {
    private val server = "https://papai.example"

    @Test
    fun postesDuServeur() {
        val spaces = JSONArray("""[
            {"key":"aaa","name":"Christine","label":"Comptabilité","online":true},
            {"key":"bbb","name":"","label":"Accueil"}
        ]""")
        assertEquals(listOf(
            Person("$server/k/aaa", "aaa", "Christine", "Comptabilité"),
            Person("$server/k/bbb", "bbb", "", "Accueil"),
        ), People.fromSpaces(spaces, server, emptyList()))
    }

    @Test
    fun clesInvalidesEtDoublonsIgnores() {
        val spaces = JSONArray("""[
            {"key":"ok-1_A"},{"key":"ok-1_A","name":"Autre"},{"key":""},{"key":"a/b"},{"key":"é"},
            {"key":42},{"name":"sans clé"},null,"texte",{"key":"${"x".repeat(201)}"},{"key":"${"y".repeat(200)}"}
        ]""")
        assertEquals(listOf("ok-1_A", "y".repeat(200)), People.fromSpaces(spaces, server, emptyList()).map { it.key })
        assertEquals(emptyList<Person>(), People.fromSpaces(null, server, emptyList()))
    }

    @Test
    fun ceQuOnSavaitNEstPasEffaceParDuVide() {
        val known = listOf(Person("$server/k/aaa", "aaa", "Christine", "Compta", "h1"))
        val list = People.fromSpaces(JSONArray("""[{"key":"aaa","name":"","label":null}]"""), server, known)
        assertEquals(known, list)
        val renamed = People.fromSpaces(JSONArray("""[{"key":"aaa","name":" Christine M. ","label":"RH"}]"""), server, known)
        assertEquals(Person("$server/k/aaa", "aaa", "Christine M.", "RH", "h1"), renamed[0])
    }

    @Test
    fun laListeDuServeurFaitFoi() {
        val known = listOf(Person("$server/k/old", "old", "Paul"))
        assertEquals(listOf("new"), People.fromSpaces(JSONArray("""[{"key":"new"}]"""), server, known).map { it.key })
    }

    @Test
    fun pasPlusDeCinqCents() {
        val spaces = JSONArray().apply { repeat(People.MAX + 10) { put(org.json.JSONObject().put("key", "k$it")) } }
        assertEquals(People.MAX, People.fromSpaces(spaces, server, emptyList()).size)
    }

    @Test
    fun prenomPuisService() {
        assertEquals("Christine", People.title(Person(server, "a", "Christine", "Comptabilité")))
        assertEquals("Comptabilité", People.detail(Person(server, "a", "Christine", "Comptabilité")))
        assertEquals("Accueil", People.title(Person(server, "a", "", "Accueil")))
        assertNull(People.detail(Person(server, "a", "", "Accueil")))
        assertNull(People.detail(Person(server, "a", "Christine", "Christine")))
        assertEquals("Poste", People.title(Person(server, "a")))
    }

    @Test
    fun demandeEnAttente() {
        listOf("waiting_consent", "planning", "awaiting_approval", "awaiting_helper").forEach { assertTrue(People.isAsking(it)) }
        listOf("active", "done", "stopped", null).forEach { assertFalse(People.isAsking(it)) }
    }
}
