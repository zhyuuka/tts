package com.example.watcharcade.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.Canvas
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowLeft
import androidx.compose.material.icons.outlined.ArrowRight
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material3.Icon
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.ui.common.GameScaffold
import com.example.watcharcade.ui.common.Haptic
import com.example.watcharcade.ui.common.PillButton
import com.example.watcharcade.ui.theme.Neon
import com.example.watcharcade.ui.theme.NeonAlt
import com.example.watcharcade.ui.theme.Surface
import kotlinx.coroutines.delay
import kotlin.random.Random

private const val N = 9

/** 贪吃蛇：方向键控制，吃到食物+1分，撞墙/自身结束。 */
@Composable
fun SnakeGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var snake by remember { mutableStateOf(listOf(N / 2 to N / 2)) }
    var dir by remember { mutableStateOf(1 to 0) }
    var pendingDir by remember { mutableStateOf(1 to 0) }
    var food by remember { mutableStateOf(5 to 5) }
    var score by remember { mutableLongStateOf(0L) }
    var running by remember { mutableStateOf(false) }
    var over by remember { mutableStateOf(false) }

    fun reset() {
        snake = listOf(N / 2 to N / 2)
        dir = 1 to 0; pendingDir = 1 to 0
        food = Random.nextInt(N) to Random.nextInt(N)
        score = 0; over = false; running = true
    }

    LaunchedEffect(running) {
        while (running) {
            delay(260)
            if (pendingDir.first != -dir.first || pendingDir.second != -dir.second) {
                dir = pendingDir
            }
            val head = snake.first()
            val nh = (head.first + dir.first) to (head.second + dir.second)
            if (nh.first < 0 || nh.first >= N || nh.second < 0 || nh.second >= N || snake.contains(nh)) {
                running = false; over = true; submit(score)
                Haptic.pattern(ctx, longArrayOf(0, 120, 80, 120))
                break
            }
            snake = if (nh == food) {
                score++; Haptic.tap(ctx, 20)
                var f: Pair<Int, Int>
                do { f = Random.nextInt(N) to Random.nextInt(N) } while (snake.contains(f) || f == nh)
                food = f
                listOf(nh) + snake
            } else {
                listOf(nh) + snake.dropLast(1)
            }
        }
    }

    fun turn(d: Pair<Int, Int>) {
        if (!running) return
        if (d.first != -dir.first || d.second != -dir.second) pendingDir = d
    }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(120.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Surface)
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val cell = size.minDimension / N
                    // food
                    drawRect(
                        color = NeonAlt,
                        topLeft = Offset(food.first * cell, food.second * cell),
                        size = Size(cell * 0.85f, cell * 0.85f)
                    )
                    // snake
                    snake.forEach { p ->
                        drawRect(
                            color = Neon,
                            topLeft = Offset(p.first * cell, p.second * cell),
                            size = Size(cell * 0.85f, cell * 0.85f)
                        )
                    }
                }
            }
            if (!running) {
                PillButton(if (over) "再来 · 得分 $score" else "开始", def.color) { reset() }
            } else {
                Dpad(
                    onUp = { turn(0 to -1) }, onDown = { turn(0 to 1) },
                    onLeft = { turn(-1 to 0) }, onRight = { turn(1 to 0) }
                )
            }
        }
    }
}

@Composable
private fun Dpad(onUp: () -> Unit, onDown: () -> Unit, onLeft: () -> Unit, onRight: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        DpadBtn(Icons.Outlined.ArrowUpward, onUp)
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            DpadBtn(Icons.Outlined.ArrowLeft, onLeft)
            DpadBtn(Icons.Outlined.ArrowRight, onRight)
        }
        DpadBtn(Icons.Outlined.ArrowDownward, onDown)
    }
}

@Composable
private fun DpadBtn(icon: ImageVector, onClick: () -> Unit) {
    Box(
        Modifier
            .size(26.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Surface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = Neon, modifier = Modifier.size(16.dp))
    }
}
