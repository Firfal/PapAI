package com.quentin.papai.aidant

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ApprovalScreen() {
    val m = Helper
    var refine by remember { mutableStateOf(false) }
    var confirmRefuse by remember { mutableStateOf(false) }
    var zoom by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            RequestCard(onThumb = { zoom = true })
            Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                T("Plan proposé par Holo", 17.sp, FontWeight.SemiBold, modifier = Modifier.weight(1f))
                T("${m.plan.size} étape${if (m.plan.size > 1) "s" else ""}", 13.sp, color = Soin.secondary,
                    modifier = Modifier.clip(CircleShape).background(Soin.card).padding(horizontal = 12.dp, vertical = 6.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                m.plan.forEachIndexed { i, raw ->
                    val (title, detail) = splitStep(raw)
                    Row(Modifier.fillMaxWidth().soinCard().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Box(Modifier.size(38.dp).clip(CircleShape).background(Soin.bg), contentAlignment = Alignment.Center) {
                            T("${i + 1}", 16.sp, FontWeight.SemiBold)
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T(title, 17.sp, FontWeight.SemiBold)
                            detail?.let { T(it, 14.sp, color = Soin.secondary) }
                        }
                    }
                }
            }
        }
        Column(Modifier.fillMaxWidth().background(Soin.bg).padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                CapsuleButton("Valider le plan", Modifier.weight(1f), enabled = !m.planBusy, content = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (m.planBusy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                        else Icon(Icons.Default.Check, null, tint = Color.White)
                        T("Valider le plan", 17.sp, FontWeight.SemiBold, Color.White)
                    }
                }) { m.approvePlan() }
                RoundIconButton(!m.planBusy, { refine = true }) { Icon(Icons.Default.Edit, "Préciser", tint = Soin.ink) }
                RoundIconButton(!m.planBusy, { confirmRefuse = true }) { Icon(Icons.Default.Close, "Refuser", tint = Soin.ink) }
            }
            T("Rien ne se fait sans votre accord.", 13.sp, color = Soin.secondary)
        }
    }
    if (confirmRefuse) AlertDialog(
        onDismissRequest = { confirmRefuse = false },
        title = { Text("Refuser ce plan ?") },
        text = { Text("Rien ne sera fait, et l'ordinateur de ${m.senior} l'indiquera.") },
        confirmButton = {
            TextButton({ confirmRefuse = false; m.refusePlan() }) { Text("Refuser le plan", color = Soin.danger) }
        },
        dismissButton = { TextButton({ confirmRefuse = false }) { Text("Annuler", color = Soin.ink) } },
        containerColor = Soin.card,
    )
    if (refine) Sheet(onClose = { refine = false }) { RefineSheet { refine = false } }
    val f = m.frame
    if (zoom && f != null) ZoomDialog(f) { zoom = false }
}

@Composable
fun RefineSheet(onClose: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            T("Préciser le plan", 24.sp, FontWeight.Bold)
            T("Dites ou écrivez à Holo ce qu'il doit changer. Il proposera un nouveau plan.", 15.sp, color = Soin.secondary)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoinField(text, { text = it }, "Par exemple : les photos sont dans Images > Noël 2025",
                    Modifier.weight(1f), single = false, minLines = 3,
                    keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
                MicButton({ text }, { text = it; error = null }, { error = it })
            }
            error?.let { T(it, 14.sp) } ?: Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.GraphicEq, null, Modifier.size(16.dp), tint = Soin.secondary)
                T("Le micro ajoute ce que vous dites ; l'envoi reste manuel.", 14.sp, color = Soin.secondary)
            }
        }
        CapsuleButton("Envoyer à Holo", enabled = text.isNotBlank()) {
            val t = text.trim()
            if (t.isNotEmpty()) { Helper.refinePlan(t); onClose() }
        }
        TextLink("Annuler", onClick = onClose)
    }
}
