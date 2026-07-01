package com.example.watcharcade.games

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
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
import com.example.watcharcade.ui.theme.Danger
import com.example.watcharcade.ui.theme.Neon
import kotlinx.coroutines.delay
import kotlin.random.Random

/** 反应速度：红屏等变绿，变绿后尽快点；提前点算失败。分数 = 1000 - 反应毫秒（最小0）。 */
@Composable
fun ReactionGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    // state: WAIT 等待变绿 / GO 已变绿待点 / RESULT 结果 / EARLY 太早
    var phase by remember { mutableStateOf("WAIT") }
    var waitMs by remember { mutableLongStateOf(0L) }
    var goAt by remember { mutableLongStateOf(0L) }
    var resultMs by remember { mutableLongStateOf(0L) }
    var score by remember { mutableLongStateOf(0L) }

    LaunchedEffect(phase) {
        if (phase == "WAIT") {
            waitMs = 800L + Random.nextLong(2200L)
            delay(waitMs)
            goAt = System.currentTimeMillis()
            phase = "GO"
        }
    }

    val bg = when (phase) {
        "GO" -> Neon
        "EARLY" -> Danger
        else -> Color(0xFF2A3441)
    }

    GameScaffold(def.title, score.toString(), best.toString(), def.color, onExit) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(12.dp))
                .background(bg)
                .clickable {
                    when (phase) {
                        "WAIT" -> { Haptic.pattern(ctx, longArrayOf(0, 60, 60, 60)); phase = "EARLY" }
                        "GO" -> {
                            resultMs = System.currentTimeMillis() - goAt
                            score = (1000L - resultMs).coerceAtLeast(0L)
                            Haptic.tap(ctx)
                            submit(score)
                            phase = "RESULT"
                        }
                        "RESULT", "EARLY" -> { phase = "WAIT" }
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            val msg = when (phase) {
                "WAIT" -> if (resultMs > 0) "再来一次" else "等待变绿…"
                "GO" -> "现在点！"
                "EARLY" -> "太早了！\n点击重试"
                else -> "${resultMs}ms\n得分 $score\n点击重试"
            }
            Text(
                msg,
                color = if (phase == "GO") Color(0xFF04140F) else Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
    }
}
