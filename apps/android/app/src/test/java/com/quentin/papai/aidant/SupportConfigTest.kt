package com.quentin.papai.aidant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SupportConfigTest {
    private val t = "sup-abcdefghij"   // 14 caractères : le plus court accepté

    @Test fun jetonValide() {
        assertEquals(t, SupportConfig.token(t))
        assertEquals(t, SupportConfig.token("  $t\n"))
        val longest = "sup-" + "a".repeat(100)
        assertEquals(longest, SupportConfig.token(longest))
        assertEquals("sup-AZ_az-09_xyz", SupportConfig.token("sup-AZ_az-09_xyz"))
    }

    @Test fun jetonRefuse() {
        for (bad in listOf(null, "", "sup-", "sup-abcdefghi", "sup-" + "a".repeat(101), "ins-abcdefghijklmnop",
            "SUP-abcdefghijkl", "sup-abcdefghij!", "sup-abc defghijkl", "sup-abcdéfghijkl", "https://x/o/$t")) {
            assertNull(bad, SupportConfig.token(bad))
        }
        assertNull(SupportConfig.token(42))
    }

    @Test fun serveurRameneASonOrigine() {
        assertEquals("https://srv.fr", SupportConfig.server("https://srv.fr"))
        assertEquals("https://srv.fr", SupportConfig.server(" HTTPS://SRV.fr/k/abc?x=1#y "))
        assertEquals("http://10.0.2.2:8000", SupportConfig.server("http://10.0.2.2:8000/"))
        assertEquals("https://srv.fr:443", SupportConfig.server("https://srv.fr:443"))
    }

    @Test fun serveurRefuse() {
        for (bad in listOf(null, "", "srv.fr", "ftp://srv.fr", "javascript:alert(1)", "https://user:mdp@srv.fr",
            "https://user@srv.fr", "https:///chemin", "papai://org", "https://srv fr")) {
            assertNull(bad, SupportConfig.server(bad))
        }
        assertNull(SupportConfig.server(42))
    }

    @Test fun premiereSourceValideLEmporte() {
        val managed = mapOf("supportToken" to t, "server" to "https://it.acme.fr/x")
        val demo = mapOf("supportToken" to "sup-demodemodemo", "server" to "https://demo.fr")
        assertEquals(SupportOrg("https://it.acme.fr", t), SupportConfig.resolve(listOf(managed, demo)))
        // Source gérée vide ou invalide : la démo prend le relais, avec son propre serveur.
        assertEquals(SupportOrg("https://demo.fr", "sup-demodemodemo"),
            SupportConfig.resolve(listOf(emptyMap(), mapOf("supportToken" to "faux"), demo)))
    }

    @Test fun serveurOfficielParDefaut() {
        val official = SupportOrg(SupportConfig.OFFICIAL_SERVER, t)
        assertEquals(official, SupportConfig.resolve(listOf(mapOf("supportToken" to t))))
        assertEquals(official, SupportConfig.resolve(listOf(mapOf("supportToken" to t, "server" to ""))))
        assertEquals(official, SupportConfig.resolve(listOf(mapOf("supportToken" to t, "server" to "ftp://x"))))
        // Le serveur d'une autre source n'est pas repris.
        assertEquals(official, SupportConfig.resolve(listOf(mapOf("server" to "https://autre.fr"), mapOf("supportToken" to t))))
    }

    @Test fun rienDeConfigure() {
        assertNull(SupportConfig.resolve(emptyList()))
        assertNull(SupportConfig.resolve(listOf(emptyMap(), mapOf("supportToken" to "", "server" to ""))))
    }

    @Test fun nomDuSupport() {
        assertEquals("Marc · IT", SupportConfig.name("  Marc · IT "))
        assertNull(SupportConfig.name(""))
        assertNull(SupportConfig.name("null"))
        assertNull(SupportConfig.name(null))
        assertEquals(80, SupportConfig.name("a".repeat(200))!!.length)
    }
}
