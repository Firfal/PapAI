package com.quentin.papai.aidant

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SupportDataTest {
    private val christine = Person("http://10.0.2.2:8000/k/cle1", "cle1", "Christine", "Poste compta")
    private val poste = Person("http://10.0.2.2:8000/k/cle2/", "cle2", "", "Poste accueil")

    private fun ticket(id: String, status: String, updated: Double, p: Person = christine) =
        SupportTicket.from(JSONObject().put("id", id).put("number", 7).put("task", "Imprimante").put("status", status)
            .put("updated", updated).put("assignee", "Marc"), p)!!

    @Test fun ticketLu() {
        val t = ticket("a1", "nouveau", 1_700_000_000.0)
        assertEquals("T-0007", t.label)
        assertEquals("cle1/a1", t.id)
        assertEquals("Nouveau" to Tone.BLUE, t.statut)
        assertTrue(t.isOpen && t.canTake)
        assertEquals("Christine", t.personName)
        assertTrue(t.quand.startsWith("Mis à jour le "))
    }

    @Test fun ticketSansIdIgnore() {
        assertNull(SupportTicket.from(JSONObject().put("task", "x"), christine))
    }

    @Test fun statutsEtActions() {
        val enCours = ticket("b", "en_cours", 1.0)
        assertTrue(enCours.isOpen); assertFalse(enCours.canTake)
        val resolu = ticket("c", "resolu", 1.0)
        assertFalse(resolu.isOpen); assertFalse(resolu.canTake)
        assertEquals("Résolu" to Tone.GRAY, resolu.statut)
        assertEquals("Rendez-vous" to Tone.VIOLET, ticket("d", "rdv", 1.0).statut)
        assertEquals("À reprendre" to Tone.ORANGE, ticket("e", "a_reprendre", 1.0).statut)
        assertEquals("Poste accueil", ticket("f", "nouveau", 1.0, poste).personName)
    }

    @Test fun ticketsDeTousLesPostesLesPlusRecentsDabord() {
        val all = SupportTicket.merge(listOf(
            listOf(ticket("a", "nouveau", 10.0), ticket("b", "resolu", 30.0)),
            listOf(ticket("c", "en_attente", 20.0, poste)),
        ))
        assertEquals(listOf("cle1/b", "cle2/c", "cle1/a"), all.map { it.id })
    }

    @Test fun adresseDeLespace() {
        assertEquals("http://10.0.2.2:8000/k/cle2", spaceBase(poste))
        assertEquals("http://h/k/x", spaceBase(Person("h/k/x", "x")))
    }

    @Test fun packPapai() {
        val pack = """{"papai":1,"title":"Wi-Fi","description":"Ouvre le Wi-Fi","publisher":"IT","platforms":["mac","windows"],
            "actions":[{"do":"open_settings","page":"wifi"}],"steps":[{"instruction":"a"},{"instruction":"b"}]}"""
        assertTrue(AutomateEntry.isPack(pack))
        assertFalse(AutomateEntry.isPack("""{"papai":2,"title":"x"}"""))
        assertFalse(AutomateEntry.isPack("""{"papai":1}"""))
        assertFalse(AutomateEntry.isPack("pas du json"))
        val e = AutomateEntry("id", pack, listOf("cle1"), 5)
        assertEquals("Wi-Fi", e.title); assertEquals(2, e.stepCount); assertEquals("open_settings", e.firstAction)
        assertEquals(listOf("mac", "windows"), e.platforms)
        val back = AutomateEntry.fromJson(e.toJson())!!
        assertEquals(e, back)
    }

    @Test fun consigneModifierEtape() {
        val s = EditedStep(1, "Aller dans Images", listOf("Ouvrir le Finder", "Aller dans Images"))
        assertEquals("Étape 2 : remplacer « Aller dans Images » par « Aller dans Bureau ». " +
            "Plan actuel : 1. Ouvrir le Finder ; 2. Aller dans Images. Garde les autres étapes telles quelles et propose le plan corrigé.",
            s.instruction("Aller dans Bureau"))
    }
}
