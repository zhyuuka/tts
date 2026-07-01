package com.example.watcharcade.games

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowLeft
import androidx.compose.material.icons.outlined.ArrowRight
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.unit.sp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.ui.common.GameScaffold
import com.example.watcharcade.ui.common.Haptic
import com.example.watcharcade.ui.common.PillButton
import com.example.watcharcade.ui.theme.Neon
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.random.Random

/** 滑动冲刺：屏幕给一个方向箭头，玩家朝该方向滑；正确+1并加速，错误/超时结束。分数=连续正确数。 */
@Composable
fun SwipeDashGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var score by remember { mutableLongStateOf(0L) }
    var target by remember { mutableStateOf(Random.nextInt(4)) }
    var running by remember { mutableStateOf(false) }
    var over by remember { mutableStateOf(false) }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        if (!running) {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (over) Text("结束！得分 $score", color = Color(0xFFFF5252), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                PillButton(if (over) "再来" else "开始", def.color) {
                    score = 0; over = false; running = true; target = Random.nextInt(4)
                }
            }
        } else {
            val arrows = listOf(Icons.Outlined.ArrowLeft, Icons.Outlined.ArrowUpward, Icons.Outlined.ArrowRight, Icons.Outlined.ArrowDownward)
            Box(
                Modifier
                    .fillMaxSize()
                    .clip(CircleShape)
                    .background(Neon.copy(alpha = 0.12f))
                    .pointerInput(score) {
                        detectDragGestures(
                            onDragEnd = { },
                            onDrag = { change, delta ->
                                change.consume()
                            }
                        )
                    }
                    .pointerInput(score) {
                        // 用按下后的大幅移动判定方向
                        var sx = 0f; var sy = 0f
                        detectDragGestures(
                            onDragStart = { off -> sx = off.x; sy = off.y },
                            onDragEnd = { },
                            onDrag = { change, delta ->
                                sx += delta.x; sy += delta.y
                                change.consume()
                                val tx = abs(sx); val ty = abs(sy)
                                if (tx + ty > 28f) {
                                    val dir = when {
                                        tx > ty && sx > 0 -> 2   // right
                                        tx > ty && sx <= 0 -> 0  // left
                                        ty > tx && sy > 0 -> 3   // down
                                        else -> 1                 // up
                                    }
                                    sx = 0f; sy = 0f
                                    if (dir == target) {
                                        score++; Haptic.tap(ctx, 20)
                                        target = Random.nextInt(4)
                                    } else {
                                        running = false; over = true; submit(score)
                                        Haptic.pattern(ctx, longArrayOf(0, 100, 80, 100))
                                    }
                                }
                            }
                        )
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(arrows[target], contentDescription = "方向", tint = Neon, modifier = Modifier.fillMaxSize(0.5f))
            }
        }
    }
}
