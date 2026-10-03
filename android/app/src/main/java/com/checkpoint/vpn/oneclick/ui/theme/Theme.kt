package com.checkpoint.vpn.oneclick.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.checkpoint.vpn.oneclick.R

val DisplayFont = FontFamily(Font(R.font.fraunces_semibold, FontWeight.SemiBold))
val BodyFont = FontFamily(
    Font(R.font.dm_sans_regular, FontWeight.Normal),
    Font(R.font.dm_sans_medium, FontWeight.Medium),
    Font(R.font.dm_sans_semibold, FontWeight.SemiBold),
)
val MonoFont = FontFamily(Font(R.font.ibm_plex_mono_medium, FontWeight.Medium))

val Ink = Color(0xFF0B1210)
val InkElevated = Color(0xFF14201C)
val Mist = Color(0xFFE8F0EC)
val Fog = Color(0xFF9BB0A6)
val Signal = Color(0xFF2FBF8C)
val SignalDim = Color(0xFF1F7A5A)
val Amber = Color(0xFFE2B15C)
val Danger = Color(0xFFE26A5C)

val AtmosphereBrush = Brush.verticalGradient(
    colors = listOf(Color(0xFF0B1210), Color(0xFF12261F), Color(0xFF0E1A16)),
)

private val DarkColors = darkColorScheme(
    primary = Signal,
    onPrimary = Ink,
    secondary = Amber,
    onSecondary = Ink,
    background = Ink,
    onBackground = Mist,
    surface = InkElevated,
    onSurface = Mist,
    surfaceVariant = Color(0xFF1C2A25),
    onSurfaceVariant = Fog,
    outline = Color(0x553DDC97),
    error = Danger,
    onError = Mist,
)

private val LightColors = lightColorScheme(
    primary = SignalDim,
    onPrimary = Color.White,
    secondary = Color(0xFF9A6B1F),
    onSecondary = Color.White,
    background = Color(0xFFF3F7F5),
    onBackground = Ink,
    surface = Color.White,
    onSurface = Ink,
    surfaceVariant = Color(0xFFE3EDE8),
    onSurfaceVariant = Color(0xFF4A5C54),
    outline = Color(0x334A5C54),
    error = Danger,
    onError = Color.White,
)

val AppTypography = Typography(
    displayLarge = TextStyle(fontFamily = DisplayFont, fontWeight = FontWeight.SemiBold, fontSize = 40.sp, letterSpacing = (-0.8).sp),
    headlineMedium = TextStyle(fontFamily = DisplayFont, fontWeight = FontWeight.SemiBold, fontSize = 28.sp),
    titleLarge = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp),
    titleMedium = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp),
    bodyLarge = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.Medium, fontSize = 14.sp),
    labelMedium = TextStyle(fontFamily = BodyFont, fontWeight = FontWeight.Medium, fontSize = 12.sp),
)

val TotpStyle = TextStyle(
    fontFamily = MonoFont,
    fontWeight = FontWeight.Medium,
    fontSize = 32.sp,
    letterSpacing = 3.sp,
)

@Composable
fun CheckpointTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}
