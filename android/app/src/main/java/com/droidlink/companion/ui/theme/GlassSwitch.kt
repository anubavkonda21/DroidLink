package com.droidlink.companion.ui.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/**
 * Apple-style switch: a pill track with a white glassy knob that slides with a spring
 * and stretches while pressed. Same API as Material's Switch for the parts we use.
 */
@Composable
fun GlassSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    onColor: Color = MaterialTheme.colorScheme.primary
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val knobWidth by animateDpAsState(if (pressed) 34.dp else 27.dp, spring(stiffness = Spring.StiffnessMedium), label = "knobW")
    // knob's left edge: 2dp inset when off, right-aligned when on (track 51 - 2 inset - knob width)
    val knobX by animateDpAsState(if (checked) 51.dp - 2.dp - knobWidth else 2.dp,
        spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow), label = "knobX")
    val track by animateColorAsState(
        if (checked) onColor else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.16f), label = "track")

    Box(
        modifier = modifier
            .size(width = 51.dp, height = 31.dp)
            .clip(RoundedCornerShape(50))
            .background(track)
            .border(0.5.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
            .toggleable(value = checked, interactionSource = interaction, indication = null,
                role = Role.Switch, onValueChange = onCheckedChange),
        contentAlignment = Alignment.CenterStart
    ) {
        Box(
            modifier = Modifier
                .offset(x = knobX)
                .size(width = knobWidth, height = 27.dp)
                .shadow(3.dp, CircleShape, clip = false)
                .clip(CircleShape)
                // glass: bright top fading to soft white, with a hairline rim
                .background(Brush.verticalGradient(listOf(Color.White, Color(0xFFF1F1F4))))
                .border(0.5.dp, Color.Black.copy(alpha = 0.06f), CircleShape)
        )
    }
}
