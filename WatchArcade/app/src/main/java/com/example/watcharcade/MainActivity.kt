package com.example.watcharcade

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.watcharcade.ui.theme.WatchArcadeTheme
import com.example.watcharcade.ui.screens.HubScreen
import com.example.watcharcade.ui.screens.GameScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WatchArcadeTheme {
                App()
            }
        }
    }
}

@Composable
private fun App() {
    val nav = rememberNavController()
    androidx.compose.foundation.layout.Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0F14))
    ) {
        NavHost(navController = nav, startDestination = "hub") {
            composable("hub") { HubScreen(onOpen = { id -> nav.navigate("game/$id") }) }
            composable("game/{id}") { backStack ->
                val id = backStack.arguments?.getString("id") ?: ""
                GameScreen(
                    gameId = id,
                    onExit = { nav.popBackStack("hub", inclusive = false) }
                )
            }
        }
    }
}
