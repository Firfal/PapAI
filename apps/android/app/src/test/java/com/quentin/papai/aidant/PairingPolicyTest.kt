package com.quentin.papai.aidant

import org.junit.Assert.*
import org.junit.Test
import java.net.URLEncoder

class PairingPolicyTest {
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

    @Test fun workingLinkRequiresExplicitConfirmation() {
        assertTrue(PairingPolicy.needsConfirmation(hasWorkingLink = true))
        assertFalse(PairingPolicy.needsConfirmation(hasWorkingLink = true, confirmed = true))
        assertFalse(PairingPolicy.needsConfirmation(hasWorkingLink = false))
        assertTrue(PairingPolicy.needsConfirmation(hasWorkingLink = true, confirmed = false))
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
