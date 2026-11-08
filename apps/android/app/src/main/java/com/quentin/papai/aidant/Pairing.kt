package com.quentin.papai.aidant

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.activity.compose.rememberLauncherForActivityResult
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions

private val relations = listOf(
    "Fille" to "sa fille", "Fils" to "son fils", "Proche" to "un proche",
    "Collègue" to "un collègue", "Service informatique" to "le service informatique", "Voisin, voisine" to "un voisin",
)

/** Scanner le QR affiché sur l'ordinateur (ZXing, appareil photo arrière). */
@Composable
fun rememberQrScanner(): () -> Unit {
    val launcher = rememberLauncherForActivityResult(ScanContract()) { r ->
        val text = r.contents ?: return@rememberLauncherForActivityResult
        if (PairingPolicy.invitationError(text, BuildConfig.DEBUG) != null) Helper.pairingRefused = true
        else Helper.open(text)
    }
    return {
        launcher.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setBeepEnabled(false)
            .setOrientationLocked(true).setPrompt("Visez le QR affiché sur l'ordinateur de ${Helper.senior}"))
    }
}

@Composable
fun SettingsSheet() {
    val m = Helper
    var server by rememberSaveable { mutableStateOf(m.serverURL) }
    var key by rememberSaveable { mutableStateOf(m.helperKey) }
    val scan = rememberQrScanner()
    val now = rememberNow()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SheetTitle("Connexion")
        T("Le plus simple : scannez le QR affiché sur l'ordinateur de ${m.senior} (Mon support › Ajouter un support).",
            15.sp, color = Soin.secondary)
        CapsuleButton("Scanner le QR de l'ordinateur", fill = Soin.accent, onClick = scan)
        CapsuleButton("Entrer le code à 6 chiffres", fill = Soin.card, text = Soin.ink) { m.openPair(m.manualPairLink()) }
        T("Ou à la main", 17.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
        val uri = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrect = false, keyboardType = KeyboardType.Uri)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FieldLabel("Adresse du serveur")
            SoinField(server, { server = it }, "https://…/k/<clé de l'espace>", keyboard = uri)
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FieldLabel("Clé support")
            SoinField(key, { key = it }, "demo", keyboard = uri)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(
                if (m.connected) Soin.accent else if (m.linkError == null) Soin.secondary else Soin.danger))
            T(if (m.isConfigured) connectionLine(now) else "Non configuré", 14.sp, color = Soin.secondary)
        }
        m.lastGood?.let { (s, k) ->
            if (s != m.serverURL || k != m.helperKey) TextLink("Revenir au dernier réglage qui marchait", Soin.accent) {
                server = s; key = k; m.applySettings(s, k)
            }
        }
        CapsuleButton("Enregistrer et se connecter", Modifier.padding(top = 8.dp),
            enabled = server.isNotBlank() && key.isNotBlank()) {
            m.applySettings(server, key); m.sheet = null
        }
        if (m.isConfigured) {
            TextLink("Réessayer maintenant") { m.reconnect() }
            TextLink("Fermer") { m.sheet = null }
        }
    }
}

@Composable
fun PairingRefusal() {
    val scan = rememberQrScanner()
    Dialog(onDismissRequest = { Helper.pairingRefused = false }) {
        Column(Modifier.fillMaxWidth().soinCard().padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            T("Lien refusé", 24.sp, FontWeight.Bold)
            T(PairingPolicy.refusal, 18.sp, FontWeight.SemiBold, Soin.danger)
            CapsuleButton("Scanner le QR de l'ordinateur") { Helper.pairingRefused = false; scan() }
            TextLink("Fermer") { Helper.pairingRefused = false }
        }
    }
}

@Composable
private fun PairServerCard(link: PairLink) {
    val official = PairingPolicy.isOfficial(link.base)
    val copy = PairingPolicy.presentation(link)
    Column(Modifier.fillMaxWidth().soinCard(if (official) Soin.accentSoft else Soin.danger.copy(alpha = 0.1f)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        T(copy.server, 19.sp, FontWeight.Bold, if (official) Soin.ink else Soin.danger)
        T(copy.domain, 13.sp, color = Soin.secondary)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PairSheet(link: PairLink) {
    val m = Helper
    var name by rememberSaveable { mutableStateOf(m.helperName ?: "") }
    var relation by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var confirmReplacement by rememberSaveable(link) { mutableStateOf(false) }
    val policyError = PairingPolicy.error(link.base, BuildConfig.DEBUG)
    val copy = PairingPolicy.presentation(link)
    if (confirmReplacement) {
        Dialog(onDismissRequest = { confirmReplacement = false }) {
            Column(Modifier.fillMaxWidth().soinCard().verticalScroll(rememberScrollState()).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)) {
                T("Remplacer la liaison ?", 24.sp, FontWeight.Bold)
                T("Ceci remplacera votre liaison ${if (m.connected) "active " else ""}avec ${m.senior}. Les demandes de ${m.senior} n'arriveront plus sur ce téléphone.", 18.sp)
                T("Actuel : ${m.lastGood?.first?.let { runCatching { PairLink(it, null).host }.getOrDefault(it) }.orEmpty()} · Nouveau : ${link.host}", 13.sp, color = Soin.secondary)
                PairServerCard(link)
                CapsuleButton("Remplacer et rejoindre") {
                    confirmReplacement = false
                    m.submitPair(link, code, name, relation, confirmed = true)
                }
                TextLink("Annuler") { confirmReplacement = false }
            }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        if (m.pairDone) {
            Spacer(Modifier.height(40.dp))
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(Modifier.size(72.dp).clip(CircleShape).background(Soin.accentSoft), contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Check, null, Modifier.size(32.dp), tint = Soin.accent)
                }
            }
            T("Vous êtes relié à ${m.senior}", 26.sp, FontWeight.Bold, modifier = Modifier.fillMaxWidth(), align = TextAlign.Center)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                when {
                    m.connected -> {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(Soin.accent))
                        T("Connecté. Vous serez prévenu dès qu'une demande d'aide arrive.", 15.sp, color = Soin.secondary, align = TextAlign.Center)
                    }
                    m.linkError != null -> T(m.linkError!!, 15.sp, color = Soin.secondary, align = TextAlign.Center)
                    else -> {
                        CircularProgressIndicator(Modifier.size(16.dp), color = Soin.accent, strokeWidth = 2.dp)
                        T("Connexion au serveur…", 15.sp, color = Soin.secondary)
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
            CapsuleButton("Terminer") { m.sheet = null }
            return@Column
        }
        SheetTitle(copy.title)
        PairServerCard(link)
        policyError?.let { T(it, 16.sp, FontWeight.SemiBold, Soin.danger) }
        T(copy.description,
            15.sp, color = Soin.secondary)
        if (link.code == null) {
            FieldLabel("Code affiché sur l'ordinateur")
            SoinField(code, { v -> code = v.filter { it.isDigit() }.take(6) }, "000000", size = 28.sp,
                weight = FontWeight.SemiBold, align = TextAlign.Center,
                keyboard = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
        }
        FieldLabel("Votre prénom")
        SoinField(name, { name = it }, "Claire", keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        FieldLabel(copy.relationLabel)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            relations.forEach { (label, value) ->
                val on = relation == value
                T(label, 15.sp, FontWeight.Medium, if (on) Color.White else Soin.ink,
                    Modifier.clip(CircleShape).background(if (on) Soin.ink else Soin.card)
                        .clickable { relation = if (on) "" else value }.padding(horizontal = 16.dp, vertical = 10.dp))
            }
        }
        m.pairError?.let { T(it, 15.sp, FontWeight.SemiBold, Soin.danger) }
        CapsuleButton("Rejoindre", enabled = !m.pairBusy && policyError == null, content = if (m.pairBusy) {
            { CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp) }
        } else null) {
            if (PairingPolicy.needsConfirmation(m.lastGood != null)) confirmReplacement = true
            else m.submitPair(link, code, name, relation)
        }
        if (!m.pairBusy) TextLink("Annuler") { m.sheet = if (m.isConfigured) null else AppSheet.Settings }
    }
}
