package com.quentin.papai.aidant

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Design « Soin », mêmes couleurs que les apps Mac et iPhone. */
object Soin {
    val bg = Color(0xFFEEF0EE)
    val card = Color.White
    val ink = Color(0xFF111312)
    val secondary = Color(0xFF7A807C)
    val accent = Color(0xFF2E9E5B)
    val accentSoft = Color(0xFFE2F2E7)
    val danger = Color(0xFFC62828)
}

fun Modifier.soinCard(fill: Color = Soin.card, radius: Dp = 22.dp): Modifier =
    clip(RoundedCornerShape(radius)).background(fill)

/** Bouton plein en capsule (encre par défaut). */
@Composable
fun CapsuleButton(
    label: String,
    modifier: Modifier = Modifier,
    fill: Color = Soin.ink,
    text: Color = Color.White,
    enabled: Boolean = true,
    content: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .clip(CircleShape)
            .background(fill)
            .alpha(if (enabled) 1f else 0.45f)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (content != null) content()
        else Text(label, color = text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun RoundIconButton(enabled: Boolean = true, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.size(58.dp).clip(CircleShape).background(Soin.card)
            .alpha(if (enabled) 1f else 0.45f)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}
