package com.quentin.papai.aidant

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun DoneScreen() {
    val m = Helper
    var zoom by remember { mutableStateOf<ImageBitmap?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(Modifier.fillMaxWidth().soinCard(Soin.accentSoft, 28.dp).padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Check, null, Modifier.size(16.dp), tint = Soin.accent)
                T("Terminé", 13.sp, FontWeight.SemiBold, Soin.accent)
            }
            if (m.task.isNotEmpty()) T("« ${m.task} »", 14.sp, color = Soin.secondary)
            T(m.doneAnswer ?: "Holo a terminé.", 20.sp, FontWeight.SemiBold)
        }
        val saved = m.savedTitle
        when {
            saved != null -> Row(Modifier.fillMaxWidth().soinCard().padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(34.dp).clip(CircleShape).background(Soin.accent), contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Check, null, Modifier.size(18.dp), tint = Color.White)
                }
                T("Automate « $saved » enregistré.", 16.sp, FontWeight.SemiBold)
            }
            m.hasDraft -> Draft { zoom = it }
            else -> {
                CapsuleButton("", enabled = !m.lessonBusy, content = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (m.lessonBusy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                        T(if (m.lessonBusy) "Rédaction en cours…" else "Garder comme automate", 17.sp, FontWeight.SemiBold, Color.White)
                    }
                }) { m.requestLesson() }
                T("Holo transforme cette assistance en automate que ${m.senior} pourra relancer sans aide.", 13.sp, color = Soin.secondary)
            }
        }
    }
    zoom?.let { ZoomDialog(it) { zoom = null } }
}

@Composable
private fun Draft(onZoom: (ImageBitmap) -> Unit) {
    val m = Helper
    val sentence = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        T("Brouillon de l'automate", 17.sp, FontWeight.SemiBold)
        SoinField(m.draftTitle, { m.draftTitle = it }, "Titre", size = 18.sp, weight = FontWeight.SemiBold, keyboard = sentence)
        Row(Modifier.fillMaxWidth().soinCard().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Default.Folder, null, tint = Soin.accent)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T("La tuile ouvrira", 13.sp, FontWeight.SemiBold, Soin.secondary)
                T(m.draftTarget ?: "Aucun dossier : ${m.senior} aura seulement les étapes.", 16.sp, FontWeight.SemiBold)
            }
        }
        m.draftSteps.forEachIndexed { i, s ->
            Column(Modifier.fillMaxWidth().soinCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                T("Étape ${i + 1}", 13.sp, FontWeight.SemiBold, Soin.accent)
                SoinField(s.instruction, { s.instruction = it }, "Instruction", size = 16.sp, single = false,
                    fill = Soin.bg, radius = 14.dp, keyboard = sentence)
                s.checkpoint?.let { T("${m.seniorTitle} doit voir : $it", 13.sp, color = Soin.secondary) }
                s.preview?.let { p ->
                    // Toute la largeur, et un appui l'ouvre en plein écran.
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { onZoom(p) }) {
                        Image(p, "Agrandir la capture", Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
                        Box(Modifier.align(Alignment.BottomEnd).padding(8.dp).size(34.dp).clip(CircleShape).background(Soin.card),
                            contentAlignment = Alignment.Center) { Icon(Icons.Default.OpenInFull, null, Modifier.size(16.dp), tint = Soin.ink) }
                    }
                }
            }
        }
        CapsuleButton("Valider") { m.approveLesson() }
    }
}
