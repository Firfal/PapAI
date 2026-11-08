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
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Design « Soin », version bleue : fond lavande clair en léger dégradé, en-tête et bouton
 * principal en dégradé bleu, cartes blanches à ombre douce. Contraste AA vérifié
 * (blanc sur `accent` 5,7:1, sur `accentEnd` 4,5:1 ; `accent` sur blanc 5,7:1).
 */
object Soin {
    val bg = Color(0xFFF1F4FC)
    val bgEnd = Color(0xFFEDEBFA)
    val card = Color.White
    val ink = Color(0xFF111827)
    val secondary = Color(0xFF586174)
    val accent = Color(0xFF1F5BE8)
    val accentEnd = Color(0xFF2B6BFF)
    val accentSoft = Color(0xFFE8EFFF)
    val online = Color(0xFF1E8E4E)
    val danger = Color(0xFFC8442F)
    /** Teinte des ombres (Android en règle lui-même l'opacité, très faible). */
    val shadow = Color(0xFF2A3A80)

    /** Fond des écrans : lavande très clair, du haut vers le bas. */
    val screenBrush: Brush get() = Brush.verticalGradient(listOf(bg, bgEnd))

    /** En-têtes et bouton principal. */
    val accentBrush: Brush get() = Brush.horizontalGradient(listOf(accent, accentEnd))

    /** En-tête : plus clair en haut, plus soutenu en bas, comme la maquette (texte blanc AA sur les deux). */
    val headerBrush: Brush get() = Brush.verticalGradient(listOf(accentEnd, accent))
}

/** Fond d'écran en léger dégradé. */
fun Modifier.soinScreen(): Modifier = background(Soin.screenBrush)

/** Carte arrondie ; les cartes blanches portent une ombre douce et diffuse. */
fun Modifier.soinCard(fill: Color = Soin.card, radius: Dp = 20.dp): Modifier {
    val shape = RoundedCornerShape(radius)
    val lifted = if (fill == Soin.card) shadow(8.dp, shape, ambientColor = Soin.shadow, spotColor = Soin.shadow) else this
    return lifted.clip(shape).background(fill)
}

/** Bouton plein en capsule. Bleu dégradé par défaut (bouton principal), sinon couleur unie. */
@Composable
fun CapsuleButton(
    label: String,
    modifier: Modifier = Modifier,
    fill: Color = Soin.accent,
    text: Color = Color.White,
    enabled: Boolean = true,
    content: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    val primary = fill == Soin.accent
    val lifted = when {
        primary && enabled -> Modifier.shadow(8.dp, CircleShape, ambientColor = Soin.accent, spotColor = Soin.accent)
        fill == Soin.card -> Modifier.shadow(3.dp, CircleShape, ambientColor = Soin.shadow, spotColor = Soin.shadow)
        else -> Modifier
    }
    Box(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .then(lifted)
            .clip(CircleShape)
            .then(
                if (primary && enabled) Modifier.background(Soin.accentBrush)
                else Modifier.background(if (enabled) fill else fill.copy(alpha = 0.45f))
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (content != null) content()
        else Text(label, color = if (enabled) text else text.copy(alpha = 0.7f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun RoundIconButton(enabled: Boolean = true, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.size(58.dp)
            .shadow(3.dp, CircleShape, ambientColor = Soin.shadow, spotColor = Soin.shadow)
            .clip(CircleShape).background(Soin.card)
            .alpha(if (enabled) 1f else 0.45f)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}
