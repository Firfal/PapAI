package com.quentin.papai.aidant

import org.junit.Assert.*
import org.junit.Test
import java.net.URLEncoder

class PairingPolicyTest {
    @Test fun opaqueInvitationsAndLegacyRoutes() {
        val token = "Abc_def-1234567890123456"
        for (route in listOf("/p/123456", "/i/$token", "/k/key/p/123456")) {
            val url = "https://trusted.example$route"
            for (text in listOf(url, "papai://pair?u=" + URLEncoder.encode(url, "UTF-8"))) {
                val link = PairLink.parse(text)!!
                assertEquals(url, link.endpoint(""))
                assertFalse(link.isManual)
                assertNull(PairingPolicy.invitationError(text, false))
            }
        }
        assertEquals("https://trusted.example/p/654321",
            PairLink("https://trusted.example/k/old", null).endpoint("654321"))
    }

    @Test fun malformedOpaqueInvitationsAreRejected() {
        for (route in listOf("/i/short", "/i/" + "a".repeat(129), "/i/abcdefghijklmnopqrstuv!",
            "/i/abcdefghijklmnopqrstuv/extra", "/extra/p/123456", "/p/1234567", "/p/１２３４５６")) {
            assertNull(route, PairLink.parse("https://trusted.example$route"))
        }
        assertNotNull(PairingPolicy.invitationError("http://public.example/i/abcdefghijklmnopqrstuv", true))
    }

    @Test fun onlyRefusalAndTimeoutRequireNewCredentials() {
        for (status in listOf(200, 400, 403, 408, 409, 429)) {
            for (refused in listOf(false, true)) {
                assertEquals(status == 408 || status == 409 || (status == 403 && refused), PairingPolicy.needsNew(status, refused))
            }
        }
        assertEquals("Demandez à l’utilisateur d'appuyer sur Accepter sur son ordinateur (2 min).", PairingPolicy.instruction)
    }
    @Test fun successRequiresHttp200AndBooleanOk() {
        assertTrue(PairingPolicy.isSuccess(200, true))
        for (status in listOf(400, 403, 408, 409, 429, 500)) assertFalse(PairingPolicy.isSuccess(status, true))
        for (ok in listOf(null, false, "true", "", 1)) assertFalse(PairingPolicy.isSuccess(200, ok))
    }

    @Test fun waitingCopy() {
        assertEquals("En attente de l'accord sur l'ordinateur…", PairingPolicy.waiting)
    }
    @Test fun officialServerRequiresExactHttpsOrigin() {
        val host = PairingPolicy.officialHost
        assertTrue(PairingPolicy.isOfficial("https://$host"))
        assertTrue(PairingPolicy.isOfficial("https://$host:443"))
        for (base in listOf("http://$host", "https://sub.$host", "https://$host.evil.com", "https://$host:8443", "https://papai-450417131703.europe-west1.run.app", "not a url")) {
            assertFalse(base, PairingPolicy.isOfficial(base))
        }
    }

    @Test fun presentationNeverUsesInvitationName() {
        for (base in listOf("https://${PairingPolicy.officialHost}", "http://10.0.2.2:8000")) {
            val link = PairLink(base, "123456", "Pirate")
            val copy = PairingPolicy.presentation(link)
            assertEquals(PairingPolicy.presentation(link.copy(senior = null)), copy)
            assertFalse(copy.toString().contains("Pirate"))
            assertEquals("Relier ce téléphone", copy.title)
            assertEquals("Votre lien avec l’utilisateur", copy.relationLabel)
        }
    }

    @Test fun serverLabelsMatchSafetyCopy() {
        assertEquals("Serveur PapAI officiel", PairingPolicy.presentation(PairLink("https://${PairingPolicy.officialHost}", null)).server)
        assertEquals("Serveur inconnu : ne continuez que si l’utilisateur vous a donné ce lien lui-même",
            PairingPolicy.presentation(PairLink("http://10.0.2.2:8000", null)).server)
    }

    @Test fun refusalsAreExactAndActionable() {
        val expected = "Ce lien n'est pas sûr. Demandez un nouveau QR code depuis l'ordinateur de l’utilisateur (Réglages > Mon support)."
        for (debug in listOf(false, true)) {
            for (text in listOf("http://example.com/p/123456", "papai://pair?u=http%3A%2F%2Fexample.com%2Fp%2F123456", "illisible", "", "https://foreign.example/qr")) {
                assertEquals(expected, PairingPolicy.invitationError(text, debug))
            }
            assertEquals(expected, PairingPolicy.error("http://example.com", debug))
        }
    }

    @Test fun validInvitationHasNoRefusal() {
        assertNull(PairingPolicy.invitationError("https://${PairingPolicy.officialHost}/p/123456", false))
        assertNull(PairingPolicy.invitationError("http://10.0.2.2:8000/p/123456", true))
        assertEquals(PairingPolicy.refusal, PairingPolicy.invitationError("http://10.0.2.2:8000/p/123456", false))
    }

    @Test fun publicHttpIsAlwaysRejected() {
        for (debug in listOf(false, true)) {
            for (host in listOf("example.com", "8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.0.1", "localhost.example.com", "010.0.0.1")) {
                assertNotNull(host, PairingPolicy.error("http://$host", debug))
            }
        }
    }

    @Test fun httpsIsAccepted() {
        for (debug in listOf(false, true)) {
            assertNull(PairingPolicy.error("https://example.com:8443/k/family", debug))
        }
    }

    @Test fun localHttpIsDebugOnly() {
        for (host in listOf("127.0.0.1", "localhost", "10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.2", "papai.local")) {
            assertNull(host, PairingPolicy.error("http://$host:8000", true))
            assertNotNull(host, PairingPolicy.error("http://$host:8000", false))
        }
    }

    @Test fun malformedAndNonHttpAddressesAreRejected() {
        for (url in listOf("", "not a url", "ftp://example.com", "https://user@example.com", "https://example.com@evil.com", "http://10.999.0.1", "https://example.com?next=evil")) {
            assertNotNull(url, PairingPolicy.error(url, true))
        }
    }

    @Test fun responseCannotChangeOrigin() {
        val link = PairLink("https://trusted.example:8443/k/family", "123456")
        for (server in listOf(null, "", "https://evil.example", "http://trusted.example:8443", "https://trusted.example:9999", "not a url")) {
            assertEquals("https://trusted.example:8443", PairingPolicy.responseOrigin(link, server))
        }
    }

    @Test fun invitationKeepsNamePendingAndPreservesPairingPath() {
        val target = "https://trusted.example/k/family/p/123456"
        val link = PairLink.parse("papai://pair?u=${URLEncoder.encode(target, "UTF-8")}&n=Marie")!!
        assertEquals("Marie", link.senior)
        assertEquals("https://trusted.example/k/family", link.base)
        assertEquals("123456", link.code)
        assertNull(PairingPolicy.error(link.base, false))
        assertEquals(link.copy(senior = null), PairLink.parse(target))
    }

    @Test fun invalidInvitationsAreRejected() {
        for (text in listOf("", "papai://pair", "papai://open?u=x", "https://host/p/123", "https://user@host/p/123456")) {
            assertNull(text, PairLink.parse(text))
        }
    }
}
