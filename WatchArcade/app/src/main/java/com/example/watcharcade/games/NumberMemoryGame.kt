package com.example.watcharcade.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
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
import com.example.watcharcade.ui.theme.Neon
import com.example.watcharcade.ui.theme.Surface
import com.example.watcharcade.ui.theme.SurfaceHi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

/** 数字记忆：每轮显示一串数字（长度递增），消失后玩家点数字键盘输入；正确进入下一轮。分数=最长通过的位数。 */
@Composable
fun NumberMemoryGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var phase by remember { mutableStateOf("IDLE") }  // IDLE / SHOW / INPUT / OVER
    var level by remember { mutableLongStateOf(3L) }
    var number by remember { mutableStateOf("") }
    var typed by remember { mutableStateOf("") }
    var score by remember { mutableLongStateOf(0L) }

    fun gen() {
        level = if (phase == "IDLE" || phase == "OVER") 3 else level + 1
        number = buildString { repeat(level.toInt()) { append(Random.nextInt(10)) } }
        typed = ""
        phase = "SHOW"
    }

    LaunchedEffect(phase) {
        if (phase == "SHOW") {
            delay(800 + level * 400)
            phase = "INPUT"
        }
    }

    val scope = androidx.compose.runtime.rememberCoroutineScope()

    fun press(d: Int) {
        if (phase != "INPUT") return
        Haptic.tap(ctx, 10)
        typed += d
        if (typed.length == number.length) {
            if (typed == number) {
                score = level
                Haptic.tap(ctx, 50)
                scope.launch { delay(400); gen() }
            } else {
                phase = "OVER"; submit(score)
                Haptic.pattern(ctx, longArrayOf(0, 100, 80, 100))
            }
        }
    }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        when (phase) {
            "IDLE", "OVER" -> Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                if (phase == "OVER") Text("失败！最长 $score 位", color = Color(0xFFFF5252), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                PillButton(if (phase == "IDLE") "开始" else "再来", def.color) {
                    score = 0; gen()
                }
            }
            "SHOW" -> Box(
                Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)).background(Surface),
                contentAlignment = Alignment.Center
            ) {
                Text(number, color = Neon, fontWeight = FontWeight.Bold, fontSize = 28.sp)
            }
            "INPUT" -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("输入 ${typed.length}/${number.length}", color = Color(0xFF8A94A6), fontSize = 11.sp)
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier.fillMaxWidth().height(28.dp).clip(RoundedCornerShape(8.dp)).background(Surface),
                    contentAlignment = Alignment.Center
                ) {
                    Text("●".repeat(typed.length).ifEmpty { "—" }, color = Neon, fontSize = 18.sp, letterSpacing = 4.sp)
                }
                Spacer(Modifier.height(6.dp))
                KeypadGrid(onKey = { press(it) })
            }
        }
    }
}

private val rows = listOf(listOf(1,2,3), listOf(4,5,6), listOf(7,8,9), listOf(0))

@Composable
private fun KeypadGrid(onKey: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        rows.forEach { r ->
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                r.forEach { d ->
                    Box(
                        Modifier
                            .size(26.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(SurfaceHi)
                            .clickable { onKey(d) },
                        contentAlignment = Alignment.Center
                    ) { Text("$d", color = Color(0xFFE8EDF2), fontWeight = FontWeight.Bold, fontSize = 14.sp) }
                }
            }
        }
    }
}
