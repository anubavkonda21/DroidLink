/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Material 3 application theme, dynamic color adaptation, and custom indigo/violet palette.
 */

package com.droidlink.companion.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

// DroidLink palette (AJ's choice: indigo & violet). Keep in sync with mac/DroidLink/Models/Palette.swift.
val Indigo = Color(0xFF5E5CE6)
val IndigoLight = Color(0xFF9B99FF)
val IndigoDark = Color(0xFF3634A3)
val Violet = Color(0xFFBF5AF2)
val VioletLight = Color(0xFFDA8FFF)

private val DarkColorScheme = darkColorScheme(
    primary = IndigoLight,
    onPrimary = Color(0xFF14123D),
    primaryContainer = IndigoDark,
    onPrimaryContainer = Color.White,
    secondary = VioletLight,
    onSecondary = Color(0xFF2A0D3D),
    tertiary = Violet,
    background = Color(0xFF0D0D14),
    onBackground = Color(0xFFE6E5F0),
    surface = Color(0xFF15151F),
    onSurface = Color(0xFFE6E5F0),
    surfaceVariant = Color(0xFF23232F),
    onSurfaceVariant = Color(0xFFC6C4D6)
)

private val LightColorScheme = lightColorScheme(
    primary = Indigo,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE2E1FF),
    onPrimaryContainer = IndigoDark,
    secondary = Violet,
    onSecondary = Color.White,
    tertiary = Violet,
    background = Color(0xFFF6F5FB),
    onBackground = Color(0xFF1A1A24),
    surface = Color.White,
    onSurface = Color(0xFF1A1A24),
    surfaceVariant = Color(0xFFE6E5F1),
    onSurfaceVariant = Color(0xFF45445A)
)

@Composable
fun DroidLinkTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false, // our own palette, not the wallpaper colours
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window
            if (window != null) {
                window.statusBarColor = colorScheme.background.toArgb()
                WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
