package com.quentin.papai.aidant

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Pause
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

@Composable
fun ActiveScreen() {
    val m = Helper
    val caption = when {
        m.seniorPaused -> "Aide en pause"
        m.planStep != null && m.plan.isNotEmpty() -> "Étape ${minOf(m.planStep!!, m.plan.size)} sur ${m.plan.size}"
        else -> "Holo agit"
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            CaptureView()
            Column(Modifier.fillMaxWidth().soinCard().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusPill(caption, if (m.seniorPaused) Tone.GRAY else Tone.BLUE) {
                    if (m.seniorPaused) Icon(Icons.Default.Pause, null, Modifier.size(16.dp), tint = Soin.secondary)
                    else CircularProgressIndicator(Modifier.size(14.dp), color = Soin.accent, strokeWidth = 2.dp)
                }
                T(if (m.webLive) "Holo travaille dans ${m.webBrowserTitle}"
                  else if (m.seniorPaused) "${m.seniorTitle} a mis l'aide en pause. Holo attend la reprise."
                  else m.doing ?: "Holo regarde l'écran de ${m.senior}…", 19.sp, FontWeight.SemiBold, maxLines = 3)
            }
        }
        CapsuleButton(if (m.pausing) "Pause demandée…" else "Mettre en pause",
            Modifier.padding(horizontal = 20.dp, vertical = 8.dp), fill = Soin.card, text = Soin.ink,
            enabled = !m.pausing) { m.pause() }
    }
}

/** Capture de l'écran de l’utilisateur, avec le viseur quand on prend la main. */
@Composable
fun CaptureView() {
    val m = Helper
    val img = m.frame
    if (img == null) {
        Box(Modifier.fillMaxWidth().heightIn(min = 180.dp).soinCard(), contentAlignment = Alignment.Center) {
            T(if (m.webLive) "En attente de la première image de Chrome PapAI…"
              else "En attente de la première capture d'écran…", 15.sp, color = Soin.secondary)
        }
        return
    }
    val shape = RoundedCornerShape(22.dp)
    Box(
        Modifier.fillMaxWidth().aspectRatio(img.width.toFloat() / img.height).clip(shape)
            .border(2.dp, if (m.aiming) Soin.accent else Color.Transparent, shape)
            .pointerInput(m.aiming) {
                if (!m.aiming) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown()
                    fun set(p: Offset) {
                        m.target = Offset((p.x / size.width).coerceIn(0f, 1f), (p.y / size.height).coerceIn(0f, 1f))
                    }
                    set(down.position); down.consume()
                    while (true) {
                        val e = awaitPointerEvent()
                        val c = e.changes.firstOrNull { it.id == down.id } ?: break
                        if (!c.pressed) break
                        set(c.position); c.consume()
                    }
                }
            },
    ) {
        Image(img, if (m.webLive) m.webBrowserTitle else "Écran de ${m.senior}",
            Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
        val t = m.target
        if (m.aiming && t != null) Canvas(Modifier.fillMaxSize()) {
            val c = Offset(t.x * size.width, t.y * size.height)
            val shadow = Color.Black.copy(alpha = 0.4f)
            drawCircle(shadow, 14.dp.toPx(), c, style = Stroke(4.dp.toPx()))
            drawCircle(Soin.accent, 14.dp.toPx(), c, style = Stroke(2.dp.toPx()))
            val l = 23.dp.toPx()
            drawLine(Soin.accent, c.copy(y = c.y - l), c.copy(y = c.y + l), 2.dp.toPx())
            drawLine(Soin.accent, c.copy(x = c.x - l), c.copy(x = c.x + l), 2.dp.toPx())
        }
    }
}

/** Loupe ×3 posée au-dessus de l'image : le doigt cacherait la cible sinon. */
@Composable
fun Loupe(image: ImageBitmap, target: Offset) {
    val shape = RoundedCornerShape(22.dp)
    BoxWithConstraints(Modifier.fillMaxWidth().height(124.dp).clip(shape).background(Color.Black).border(2.dp, Soin.accent, shape)) {
        Canvas(Modifier.fillMaxSize()) {
            // L'image affichée fait la largeur de la loupe ; on la grossit 3 fois.
            val scale = 3f * size.width / image.width
            val srcW = (size.width / scale).coerceAtMost(image.width.toFloat())
            val srcH = (size.height / scale).coerceAtMost(image.height.toFloat())
            val tx = target.x * image.width
            val ty = target.y * image.height
            val sx = (tx - srcW / 2).coerceIn(0f, image.width - srcW)
            val sy = (ty - srcH / 2).coerceIn(0f, image.height - srcH)
            drawImage(
                image, IntOffset(sx.roundToInt(), sy.roundToInt()), IntSize(srcW.roundToInt(), srcH.roundToInt()),
                dstSize = IntSize((srcW * scale).roundToInt(), (srcH * scale).roundToInt()),
            )
            val c = Offset((tx - sx) * scale, (ty - sy) * scale)
            val a = Soin.accent.copy(alpha = 0.9f)
            drawLine(a, Offset(c.x, 0f), Offset(c.x, size.height), 1.dp.toPx())
            drawLine(a, Offset(0f, c.y), Offset(size.width, c.y), 1.dp.toPx())
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HelperScreen() {
    val m = Helper
    var reply by rememberSaveable { mutableStateOf("") }
    fun sendReply() {
        val t = reply.trim()
        if (t.isNotEmpty()) { m.answer(t); reply = "" }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState(), enabled = !m.aiming)
        .padding(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        val q = m.question
        if (m.aiming) {
            val img = m.frame; val t = m.target
            if (img != null && t != null) Loupe(img, t)
        } else if (q != null) {
            Column(Modifier.fillMaxWidth().soinCard(Soin.accentSoft, 28.dp).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                T(if (m.webLive) "Holo a une question"
                  else if (m.questionToSenior) "Question posée à ${m.senior} sur son écran. Vous pouvez aussi répondre."
                  else "${m.seniorTitle} a besoin de vous", 13.sp, color = Soin.secondary)
                T(q.text, 20.sp, FontWeight.SemiBold)
                if (q.options.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    q.options.forEach { o ->
                        T(o, 15.sp, FontWeight.SemiBold, modifier = Modifier.clip(CircleShape).background(Soin.card)
                            .clickable { m.answer(o) }.padding(horizontal = 16.dp, vertical = 11.dp))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SoinField(reply, { reply = it }, "Votre réponse…", Modifier.weight(1f), size = 16.sp, radius = 28.dp,
                        keyboard = KeyboardOptions(imeAction = ImeAction.Send), onDone = ::sendReply)
                    Box(Modifier.size(52.dp).clip(CircleShape).background(Soin.accentBrush).clickable(onClick = ::sendReply),
                        contentAlignment = Alignment.Center) { Icon(Icons.Default.ArrowUpward, "Envoyer", tint = Color.White) }
                }
            }
        }
        if (m.webLive) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T(m.webBrowserTitle, 17.sp, FontWeight.SemiBold)
                T("Holo agit seulement dans le navigateur. Répondez à ses questions ici.", 13.sp, color = Soin.secondary)
            }
        }
        CaptureView()
        if (!m.webLive) {
            if (m.aiming) AimBar() else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CapsuleButton("Prendre la main") { m.setAimingOn(true) }
                T("Vous pouvez cliquer vous-même sur l'écran de ${m.senior}.", 13.sp, color = Soin.secondary)
            }
        }
    }
}

@Composable
private fun AimBar() {
    val m = Helper
    val now = rememberNow()
    val age = m.frameAt?.let { ((now - it) / 1000).toInt() } ?: Int.MAX_VALUE
    val stale = age >= Helper.FRAME_TTL_S
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.fillMaxWidth().soinCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            T(if (m.target == null) "Touchez l'écran de ${m.senior} à l'endroit où il faut cliquer."
              else "Ajustez en gardant le doigt appuyé, puis confirmez.", 15.sp, FontWeight.SemiBold)
            T(if (stale) "Cette capture est trop ancienne : l'écran a pu changer."
              else "Capture d'il y a $age s, valable ${Helper.FRAME_TTL_S - age} s encore.", 13.sp,
                color = if (stale) Soin.ink else Soin.secondary)
            if (stale) T("Rafraîchir", 14.sp, FontWeight.SemiBold, Soin.accent, Modifier.clickable { m.refresh() }.padding(vertical = 4.dp))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CapsuleButton(if (m.sending) "Envoi…" else "Cliquer ici", Modifier.weight(1f),
                enabled = m.target != null && !stale && !m.sending) { m.confirmClick() }
            CapsuleButton("Annuler", Modifier.width(130.dp), fill = Soin.card, text = Soin.ink) { m.setAimingOn(false) }
        }
    }
}
