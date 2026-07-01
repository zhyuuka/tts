package com.example.watcharcade.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.ui.common.GameScaffold
import com.example.watcharcade.ui.common.Haptic
import com.example.watcharcade.ui.common.PillButton
import com.example.watcharcade.ui.theme.Info
import com.example.watcharcade.ui.theme.Neon
import com.example.watcharcade.ui.theme.NeonAlt
import com.example.watcharcade.ui.theme.Surface
import com.example.watcharcade.ui.theme.Warn
import kotlinx.coroutines.delay
import kotlin.random.Random

private data class Card(val sym: String, val faceUp: Boolean = false, val matched: Boolean = false)

/** 翻牌配对：4x4 共8对符号，点开两张相同则消除。分数=配对数；每对100。 */
@Composable
fun MemoryGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var cards by remember { mutableStateOf(newDeck()) }
    var flipped by remember { mutableStateOf(listOf<Int>()) }
    var matchedCount by remember { mutableLongStateOf(0L) }
    var lock by remember { mutableStateOf(false) }

    LaunchedEffect(flipped) {
        if (flipped.size == 2) {
            lock = true
            val (a, b) = flipped
            if (cards[a].sym == cards[b].sym) {
                delay(300)
                cards = cards.mapIndexed { i, c -> if (i == a || i == b) c.copy(matched = true) else c }
                matchedCount++
                Haptic.tap(ctx, 30)
                if (matchedCount == 8L) {
                    delay(200)
                    val score = 800L
                    submit(score)
                    Haptic.pattern(ctx, longArrayOf(0, 80, 80, 200, 80))
                }
            } else {
                delay(700)
                cards = cards.mapIndexed { i, c -> if (i == a || i == b) c.copy(faceUp = false) else c }
                Haptic.tap(ctx, 10)
            }
            flipped = emptyList(); lock = false
        }
    }

    GameScaffold(def.title, "${matchedCount * 100}", "$best", def.color, onExit) {
        if (matchedCount == 8L) {
            Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                Text("通关！", color = Neon, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                PillButton("再来一局", def.color) {
                    cards = newDeck(); flipped = emptyList(); matchedCount = 0; lock = false
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(4),
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(cards.indices.toList()) { i ->
                    val c = cards[i]
                    val bg = when {
                        c.matched -> Color.Transparent
                        c.faceUp -> colorFor(c.sym)
                        else -> Surface
                    }
                    Box(
                        Modifier
                            .size(30.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(bg)
                            .clickable(enabled = !lock && !c.faceUp && !c.matched) {
                                cards = cards.mapIndexed { idx, cc -> if (idx == i) cc.copy(faceUp = true) else cc }
                                flipped = flipped + i
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        if (c.faceUp || c.matched) {
                            Text(c.sym, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color(0xFF0B0F14))
                        }
                    }
                }
            }
        }
    }
}

private val SYMBOLS = listOf("★", "♥", "◆", "●", "▲", "✦", "✚", "♪")
private fun newDeck(): List<Card> {
    val pairs = SYMBOLS + SYMBOLS
    return pairs.shuffled(Random).map { Card(it) }
}
private fun colorFor(sym: String): Color = when (SYMBOLS.indexOf(sym) % 4) {
    0 -> Neon; 1 -> Warn; 2 -> Info; else -> NeonAlt
}
