/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Material 3 application theme, dynamic color adaptation, and custom teal/green palette.
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

// Custom DroidLink Teal/Emerald Palette
val TealPrimary = Color(0xFF00897B)
val TealPrimaryDark = Color(0xFF005B4F)
val TealPrimaryLight = Color(0xFF4EBAAA)
val TealAccent = Color(0xFF00BFA5)
val TealSecondary = Color(0xFF26A69A)

val DarkBackground = Color(0xFF101615)
val DarkSurface = Color(0xFF192321)
val DarkSurfaceVariant = Color(0xFF253330)

val LightBackground = Color(0xFFF7FAF9)
val LightSurface = Color(0xFFFFFFFF)
val LightSurfaceVariant = Color(0xFFE4ECE9)

private val DarkColorScheme = darkColorScheme(
    primary = TealPrimaryLight,
    onPrimary = Color.Black,
    primaryContainer = TealPrimaryDark,
    onPrimaryContainer = Color.White,
    secondary = TealAccent,
    onSecondary = Color.Black,
    background = DarkBackground,
    onBackground = Color(0xFFE2E3E2),
    surface = DarkSurface,
    onSurface = Color(0xFFE2E3E2),
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = Color(0xFFCAC5C4)
)

private val LightColorScheme = lightColorScheme(
    primary = TealPrimary,
    onPrimary = Color.White,
    primaryContainer = TealPrimaryLight,
    onPrimaryContainer = Color.Black,
    secondary = TealSecondary,
    onSecondary = Color.White,
    background = LightBackground,
    onBackground = Color(0xFF191C1B),
    surface = LightSurface,
    onSurface = Color(0xFF191C1B),
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = Color(0xFF3F4947)
)

@Composable
fun DroidLinkTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
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
