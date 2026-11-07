package com.quentin.papai.aidant

import org.junit.Assert.*
import org.junit.Test

class HomeCardsTest {
    @Test fun pendingAlertIsFirstAndHidesWellbeing() {
        for (dictation in listOf(false, true)) {
            val cards = homeCards(hasPendingAlert = true, hasDictation = dictation)
            assertEquals(HomeCard.ALERT, cards.first())
            assertFalse(cards.contains(HomeCard.WELLBEING))
            assertEquals(HomeCard.AUTOMATIONS, cards.last())
        }
    }

    @Test fun noAlertShowsWellbeingEvenWithoutOtherContent() {
        assertEquals(listOf(HomeCard.WELLBEING, HomeCard.AUTOMATIONS), homeCards(false, false))
        assertEquals(listOf(HomeCard.WELLBEING, HomeCard.DICTATION, HomeCard.AUTOMATIONS), homeCards(false, true))
    }

    @Test fun alertPrecedesDictationAndAutomations() {
        assertEquals(listOf(HomeCard.ALERT, HomeCard.DICTATION, HomeCard.AUTOMATIONS), homeCards(true, true))
    }
}
