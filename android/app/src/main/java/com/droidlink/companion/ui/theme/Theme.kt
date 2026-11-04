/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Material 3 application theme, dynamic color adaptation, and custom mint palette.
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

// DroidLink palette: mint to match the app icon (mint squircle, dark green bolt), on neutral greys.
// No purple/indigo/violet (AJ). Keep the Mac's Palette.swift in mind if this changes.
val Mint = Color(0xFF5CD6A3)
val MintLight = Color(0xFFA8F0D1)
val ForestGreen = Color(0xFF0B3D2E)
val MintDeep = Color(0xFF1F8A63)

/** Extra colours for icons and tiles, so each feature has its own colour. */
object Accents {
    val Orange = Color(0xFFFF9F0A)
    val Blue = Color(0xFF0A84FF)
    val Pink = Color(0xFFFF375F)
    val Teal = Color(0xFF30B0C7)
    val Yellow = Color(0xFFFFD60A)
    val Green = Color(0xFF30D158)
}

private val DarkColorScheme = darkColorScheme(
    primary = Mint,
    onPrimary = ForestGreen,
    primaryContainer = Color(0xFF14513C),
    onPrimaryContainer = MintLight,
    secondary = Accents.Teal,
    onSecondary = Color.Black,
    tertiary = Accents.Orange,
    background = Color(0xFF000000),
    onBackground = Color(0xFFF2F2F7),
    surface = Color(0xFF1C1C1E),
    onSurface = Color(0xFFF2F2F7),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFFAEAEB2)
)

private val LightColorScheme = lightColorScheme(
    primary = MintDeep,
    onPrimary = Color.White,
    primaryContainer = MintLight,
    onPrimaryContainer = ForestGreen,
    secondary = Accents.Teal,
    onSecondary = Color.White,
    tertiary = Accents.Orange,
    background = Color(0xFFF2F2F7),
    onBackground = Color(0xFF1C1C1E),
    surface = Color.White,
    onSurface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFFE5E5EA),
    onSurfaceVariant = Color(0xFF48484A)
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
