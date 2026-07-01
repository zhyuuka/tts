package com.example.watcharcade.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.CornerSize

private val AppTypography = Typography(
    displaySmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 22.sp, color = TextMain),
    headlineSmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 18.sp, color = TextMain),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = TextMain),
    bodyMedium = TextStyle(fontWeight = FontWeight.Normal, fontSize = 13.sp, color = TextMain),
    labelSmall = TextStyle(fontWeight = FontWeight.Medium, fontSize = 11.sp, color = TextMuted)
)

@Composable
fun WatchArcadeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = androidx.compose.material3.darkColorScheme(
            primary = Neon,
            onPrimary = Color(0xFF04140F),
            background = Bg,
            surface = Surface,
            onSurface = TextMain,
            secondary = NeonAlt,
            onSecondary = Color(0xFF1A0710),
            tertiary = Info,
            error = Danger,
            outline = Outline
        ),
        typography = AppTypography,
        shapes = androidx.compose.material3.Shapes(
            small = RoundedCornerShape(6.dp),
            medium = RoundedCornerShape(10.dp),
            large = RoundedCornerShape(14.dp)
        ),
        content = content
    )
}
