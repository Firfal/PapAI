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
        repeat(People.MAX + 10) { list = People.upsert(list, Person("https://s/k/$it", "k$it")) }
        assertEquals(People.MAX, list.size)
    }

    @Test
    fun demandeEnAttente() {
        listOf("waiting_consent", "planning", "awaiting_approval", "awaiting_helper").forEach { assertTrue(People.isAsking(it)) }
        listOf("active", "done", "stopped", null).forEach { assertFalse(People.isAsking(it)) }
    }

    @Test fun orgLinks() {
        val host = "papai.example"
        val t = "sup-abcdefghijklmnop"
        assertEquals(Org("https://$host", t), Orgs.parse(t, host))
        assertEquals(Org("https://srv.fr", t), Orgs.parse("https://srv.fr/o/$t", host))
        assertEquals(Org("http://10.0.2.2:8000", t), Orgs.parse("http://10.0.2.2:8000/o/$t/", host))
        assertEquals(Org("https://srv.fr", t), Orgs.parse("papai://org?u=https%3A%2F%2Fsrv.fr%2F&t=$t", host))
        assertEquals(null, Orgs.parse("ins-abcdefghijklmnop", host))
        assertEquals(null, Orgs.parse("https://srv.fr/a/$t", host))
        assertEquals(null, Orgs.parse("papai://org?u=javascript:x&t=$t", host))
        val list = listOf(Org("https://a", t, "Acme"), Org("https://b", t), Org("https://c", "bad"))
        assertEquals(listOf(Org("https://a", t, "Acme")), Orgs.decode(Orgs.encode(list)))
    }
}
