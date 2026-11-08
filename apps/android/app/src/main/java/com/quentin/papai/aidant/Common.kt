package com.quentin.papai.aidant

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay

/** Heure courante, rafraîchie toutes les `periodMs` (compte à rebours, « il y a 3 min »). */
@Composable
fun rememberNow(periodMs: Long = 1000): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(periodMs) {
        while (true) { now = System.currentTimeMillis(); delay(periodMs) }
    }
    return now
}

@Composable
fun T(
    text: String,
    size: TextUnit = 16.sp,
    weight: FontWeight = FontWeight.Normal,
    color: Color = Soin.ink,
    modifier: Modifier = Modifier,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) = Text(text, modifier, color = color, fontSize = size, fontWeight = weight, textAlign = align,
    maxLines = maxLines, lineHeight = size * 1.25f)

/** Champ de saisie « Soin » : carte blanche arrondie, texte d'exemple gris. */
@Composable
fun SoinField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    size: TextUnit = 17.sp,
    weight: FontWeight = FontWeight.Normal,
    single: Boolean = true,
    keyboard: KeyboardOptions = KeyboardOptions.Default,
    onDone: (() -> Unit)? = null,
    align: TextAlign = TextAlign.Start,
    radius: Dp = 18.dp,
    fill: Color = Soin.card,
    minLines: Int = 1,
) {
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = single,
        minLines = minLines,
        textStyle = TextStyle(fontSize = size, fontWeight = weight, color = Soin.ink, textAlign = align),
        keyboardOptions = keyboard,
        keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }, onSend = { onDone?.invoke() }),
        modifier = modifier.fillMaxWidth().soinCard(fill, radius).padding(16.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) T(placeholder, size, weight, Soin.secondary.copy(alpha = 0.7f),
                    Modifier.fillMaxWidth(), align)
                inner()
            }
        },
    )
}

/** Capture en plein écran ; un appui n'importe où la ferme. */
@Composable
fun ZoomDialog(image: ImageBitmap, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Soin.ink).clickable(onClick = onClose).systemBarsPadding()) {
            Image(image, "Capture agrandie", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            Box(
                Modifier.align(Alignment.TopEnd).padding(20.dp).size(44.dp).clip(CircleShape)
                    .background(Soin.card).clickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Default.Close, "Fermer", tint = Soin.ink) }
        }
    }
}

/**
 * Micro : la reconnaissance vocale d'Android (Google) en français.
 * Le texte reconnu est ajouté à `base`, l'envoi reste manuel.
 */
@Composable
fun MicButton(base: () -> String, onText: (String) -> Unit, onError: (String) -> Unit) {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
        val heard = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
        if (heard.isNullOrEmpty()) return@rememberLauncherForActivityResult
        val b = base().trim()
        onText(if (b.isEmpty()) heard else "$b $heard")
    }
    Box(
        Modifier.size(56.dp).clip(CircleShape).background(Soin.accentBrush).clickable {
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "fr-FR")
                .putExtra(RecognizerIntent.EXTRA_PROMPT, "Je vous écoute…")
            try { launcher.launch(i) } catch (_: Exception) {
                onError("La dictée n'est pas disponible sur ce téléphone.")
            }
        },
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Default.Mic, "Dicter", tint = Color.White) }
}

@Composable
fun SheetTitle(s: String) = T(s, 28.sp, FontWeight.Bold)

@Composable
fun FieldLabel(s: String) = T(s, 13.sp, FontWeight.SemiBold, Soin.secondary)

@Composable
fun TextLink(s: String, color: Color = Soin.secondary, onClick: () -> Unit) =
    T(s, 16.sp, FontWeight.SemiBold, color,
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(10.dp),
        TextAlign.Center)
