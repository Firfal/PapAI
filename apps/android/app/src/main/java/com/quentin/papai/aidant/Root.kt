package com.quentin.papai.aidant

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Shield
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Calendar

@Composable
fun Root() {
    val m = Helper
    Box(Modifier.fillMaxSize().soinScreen()) {
        // Une assistance démarre : on montre l'utilisateur concerné, quel que soit l'onglet (comme sur Mac).
        LaunchedEffect(m.screen) { if (m.screen != Screen.IDLE) m.supportTab = 1 }
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            Header(m.helperName ?: m.orgTitle) { m.sheet = AppSheet.Settings }
            if (m.isConfigured && m.screen != Screen.IDLE) PeopleRow()
            if (m.isConfigured && !m.connected) {
                LostBanner(Modifier.padding(horizontal = 20.dp).padding(bottom = 10.dp))
            }
            m.sensitiveRefusal?.let { reason ->
                Column(
                    Modifier.padding(horizontal = 20.dp).padding(bottom = 12.dp)
                        .fillMaxWidth().soinCard().padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    T(reason, 17.sp, FontWeight.Normal, Soin.ink)
                    CapsuleButton("Compris") { m.sensitiveRefusal = null }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (!m.orgConfigured) NoOrgScreen()
                else if (!m.isConfigured) NoPosteScreen()
                else when (m.screen) {
                    Screen.IDLE -> SupportHome()
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
        when (m.sheet) {
            AppSheet.Settings -> Sheet { SettingsSheet() }
            null -> {}
        }
        AutomateLibrary.applying?.let { e ->
            Sheet(onClose = { AutomateLibrary.applying = null }) { ApplyAutomateSheet(e) { AutomateLibrary.applying = null } }
        }
        if (m.guardAlertId != null) Sheet(dismissable = false) { GuardScreen() }
    }
}

/** Feuille plein écran au-dessus de l'app (retour = fermer, si permis). */
@Composable
fun Sheet(dismissable: Boolean = true, onClose: () -> Unit = { Helper.sheet = null }, content: @Composable () -> Unit) {
    BackHandler { if (dismissable) onClose() }
    Box(
        Modifier.fillMaxSize().soinScreen().clickable(enabled = false) {}
            .systemBarsPadding().imePadding(),
    ) { content() }
}

@Composable
fun Header(name: String, onAvatar: () -> Unit) {
    // Bandeau bleu dégradé qui passe sous la barre d'état, coins bas arrondis (comme l'iPhone).
    val shape = RoundedCornerShape(bottomStart = 28.dp, bottomEnd = 28.dp)
    Row(
        Modifier.fillMaxWidth().padding(bottom = 14.dp)
            .shadow(14.dp, shape, ambientColor = Soin.accent, spotColor = Soin.accent)
            .clip(shape).background(Soin.headerBrush)
            .statusBarsPadding()
            .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 20.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(Color.White)
                .clickable(role = Role.Button, onClick = onAvatar).semantics { contentDescription = "Réglages" },
            contentAlignment = Alignment.Center,
        ) { T(name.take(1).uppercase(), 20.sp, FontWeight.Bold, Soin.accent) }
        Column(Modifier.weight(1f)) {
            val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            T(if (h >= 19 || h < 5) "Bonsoir" else "Bonjour", 14.sp, FontWeight.Medium, Color.White)
            T(name, 22.sp, FontWeight.SemiBold, Color.White, maxLines = 1)
        }
        Box(Modifier.size(48.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f)).clickable(onClick = onAvatar), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Settings, "Réglages", tint = Color.White)
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
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Soin.ink).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            if (m.linkError == null || m.retryAt != null) {
                CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
            } else Icon(Icons.Default.Warning, null, Modifier.size(16.dp), tint = Color.White)
            T(connectionLine(now), 14.sp, FontWeight.SemiBold, Color.White)
        }
        if (m.linkError != null) {
            T("Réessayer maintenant", 14.sp, FontWeight.SemiBold, Color.White,
                Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.18f))
                    .clickable { m.reconnect() }.padding(horizontal = 14.dp, vertical = 7.dp))
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
                // Hors connexion, on ne sait rien : pas de « Rien à signaler ».
                HomeCard.WELLBEING -> if (m.connected) {
                    Column(Modifier.fillMaxWidth().soinCard(Soin.accentSoft, 24.dp).padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        T("Rien à signaler pour ${m.senior}", 28.sp, FontWeight.Bold)
                        T("Vous serez prévenu dès qu'une demande d'aide arrive.", 16.sp, color = Soin.secondary)
                    }
                } else {
                    Column(Modifier.fillMaxWidth().soinCard(radius = 24.dp).padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        T("Connexion interrompue", 28.sp, FontWeight.Bold)
                        T("Impossible de recevoir les demandes d'aide de ${m.senior} pour le moment.", 17.sp, FontWeight.Medium)
                    }
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
                    T("Derniers automates", 17.sp, FontWeight.SemiBold)
                    if (m.lessons.isEmpty()) T("Aucun automate pour l'instant.", 15.sp, color = Soin.secondary)
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
        Row(Modifier.padding(top = 20.dp).soinCard(radius = 18.dp).padding(horizontal = 18.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), color = Soin.accent, strokeWidth = 2.dp)
            T(text, 17.sp, FontWeight.SemiBold)
        }
    }
}

@Composable
fun StoppedScreen() {
    val m = Helper
    val guard = m.stoppedBy == "gardien"
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(64.dp).clip(CircleShape).background(if (guard) Soin.danger.copy(alpha = 0.1f) else Soin.card),
            contentAlignment = Alignment.Center) {
            Icon(if (guard) Icons.Default.Shield else if (m.iRefusedPlan) Icons.Default.Close else Icons.Default.Pause, null,
                tint = if (guard) Soin.danger else Soin.ink)
        }
        T(when {
            guard -> "PapAI a arrêté l'assistance : démarche suspecte"
            m.iRefusedPlan -> "Vous avez refusé le plan"
            else -> "${m.seniorTitle} a arrêté l’assistance"
        }, 22.sp, FontWeight.Bold, align = TextAlign.Center)
        T("L'assistance reste arrêtée. Toute nouvelle aide demande votre accord.", 15.sp, color = Soin.secondary, align = TextAlign.Center)
        T("Appelez ${m.senior} à son numéro habituel.", 17.sp, FontWeight.SemiBold, align = TextAlign.Center)
        Spacer(Modifier.weight(2f))
    }
}

/** Alerte du gardien en plein écran, comme `GuardRequestView` sur l'iPhone. */
@Composable
fun GuardScreen() {
    val m = Helper
    var confirm by remember { mutableStateOf(false) }
    val detail = m.lastAlert?.detail.orEmpty().let { d ->
        if (m.guardTask.isEmpty()) d else d.replace("\nDemande : « ${m.guardTask} »", "")
    }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(4.dp).background(Soin.danger))
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Column(Modifier.fillMaxWidth().soinCard(radius = 28.dp).border(2.dp, Soin.danger, RoundedCornerShape(28.dp)).padding(28.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.size(60.dp).clip(CircleShape).background(Soin.danger.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.PanTool, null, Modifier.size(28.dp), tint = Soin.danger)
                }
                T(m.lastAlert?.title ?: "Démarche à vérifier", 28.sp, FontWeight.Bold)
                T("PapAI a arrêté l'assistance : démarche suspecte", 18.sp, FontWeight.SemiBold)
                if (m.guardTask.isNotEmpty()) T("« ${m.guardTask} »", 20.sp, FontWeight.SemiBold)
                if (detail.isNotEmpty()) T(detail, 17.sp, color = Soin.secondary)
                if (m.guardAcknowledged) T("Un support a vu l'alerte et s'en occupe", 17.sp, FontWeight.SemiBold)
            }
            if (confirm) {
                T("Vous connaissez cette démarche ? Cela ferme l'alerte, sans relancer l'assistance.", 17.sp)
                CapsuleButton("Confirmer : c'est normal", fill = Soin.ink, enabled = m.connected) { m.dismissGuardAlert() }
                CapsuleButton("Retour", fill = Soin.card, text = Soin.ink) { confirm = false }
            } else {
                CapsuleButton("Je m'en occupe", fill = Soin.ink, enabled = m.connected && !m.guardAcknowledged) { m.acknowledgeGuardAlert() }
                CapsuleButton("C'est normal", fill = Soin.card, text = Soin.ink, enabled = m.connected) { confirm = true }
            }
            if (!m.connected) T("Reconnectez-vous pour répondre à cette alerte.", 16.sp, color = Soin.secondary)
        }
    }
}

/** Carte menthe de la demande : qui, quand, quoi, et la dernière capture. */
@Composable
fun RequestCard(onThumb: (() -> Unit)? = null) {
    val m = Helper
    val now = rememberNow(20_000)
    val min = ((now - m.requestStart) / 60_000).toInt()
    Column(Modifier.fillMaxWidth().soinCard(radius = 24.dp).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(Soin.accentBrush), contentAlignment = Alignment.Center) {
                T(m.seniorTitle.take(1).uppercase(), 20.sp, FontWeight.Bold, Color.White)
            }
            Column {
                T("Demande de ${m.senior} · " + if (min < 1) "à l’instant" else "il y a $min min", 13.sp, color = Soin.secondary, maxLines = 1)
                T(m.seniorTitle, 20.sp, FontWeight.Bold)
            }
        }
        if (m.task.isNotEmpty()) T("« ${m.task} »", 21.sp, FontWeight.SemiBold)
        val img = m.frame
        if (img != null && onThumb != null) {
            Row(Modifier.clip(CircleShape).background(Soin.field).clickable(onClick = onThumb)
                .padding(start = 6.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Image(img, "Agrandir la dernière capture", Modifier.size(38.dp, 26.dp).clip(RoundedCornerShape(6.dp)),
                    contentScale = ContentScale.Crop)
                T("Écran de ${m.senior}", 13.sp, FontWeight.Medium)
            }
        }
    }
}

/** Sans jeton d'organisation : rien à saisir, l'administrateur configure le téléphone. */
@Composable
fun NoOrgScreen() {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
        Column(Modifier.fillMaxWidth().soinCard(radius = 24.dp).padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            T("Aucune organisation configurée", 26.sp, FontWeight.Bold)
            T("Contactez votre administrateur : il installe la configuration du support de votre organisation sur ce téléphone.",
                17.sp, color = Soin.secondary)
        }
    }
}

/** Organisation configurée, mais aucun poste à suivre (pas encore lu, vide, ou serveur injoignable). */
@Composable
fun NoPosteScreen() {
    val m = Helper
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
        Column(Modifier.fillMaxWidth().soinCard(radius = 24.dp).padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!m.orgLoaded && m.orgError == null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = Soin.accent, strokeWidth = 2.dp)
                    T("Chargement des postes…", 17.sp, FontWeight.SemiBold)
                }
            } else {
                T(if (m.orgError == null) "Aucun poste inscrit pour l'instant" else "Postes indisponibles", 26.sp, FontWeight.Bold)
                T(m.orgError ?: "Les postes de l'organisation apparaissent ici dès que PapAI y est installé.",
                    17.sp, color = Soin.secondary)
                TextLink("Réessayer maintenant", Soin.accent) { m.refreshOrg() }
            }
        }
    }
}

/** Réglages en lecture seule : tout vient de la configuration de l'organisation. */
@Composable
fun SettingsSheet() {
    val m = Helper
    val now = rememberNow()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SheetTitle("Réglages")
        Column(Modifier.fillMaxWidth().soinCard().padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            T("Organisation", 15.sp, FontWeight.SemiBold, Soin.secondary)
            T(if (m.orgConfigured) m.orgTitle else "Aucune organisation configurée", 20.sp, FontWeight.SemiBold)
            m.orgHost?.let { host ->
                T(host, 15.sp, color = Soin.secondary)
                val n = m.people.size
                T("$n poste${if (n > 1) "s" else ""}", 15.sp, color = Soin.secondary)
            }
            m.orgError?.let { T(it, 15.sp, FontWeight.SemiBold, Soin.danger) }
        }
        T(if (m.orgConfigured) "Configuré par votre administrateur. Rien à régler sur ce téléphone."
            else "Contactez votre administrateur : il installe la configuration du support sur ce téléphone.",
            15.sp, color = Soin.secondary)
        if (m.isConfigured) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(
                    if (m.connected) Soin.online else if (m.linkError == null) Soin.secondary else Soin.danger))
                T(connectionLine(now), 14.sp, color = Soin.secondary)
            }
            CapsuleButton("Réessayer maintenant", fill = Soin.card, text = Soin.ink) { m.reconnect(); m.refreshOrg() }
        }
        CapsuleButton("Fermer", Modifier.padding(top = 8.dp)) { m.sheet = null }
    }
}

/** Les postes de l'organisation : lequel suivre en détail, lequel demande une assistance. */
@Composable
fun PeopleRow() {
    val m = Helper
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
            .padding(start = 20.dp, end = 20.dp, bottom = 12.dp)
            .semantics { contentDescription = "Postes" },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        m.people.forEach { p ->
            val here = m.isCurrent(p)
            val asking = !here && m.othersAsking[p.key] == true
            val name = People.title(p)
            val detail = People.detail(p)
            val label = listOfNotNull(name, detail, if (asking) "demande une assistance" else null).joinToString(", ")
            Row(
                Modifier.clip(CircleShape).background(if (here) Soin.accent else Soin.card)
                    .then(if (asking) Modifier.border(2.dp, Soin.danger, CircleShape) else Modifier)
                    .clickable(role = Role.Button) { m.switchTo(p) }
                    .clearAndSetSemantics { contentDescription = label }
                    .padding(start = 6.dp, end = 14.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(Modifier.size(32.dp).clip(CircleShape).background(if (here) Color.White else Soin.accentSoft), contentAlignment = Alignment.Center) {
                    T(name.take(1).uppercase(), 15.sp, FontWeight.Bold, Soin.accent)
                }
                Column {
                    T(name, 15.sp, FontWeight.SemiBold, if (here) Color.White else Soin.ink, maxLines = 1)
                    detail?.let { T(it, 12.sp, color = if (here) Color.White.copy(alpha = 0.85f) else Soin.secondary, maxLines = 1) }
                }
                if (!here) {
                    Box(Modifier.size(8.dp).clip(CircleShape)
                        .background(if (m.othersOnline[p.key] == true) Soin.online else Soin.secondary))
                    if (asking) T("demande une assistance", 12.sp, color = Soin.danger, maxLines = 1)
                }
            }
        }
    }
}
