package com.example.watcharcade.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
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
import com.example.watcharcade.ui.theme.SimonColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

/** 记忆顺序：四色块按序列亮起，玩家按顺序重复，每轮序列+1。分数=成功轮数*10。 */
@Composable
fun SimonGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    val sequence = remember { mutableStateListOf<Int>() }
    var phase by remember { mutableStateOf("IDLE") }   // IDLE / SHOW / INPUT / OVER
    var showIdx by remember { mutableStateOf(-1) }
    var inputIdx by remember { mutableStateOf(0) }
    var score by remember { mutableLongStateOf(0L) }

    LaunchedEffect(phase) {
        if (phase == "SHOW") {
            inputIdx = 0
            for (i in sequence.indices) {
                showIdx = i
                Haptic.tap(ctx, 60)
                delay(450)
                showIdx = -1
                delay(180)
            }
            phase = "INPUT"
        }
    }

    fun startRound() {
        sequence.add(Random.nextInt(4))
        score = sequence.size * 10L - 10L
        phase = "SHOW"
    }

    val scope = androidx.compose.runtime.rememberCoroutineScope()

    fun onPad(i: Int) {
        if (phase != "INPUT") return
        Haptic.tap(ctx, 30)
        if (i == sequence[inputIdx]) {
            inputIdx++
            if (inputIdx == sequence.size) {
                score = sequence.size * 10L
                scope.launch { delay(500); startRound() }
            }
        } else {
            phase = "OVER"
            submit(score)
            Haptic.pattern(ctx, longArrayOf(0, 100, 80, 100))
        }
    }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
            when (phase) {
                "IDLE", "OVER" -> {
                    if (phase == "OVER") Text("失败！得分 $score", color = Color(0xFFFF5252), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    PillButton(if (phase == "IDLE") "开始" else "再来", def.color) {
                        sequence.clear(); score = 0; startRound()
                    }
                }
                else -> {
                    Text(if (phase == "SHOW") "记住…" else "重复 ${inputIdx + 1}/${sequence.size}",
                        color = Color(0xFF8A94A6), fontSize = 11.sp)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        listOf(0 to 1, 2 to 3).forEach { (a, b) ->
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Pad(a, showIdx == a && phase == "SHOW", phase == "INPUT") { onPad(a) }
                                Pad(b, showIdx == b && phase == "SHOW", phase == "INPUT") { onPad(b) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Pad(i: Int, lit: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val base = SimonColors[i]
    Box(
        Modifier
            .size(48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (lit) base else base.copy(alpha = 0.25f))
            .clickable(enabled = enabled, onClick = onClick)
    )
}
