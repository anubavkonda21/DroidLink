/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Navigation graph with Home (Connection & Notifications) and Settings.
 */

package com.droidlink.companion.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.droidlink.companion.ui.HomeScreen
import com.droidlink.companion.ui.SettingsScreen

sealed class NavDestination(
    val route: String,
    val title: String,
    val icon: ImageVector
) {
    data object Home : NavDestination("home", "Notifications", Icons.Default.Home)
    data object Settings : NavDestination("settings", "Settings", Icons.Default.Settings)

    companion object {
        val items = listOf(Home, Settings)
    }
}

@Composable
fun DroidLinkApp(
    navController: NavHostController = rememberNavController(),
    onRequestPermissions: () -> Unit
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavDestination.items.forEach { destination ->
                    val isSelected = currentRoute == destination.route
                    NavigationBarItem(
                        selected = isSelected,
                        onClick = {
                            if (currentRoute != destination.route) {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        },
                        icon = {
                            Icon(
                                imageVector = destination.icon,
                                contentDescription = destination.title
                            )
                        },
                        label = { Text(destination.title) }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = NavDestination.Home.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(NavDestination.Home.route) {
                HomeScreen(onRequestPermissions = onRequestPermissions)
            }
            composable(NavDestination.Settings.route) {
                SettingsScreen()
            }
        }
    }
}
