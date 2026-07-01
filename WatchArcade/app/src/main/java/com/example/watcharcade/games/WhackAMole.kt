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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.ui.common.GameScaffold
import com.example.watcharcade.ui.common.Haptic
import com.example.watcharcade.ui.common.PillButton
import com.example.watcharcade.ui.theme.NeonAlt
import com.example.watcharcade.ui.theme.Surface
import kotlinx.coroutines.delay
import kotlin.random.Random

/** 打地鼠：3x3 网格，随机亮起一格，点中得分，30 秒计时。 */
@Composable
fun WhackAMole(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var running by remember { mutableStateOf(false) }
    var score by remember { mutableLongStateOf(0L) }
    var timeLeft by remember { mutableIntStateOf(30) }
    var moleAt by remember { mutableIntStateOf(-1) }
    val holes = remember { (0..8).toList() }

    LaunchedEffect(running) {
        if (running) {
            score = 0; timeLeft = 30
            while (timeLeft > 0) {
                moleAt = Random.nextInt(9)
                delay(650L)
                moleAt = -1
                delay(120L)
                timeLeft--
            }
            running = false
            submit(score)
            Haptic.pattern(ctx, longArrayOf(0, 80, 80, 80))
        }
    }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        if (!running) {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                PillButton("开始 · 30秒", def.color) { running = true }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                items(holes) { idx ->
                    val isMole = idx == moleAt
                    Box(
                        Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(if (isMole) NeonAlt else Surface)
                            .clickable {
                                if (isMole) {
                                    score++; Haptic.tap(ctx, 12); moleAt = -1
                                }
                            }
                    )
                }
            }
        }
    }
}
