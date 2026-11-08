package com.quentin.papai.aidant

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/**
 * Accueil du support, aligné sur le support Mac (`SupportRoot`) et l'iPhone (`SupportHome`) :
 * trois onglets « Tickets », « Utilisateurs » et « Mes automates ». L'onglet est retenu ;
 * une assistance qui démarre ramène sur Utilisateurs (voir `Root`).
 */
@Composable
fun SupportHome() {
    val m = Helper
    Column(Modifier.fillMaxSize()) {
        SoinTabs(listOf("Tickets" to 0, "Utilisateurs" to 1, "Mes automates" to 2), m.supportTab, { m.supportTab = it },
            Modifier.padding(horizontal = 20.dp).padding(bottom = 12.dp))
        when (m.supportTab) {
            0 -> TicketsTab { p -> m.switchTo(p); m.supportTab = 1 }
            2 -> AutomatesTab()
            else -> {
                PeopleRow()
                // Fin ou arrêt d'une assistance : affichés dans Utilisateurs, les autres onglets restent accessibles (comme sur Mac).
                when (m.screen) {
                    Screen.DONE -> DoneScreen()
                    Screen.STOPPED -> StoppedScreen()
                    else -> IdleScreen()
                }
            }
        }
    }
}

/** Onglets soulignés, comme `Onglets` sur Mac, avec des zones d'au moins 48 dp. */
@Composable
fun <V> SoinTabs(options: List<Pair<String, V>>, selection: V, onSelect: (V) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth()) {
        options.forEach { (label, value) ->
            val on = value == selection
            Column(
                Modifier.weight(1f).clickable(role = Role.Tab) { onSelect(value) }.semantics { selected = on },
            ) {
                Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp), contentAlignment = Alignment.Center) {
                    T(label, 15.sp, if (on) FontWeight.SemiBold else FontWeight.Medium,
                        if (on) Soin.accentText else Soin.secondary, align = TextAlign.Center, maxLines = 2)
                }
                Box(Modifier.fillMaxWidth().height(if (on) 3.dp else 1.dp).background(if (on) Soin.accent else Soin.line))
            }
        }
    }
}

/** Bouton en pilule compact (≥ 48 dp), pour les actions d'une carte. */
@Composable
fun SmallPill(label: String, filled: Boolean = true, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        Modifier.defaultMinSize(minHeight = 48.dp).clip(CircleShape)
            .then(if (filled) Modifier.background(Soin.accentBrush) else Modifier.background(Soin.card).border(1.dp, Soin.line, CircleShape))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp).then(if (enabled) Modifier else Modifier.background(Color.Transparent)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val color = (if (filled) Color.White else Soin.accentText).copy(alpha = if (enabled) 1f else 0.5f)
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = color) }
        T(label, 15.sp, FontWeight.SemiBold, color, maxLines = 1)
    }
}

@Composable
private fun Empty(s: String) = T(s, 16.sp, color = Soin.secondary, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))

// Tickets

/** Onglet « Tickets » : tous les tickets de tous les utilisateurs suivis. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TicketsTab(openUser: (Person) -> Unit) {
    val m = Helper
    val b = TicketBoard
    var filter by remember { mutableStateOf(0) }   // 0 ouverts, 1 tous
    val people = m.people.toList()
    LaunchedEffect(people.map { it.key }, m.ticketsVersion) {
        while (true) { b.load(people); delay(10_000) }
    }
    val shown = if (filter == 0) b.tickets.filter { it.isOpen } else b.tickets.toList()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val open = b.openCount
            T(if (open == 0) "Aucune demande en attente."
              else "$open demande${if (open > 1) "s" else ""} ouverte${if (open > 1) "s" else ""} chez vos utilisateurs.",
                15.sp, FontWeight.Medium, Soin.secondary, Modifier.weight(1f))
            if (b.loading) CircularProgressIndicator(Modifier.size(16.dp), color = Soin.accent, strokeWidth = 2.dp)
        }
        SoinTabs(listOf("Ouverts" to 0, "Tous" to 1), filter, { filter = it }, Modifier.widthIn(max = 260.dp))
        b.errors.forEach { e ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Warning, null, Modifier.size(16.dp), tint = Soin.danger)
                T(e, 14.sp, color = Soin.danger)
            }
        }
        if (people.isEmpty()) Empty("Aucun utilisateur suivi. Les postes de l’organisation apparaissent dans l’onglet Utilisateurs.")
        else if (shown.isEmpty() && !b.loading) Empty(
            if (filter == 0) "Rien à traiter. Les nouvelles demandes de vos utilisateurs arriveront ici." else "Aucun ticket pour l’instant.")
        shown.forEach { t -> TicketRow(t, openUser) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TicketRow(t: SupportTicket, openUser: (Person) -> Unit) {
    val m = Helper
    val b = TicketBoard
    fun act(action: String) = b.act(t, action, m.helperName ?: "Support", m.people.toList()) { e ->
        if (e != null) m.showToast(e)
        else if (action == "take") { m.showToast("Demande proposée à ${t.person.name.ifEmpty { "l’utilisateur" }}"); openUser(t.person) }
    }
    Column(Modifier.fillMaxWidth().soinCard(radius = 18.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            T(t.label, 13.sp, FontWeight.SemiBold, Soin.secondary, Modifier.align(Alignment.CenterVertically))
            val (txt, tone) = t.statut
            StatusPill(txt, tone) { Box(Modifier.size(6.dp).clip(CircleShape).background(Soin.tone(tone).second)) }
            T(t.personName, 13.sp, FontWeight.SemiBold, modifier = Modifier.align(Alignment.CenterVertically))
        }
        T(if (t.task.isEmpty()) "Demande sans texte" else "« ${t.task} »", 17.sp, FontWeight.SemiBold)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            T(t.quand, 13.sp, color = Soin.secondary)
            if (t.assignee.isNotEmpty()) T("Pris par ${t.assignee}", 13.sp, color = Soin.secondary)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (t.canTake) SmallPill(if (b.busy == t.id) "Envoi…" else "Prendre en charge", enabled = b.busy == null) { act("take") }
            SmallPill("Voir l’utilisateur", filled = false) { openUser(t.person) }
            if (t.canTake) SmallPill("Clore", filled = false, enabled = b.busy == null) { act("close") }
            else if (!t.isOpen) SmallPill("Rouvrir", filled = false, enabled = b.busy == null) { act("reopen") }
        }
    }
}

// Mes automates

/**
 * Onglet « Mes automates » : la bibliothèque du support (`AutomateLibrary`). Comme sur Mac
 * et iPhone, pas de création à partir de rien : liste, import d'un `.papai` et « Appliquer… ».
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AutomatesTab() {
    val m = Helper
    val lib = AutomateLibrary
    val ctx = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    var toDelete by remember { mutableStateOf<AutomateEntry?>(null) }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = try { ctx.contentResolver.openInputStream(uri)?.use { s -> s.readBytes().take(2_000_000).toByteArray().decodeToString() } } catch (_: Exception) { null }
        val e = text?.let { lib.add(it) }
        if (e != null) { error = null; m.showToast("« ${e.title} » ajouté à vos automates") }
        else error = "Ce fichier n’est pas un automate .papai."
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        T("Votre bibliothèque. Choisissez ensuite à qui appliquer chaque automate.", 15.sp, FontWeight.Medium, Soin.secondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            val n = lib.entries.size
            T("$n automate${if (n > 1) "s" else ""}", 15.sp, FontWeight.SemiBold, Soin.secondary, Modifier.weight(1f))
            SmallPill("Importer un .papai", filled = false, icon = Icons.Outlined.FileDownload) { importer.launch(arrayOf("*/*")) }
        }
        error?.let { e ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Warning, null, Modifier.size(16.dp), tint = Soin.danger)
                T(e, 15.sp, FontWeight.SemiBold, Soin.danger)
            }
        }
        if (lib.entries.isEmpty()) Empty("Aucun automate. Importez un fichier .papai.")
        lib.entries.forEach { e -> AutomateRow(e, { lib.applying = e }, { toDelete = e }) }
    }
    toDelete?.let { e ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text("Supprimer cet automate de votre bibliothèque ?") },
            text = { Text("Les utilisateurs chez qui il est déjà appliqué le gardent.") },
            confirmButton = { TextButton({ lib.remove(e); toDelete = null }) { Text("Supprimer « ${e.title} »", color = Soin.danger) } },
            dismissButton = { TextButton({ toDelete = null }) { Text("Annuler", color = Soin.ink) } },
            containerColor = Soin.card,
        )
    }
}

private fun automateIcon(action: String): ImageVector = when (action) {
    "open_folder" -> Icons.Default.Folder
    "open_settings" -> Icons.Default.Settings
    "open_url" -> Icons.Default.Public
    "install_templates" -> Icons.Default.Description
    "antivirus_scan" -> Icons.Default.Shield
    "holo" -> Icons.Default.AutoAwesome
    else -> Icons.Default.CheckCircle
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AutomateRow(e: AutomateEntry, onApply: () -> Unit, onDelete: () -> Unit) {
    val m = Helper
    Column(Modifier.fillMaxWidth().soinCard(radius = 18.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(Soin.accentSoft), contentAlignment = Alignment.Center) {
                Icon(automateIcon(e.firstAction), null, Modifier.size(22.dp), tint = Soin.accent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T(e.title, 17.sp, FontWeight.SemiBold)
                if (e.detail.isNotEmpty()) T(e.detail, 15.sp, color = Soin.secondary, maxLines = 3)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (e.stepCount > 0) Tag("${e.stepCount} étape${if (e.stepCount > 1) "s" else ""}")
            if (e.platforms.isNotEmpty()) Tag(e.platforms.joinToString(" · ") { if (it == "mac") "Mac" else "Windows" })
            if (e.publisher.isNotEmpty()) Tag(e.publisher)
        }
        val names = m.people.filter { it.key in e.applied }.map { People.title(it) }
        T(if (names.isEmpty()) "Appliqué à personne" else "Appliqué à : " + names.joinToString(", "),
            13.sp, FontWeight.SemiBold, if (names.isEmpty()) Soin.secondary else Soin.accentText)
        Row(verticalAlignment = Alignment.CenterVertically) {
            SmallPill("Appliquer…", onClick = onApply)
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(48.dp).clip(CircleShape).background(Soin.field).clickable(role = Role.Button, onClick = onDelete)
                .semantics { contentDescription = "Supprimer ${e.title}" }, contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Delete, null, tint = Soin.secondary)
            }
        }
    }
}

@Composable
private fun Tag(s: String) = T(s, 12.sp, FontWeight.SemiBold, Soin.secondary,
    Modifier.clip(CircleShape).background(Soin.field).padding(horizontal = 10.dp, vertical = 4.dp), maxLines = 1)

/** Choisir les utilisateurs chez qui appliquer un automate (même logique que sur Mac et iPhone). */
@Composable
fun ApplyAutomateSheet(entry: AutomateEntry, onClose: () -> Unit) {
    val m = Helper
    val chosen = remember { mutableStateMapOf<String, Boolean>() }
    val results = remember { mutableStateMapOf<String, String>() }   // clé -> erreur ("" = réussi)
    var sending by remember { mutableStateOf(false) }
    val current = AutomateLibrary.entries.firstOrNull { it.id == entry.id } ?: entry
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SheetTitle("Appliquer « ${entry.title} »", 24.sp)
            T("Les utilisateurs cochés pourront le relancer d’un clic. Vous pouvez aussi ne l’appliquer à personne pour l’instant.",
                15.sp, color = Soin.secondary)
            if (m.people.isEmpty()) T("Aucun utilisateur suivi sur ce téléphone.", 16.sp, color = Soin.secondary)
            m.people.forEach { p ->
                val already = p.key in current.applied
                val on = chosen[p.key] == true || already
                Row(
                    Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                        .background(Soin.field).border(1.dp, Soin.line, androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                        .clickable(enabled = !already && !sending, role = Role.Checkbox) { chosen[p.key] = chosen[p.key] != true }
                        .semantics { selected = on }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(if (on) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked, null,
                        tint = if (on) Soin.accent else Soin.secondary)
                    T(People.title(p), 17.sp, FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1)
                    val r = results[p.key]
                    if (already) T("déjà appliqué", 13.sp, color = Soin.accentText)
                    else if (r != null) T(r.ifEmpty { "Appliqué" }, 13.sp, FontWeight.SemiBold, if (r.isEmpty()) Soin.accentText else Soin.danger)
                }
            }
        }
        val picked = m.people.filter { chosen[it.key] == true && it.key !in current.applied }
        CapsuleButton(if (sending) "Envoi…" else "Appliquer", enabled = picked.isNotEmpty() && !sending) {
            sending = true
            AutomateLibrary.apply(entry, picked) { r ->
                sending = false
                results.putAll(r)
                r.filterValues { it.isEmpty() }.keys.forEach { chosen.remove(it) }
                if (r.values.any { it.isEmpty() }) m.loadLessons()
            }
        }
        TextLink(if (results.isEmpty()) "Plus tard" else "Fermer", onClick = onClose)
    }
}
