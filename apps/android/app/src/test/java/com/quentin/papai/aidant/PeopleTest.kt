package com.quentin.papai.aidant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeopleTest {
    private val sophie = Person("https://papai.example/k/aaa", "aaa", "Sophie", "h1", "sa fille")
    private val paul = Person("https://papai.example/k/bbb", "bbb", "Paul")

    @Test
    fun allerRetourJson() {
        assertEquals(listOf(sophie, paul), People.decode(People.encode(listOf(sophie, paul))))
    }

    @Test
    fun jsonAbimeOuIncompletIgnore() {
        assertEquals(emptyList<Person>(), People.decode("pas du json"))
        assertEquals(emptyList<Person>(), People.decode(null))
        assertEquals(listOf(paul), People.decode("""[{"server":"","key":"x"},{"server":"https://papai.example/k/bbb","key":"bbb","name":"Paul"}]"""))
    }

    @Test
    fun memeCleUneSeuleFois() {
        val twice = People.encode(listOf(sophie, sophie.copy(name = "Autre")))
        assertEquals(listOf(sophie), People.decode(twice))
    }

    @Test
    fun ajoutPuisMiseAJourSansEffacer() {
        val list = People.upsert(listOf(sophie), paul)
        assertEquals(listOf(sophie, paul), list)
        val renamed = People.upsert(list, Person(sophie.server, "aaa", "", "", ""))
        assertEquals(sophie, renamed[0])
        assertEquals("Sophie M.", People.upsert(list, sophie.copy(name = "Sophie M."))[0].name)
    }

    @Test
    fun pasPlusDeCinquante() {
        var list = emptyList<Person>()
        repeat(60) { list = People.upsert(list, Person("https://s/k/$it", "k$it")) }
        assertEquals(People.MAX, list.size)
    }

    @Test
    fun demandeEnAttente() {
        listOf("waiting_consent", "planning", "awaiting_approval", "awaiting_helper").forEach { assertTrue(People.isAsking(it)) }
        listOf("active", "done", "stopped", null).forEach { assertFalse(People.isAsking(it)) }
    }
}
