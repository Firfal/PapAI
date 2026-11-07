package com.quentin.papai.aidant

enum class HomeCard { WELLBEING, ALERT, DICTATION, AUTOMATIONS }

fun homeCards(hasPendingAlert: Boolean, hasDictation: Boolean): List<HomeCard> = buildList {
    add(if (hasPendingAlert) HomeCard.ALERT else HomeCard.WELLBEING)
    if (hasDictation) add(HomeCard.DICTATION)
    add(HomeCard.AUTOMATIONS)
}
