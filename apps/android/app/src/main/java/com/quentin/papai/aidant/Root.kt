package com.quentin.papai.aidant

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import java.util.Calendar

@Composable
fun Root() {
    val m = Helper
    LaunchedEffect(m.isConfigured, m.sheet) {
        if (!m.isConfigured && m.sheet == null) m.sheet = AppSheet.Settings
    }
    Box(Modifier.fillMaxSize().background(Soin.bg)) {
        Column(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
            Header(m.helperName ?: "Support") { m.sheet = AppSheet.Settings }
            if (m.isConfigured) PeopleRow()
            if (m.isConfigured && !m.connected) {
                LostBanner(Modifier.padding(horizontal = 20.dp).padding(bottom = 10.dp))
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (m.isConfigured) when (m.screen) {
                    Screen.IDLE -> IdleScreen()
                    Screen.WAITING -> WaitingScreen("En attente de l'autorisation de ${m.senior}")
                    Screen.PLANNING -> WaitingScreen("Holo regarde l'écran…")
                    Screen.APPROVAL -> ApprovalScreen()
                    Screen.ACTIVE -> ActiveScreen()
                    Screen.HELPER -> HelperScreen()
                    Screen.DONE -> DoneScreen()
                    Screen.STOPPED -> StoppedScreen()
                }
            }
        }
        AnimatedVisibility(
            m.toast != null, Modifier.align(Alignment.BottomCenter).systemBarsPadding().padding(bottom = 110.dp, start = 20.dp, end = 20.dp),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) {
            T(m.toast ?: "", 15.sp, FontWeight.SemiBold, Color.White,
                Modifier.clip(RoundedCornerShape(50)).background(Soin.ink).padding(horizontal = 18.dp, vertical = 12.dp),
                TextAlign.Center)
        }
        when (val s = m.sheet) {
            AppSheet.Settings -> Sheet(dismissable = m.isConfigured) { SettingsSheet() }
            is AppSheet.Pair -> Sheet(dismissable = !m.pairBusy) { PairSheet(s.link) }
            null -> {}
        }
        if (m.pairingRefused) PairingRefusal()
    }
}

/** Feuille plein écran au-dessus de l'app (retour = fermer, si permis). */
@Composable
fun Sheet(dismissable: Boolean = true, onClose: () -> Unit = { Helper.sheet = null }, content: @Composable () -> Unit) {
    BackHandler { if (dismissable) onClose() }
    Box(
        Modifier.fillMaxSize().background(Soin.bg).clickable(enabled = false) {}
            .systemBarsPadding().imePadding(),
    ) { content() }
}

@Composable
fun Header(name: String, onAvatar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(Soin.accentSoft).clickable(onClick = onAvatar),
            contentAlignment = Alignment.Center,
        ) { T(name.take(1).uppercase(), 20.sp, FontWeight.Bold, Soin.accent) }
        Column(Modifier.weight(1f)) {
            val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            T(if (h >= 19 || h < 5) "Bonsoir" else "Bonjour", 14.sp, color = Soin.secondary)
            T(name, 20.sp, FontWeight.SemiBold)
        }
        Box(Modifier.size(48.dp).clip(CircleShape).background(Soin.card).clickable(onClick = onAvatar), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Settings, "Réglages", tint = Soin.ink)
        }
    }
}

fun connectionLine(now: Long): String {
    val m = Helper
    if (m.connected) return "Connecté à ${m.displayHost}"
    val e = m.linkError ?: return "Connexion à ${m.displayHost}…"
    val at = m.retryAt ?: return e
    val n = ((at - now + 999) / 1000).toInt()
    return if (n > 0) "$e, nouvel essai dans $n s" else "$e, nouvel essai…"
}

/** État de la connexion quand elle ne marche pas : la vraie raison, pas un « reconnexion » muet. */
@Composable
fun LostBanner(modifier: Modifier = Modifier) {
    val m = Helper
    val now = rememberNow()
    Column(modifier.fillMaxWidth().soinCard(Soin.ink).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            if (m.linkError == null || m.retryAt != null) {
                CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
            } else Icon(Icons.Default.Warning, null, Modifier.size(16.dp), tint = Color.White)
            T(connectionLine(now), 14.sp, FontWeight.SemiBold, Color.White)
        }
        if (m.linkError != null) {
            T("Vérifier les réglages", 14.sp, FontWeight.SemiBold, Color.White,
                Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.18f))
                    .clickable { m.sheet = AppSheet.Settings }.padding(horizontal = 14.dp, vertical = 7.dp))
        }
    }
}

// Écrans simples

@Composable
fun IdleScreen() {
    val m = Helper
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        homeCards(m.lastAlert != null, m.liveDictation != null).forEach { card ->
            when (card) {
                HomeCard.WELLBEING -> Column(Modifier.fillMaxWidth().soinCard(Soin.accentSoft, 28.dp).padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    T("Rien à signaler pour ${m.senior}", 28.sp, FontWeight.Bold)
                    T("Vous serez prévenu dès qu'une demande d'aide arrive.", 16.sp, color = Soin.secondary)
                }
                HomeCard.DICTATION -> m.liveDictation?.let { live ->
                    Column(Modifier.fillMaxWidth().soinCard(radius = 24.dp).padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Default.GraphicEq, null, Modifier.size(16.dp), tint = Soin.accent)
                            T("${m.seniorTitle} est en train de parler", 13.sp, FontWeight.SemiBold, Soin.accent)
                        }
                        T("« $live »", 20.sp, FontWeight.SemiBold)
                    }
                }
                HomeCard.ALERT -> m.lastAlert?.let { a ->
                    Column(Modifier.fillMaxWidth().soinCard().padding(18.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        T(a.title, 16.sp, FontWeight.SemiBold)
                        if (a.detail.isNotEmpty()) T(a.detail, 14.sp, color = Soin.secondary)
                    }
                }
                HomeCard.AUTOMATIONS -> {
                    T("Derniers automatismes", 17.sp, FontWeight.SemiBold)
                    if (m.lessons.isEmpty()) T("Aucun automatisme pour l'instant.", 15.sp, color = Soin.secondary)
                    else Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        m.lessons.take(5).forEach { l ->
                            Row(Modifier.fillMaxWidth().soinCard().padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Box(Modifier.size(32.dp).clip(CircleShape).background(Soin.accentSoft), contentAlignment = Alignment.Center) {
                                    Icon(Icons.Default.Check, null, Modifier.size(16.dp), tint = Soin.accent)
                                }
                                Column {
                                    T(l.title, 16.sp, FontWeight.SemiBold)
                                    T("${l.steps} étape${if (l.steps > 1) "s" else ""}", 13.sp, color = Soin.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun WaitingScreen(text: String) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        RequestCard()
        Row(Modifier.padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), color = Soin.accent, strokeWidth = 2.dp)
            T(text, 16.sp, FontWeight.Medium, Soin.secondary)
        }
    }
}

@Composable
fun StoppedScreen() {
    val m = Helper
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(64.dp).clip(CircleShape).background(Soin.card), contentAlignment = Alignment.Center) {
            Icon(if (m.iRefusedPlan) Icons.Default.Close else Icons.Default.Pause, null, tint = Soin.ink)
        }
        Spacer(Modifier.height(10.dp))
        T(if (m.iRefusedPlan) "Vous avez refusé le plan" else "${m.seniorTitle} a arrêté l'assistance", 22.sp,
            FontWeight.Bold, align = TextAlign.Center)
        Spacer(Modifier.height(10.dp))
        T("Rien n'a été fait sur son ordinateur.", 15.sp, color = Soin.secondary, align = TextAlign.Center)
        Spacer(Modifier.weight(2f))
    }
}

/** Carte menthe de la demande : qui, quand, quoi, et la dernière capture. */
@Composable
fun RequestCard(onThumb: (() -> Unit)? = null) {
    val m = Helper
    val now = rememberNow(20_000)
    val min = ((now - m.requestStart) / 60_000).toInt()
    Column(Modifier.fillMaxWidth().soinCard(Soin.accentSoft, 28.dp).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(Soin.card), contentAlignment = Alignment.Center) {
                T(m.seniorTitle.take(1).uppercase(), 20.sp, FontWeight.Bold, Soin.accent)
            }
            Column {
                T("Demande · " + if (min < 1) "à l'instant" else "il y a $min min", 13.sp, color = Soin.secondary, maxLines = 1)
                T(m.seniorTitle, 20.sp, FontWeight.Bold)
            }
        }
        if (m.task.isNotEmpty()) T("« ${m.task} »", 21.sp, FontWeight.SemiBold)
        val img = m.frame
        if (img != null && onThumb != null) {
            Row(Modifier.clip(CircleShape).background(Soin.card).clickable(onClick = onThumb)
                .padding(start = 6.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Image(img, "Agrandir la dernière capture", Modifier.size(38.dp, 26.dp).clip(RoundedCornerShape(6.dp)),
                    contentScale = ContentScale.Crop)
                T("Écran de ${m.senior}", 13.sp, FontWeight.Medium)
            }
        }
    }
}

/** Mes personnes aidées : qui suivre en détail, qui demande une assistance, ajouter ou retirer. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PeopleRow() {
    val m = Helper
    var forget by remember { mutableStateOf<Person?>(null) }
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
            .padding(start = 20.dp, end = 20.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        m.people.forEach { p ->
            val here = m.isCurrent(p)
            val asking = !here && m.othersAsking[p.key] == true
            val name = p.name.ifEmpty { "Personne aidée" }
            Row(
                Modifier.clip(CircleShape).background(if (here) Soin.ink else Soin.card)
                    .then(if (asking) Modifier.border(2.dp, Soin.danger, CircleShape) else Modifier)
                    .combinedClickable(onClick = { m.switchTo(p) }, onLongClick = { forget = p })
                    .padding(start = 6.dp, end = 14.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(Modifier.size(32.dp).clip(CircleShape).background(Soin.accentSoft), contentAlignment = Alignment.Center) {
                    T(name.take(1).uppercase(), 15.sp, FontWeight.Bold, Soin.accent)
                }
                T(name, 15.sp, FontWeight.SemiBold, if (here) Color.White else Soin.ink, maxLines = 1)
                if (!here) {
                    Box(Modifier.size(8.dp).clip(CircleShape)
                        .background(if (m.othersOnline[p.key] == true) Soin.accent else Soin.secondary))
                    if (asking) T("demande une assistance", 12.sp, color = Soin.danger, maxLines = 1)
                }
            }
        }
        T("+ Ajouter une personne", 15.sp, FontWeight.SemiBold, Soin.accent,
            Modifier.clip(CircleShape).background(Soin.card).clickable { m.sheet = AppSheet.Settings }
                .padding(horizontal = 16.dp, vertical = 12.dp), maxLines = 1)
    }
    forget?.let { p ->
        val who = p.name.ifEmpty { "cette personne" }
        Dialog(onDismissRequest = { forget = null }) {
            Column(Modifier.fillMaxWidth().soinCard().padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                T("Retirer $who ?", 24.sp, FontWeight.Bold)
                T("Ses demandes n'arriveront plus sur ce téléphone. Vous pourrez la rajouter avec un nouveau code.", 17.sp)
                CapsuleButton("Retirer", fill = Soin.danger) { m.forget(p); forget = null }
                TextLink("Annuler") { forget = null }
            }
        }
    }
}
