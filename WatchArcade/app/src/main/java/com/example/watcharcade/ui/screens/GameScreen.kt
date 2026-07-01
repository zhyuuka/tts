package com.example.watcharcade.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.example.watcharcade.data.GameRegistry
import com.example.watcharcade.data.ScoreStore
import com.example.watcharcade.games.Game2048
import com.example.watcharcade.games.MemoryGame
import com.example.watcharcade.games.NumberMemoryGame
import com.example.watcharcade.games.ReactionGame
import com.example.watcharcade.games.SimonGame
import com.example.watcharcade.games.SnakeGame
import com.example.watcharcade.games.SwipeDashGame
import com.example.watcharcade.games.WhackAMole

/** 根据 gameId 调度到对应游戏。 */
@Composable
fun GameScreen(gameId: String, onExit: () -> Unit) {
    val ctx = LocalContext.current
    val def = GameRegistry.byId(gameId)
    if (def == null) { onExit(); return }
    val best = ScoreStore.best(ctx, gameId)
    when (gameId) {
        "reaction" -> ReactionGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "whack"    -> WhackAMole(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "memory"   -> MemoryGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "simon"    -> SimonGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "swipe"    -> SwipeDashGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "number"   -> NumberMemoryGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "snake"    -> SnakeGame(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        "merge"    -> Game2048(def, best, onExit) { s -> ScoreStore.submit(ctx, gameId, s) }
        else       -> onExit()
    }
}
