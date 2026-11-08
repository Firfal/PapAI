package com.quentin.papai.aidant

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
 * Palette unique de PapAI, la même que `apps/shared/Palette.swift` (Mac et iPhone) : fond
 * bleu-lavande très clair, cartes blanches à ombre douce, un seul accent bleu. Textes
 * secondaires et bleus de texte à au moins 4,5:1 sur le blanc et sur le fond.
 */
object Soin {
    val bg = Color(0xFFF1F4FD)
    val card = Color.White
    val ink = Color(0xFF141A33)
    val secondary = Color(0xFF5A6178)
    /** Bleu d'accent : icônes, onglet choisi, boutons. */
    val accent = Color(0xFF2F6EF7)
    /** Bleu de texte sur blanc ou bleu pâle. */
    val accentText = Color(0xFF1D4FD7)
    val accentDeep = Color(0xFF1A56E0)
    /** Bleu pâle : pastilles, ronds d'icône, encarts. */
    val accentSoft = Color(0xFFEAF1FF)
    val online = Color(0xFF12A15E)
    /** Champ de saisie posé sur une carte blanche. */
    val field = Color(0xFFF2F4FA)
    /** Séparateurs, filets des cartes et des champs. */
    val line = Color(0xFFE3E7F2)
    val danger = Color(0xFFC8442F)
    /** Teinte des ombres (Android en règle lui-même l'opacité, très faible). */
    val shadow = Color(0xFF2A3F8F)

    /** Fond des écrans : bleuté en haut, lavande en bas. */
    val screenBrush: Brush get() = Brush.verticalGradient(listOf(Color(0xFFEDF2FE), Color(0xFFF2EFFC)))

    /** Bouton principal : bleu assez soutenu pour un texte blanc à 4,5:1 partout. */
    val accentBrush: Brush get() = Brush.linearGradient(listOf(accent, accentDeep))

    /** En-tête : dégradé bleu vif de gauche à droite, titre blanc. */
    val headerBrush: Brush get() = Brush.horizontalGradient(listOf(Color(0xFF1F5FF0), Color(0xFF3D7FFF)))

    /** Fond et texte des pastilles (`TonPastille` sur Mac et iPhone). */
    fun tone(t: Tone): Pair<Color, Color> = when (t) {
        Tone.BLUE -> accentSoft to accentText
        Tone.VIOLET -> Color(0xFFF1EAFE) to Color(0xFF6236C7)
        Tone.GREEN -> Color(0xFFE4F5EA) to Color(0xFF1C6E3F)
        Tone.ORANGE -> Color(0xFFFFF0E0) to Color(0xFF9A4706)
        Tone.GRAY -> Color(0xFFEEF0F5) to Color(0xFF4D5468)
    }
}

/** Fond d'écran en léger dégradé. */
fun Modifier.soinScreen(): Modifier = background(Soin.screenBrush)

/** Carte arrondie ; les cartes blanches portent une ombre douce et diffuse. */
fun Modifier.soinCard(fill: Color = Soin.card, radius: Dp = 20.dp): Modifier {
    val shape = RoundedCornerShape(radius)
    val white = fill == Soin.card
    val lifted = if (white) shadow(8.dp, shape, ambientColor = Soin.shadow, spotColor = Soin.shadow) else this
    return lifted.clip(shape).background(fill)
        .border(1.dp, if (white) Soin.line else Soin.accent.copy(alpha = 0.12f), shape)
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
