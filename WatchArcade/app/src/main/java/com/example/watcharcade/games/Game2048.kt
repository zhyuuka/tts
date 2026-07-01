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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.ui.common.GameScaffold
import com.example.watcharcade.ui.common.Haptic
import com.example.watcharcade.ui.common.PillButton
import com.example.watcharcade.ui.theme.Surface
import com.example.watcharcade.ui.theme.Tile1024
import com.example.watcharcade.ui.theme.Tile128
import com.example.watcharcade.ui.theme.Tile16
import com.example.watcharcade.ui.theme.Tile2
import com.example.watcharcade.ui.theme.Tile2048
import com.example.watcharcade.ui.theme.Tile256
import com.example.watcharcade.ui.theme.Tile32
import com.example.watcharcade.ui.theme.Tile4
import com.example.watcharcade.ui.theme.Tile512
import com.example.watcharcade.ui.theme.Tile64
import com.example.watcharcade.ui.theme.Tile8
import kotlin.random.Random

private const val N = 4

/** 2048：4x4，点击方向键滑动合并。分数=合并产生的数值累加。 */
@Composable
fun Game2048(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit) {
    val ctx = LocalContext.current
    var board by remember { mutableStateOf(newBoard()) }
    var score by remember { mutableLongStateOf(0L) }
    var over by remember { mutableStateOf(false) }
    var won by remember { mutableStateOf(false) }

    fun spawn(b: Array<IntArray>): Array<IntArray> {
        val empty = mutableListOf<Pair<Int, Int>>()
        for (i in 0 until N) for (j in 0 until N) if (b[i][j] == 0) empty.add(i to j)
        if (empty.isEmpty()) return b
        val (i, j) = empty.random(Random)
        b[i][j] = if (Random.nextFloat() < 0.9f) 2 else 4
        return b
    }

    fun reset() {
        val b = Array(N) { IntArray(N) }
        spawn(b); spawn(b)
        board = b; score = 0; over = false; won = false
    }

    fun canMove(b: Array<IntArray>): Boolean {
        for (i in 0 until N) for (j in 0 until N) {
            if (b[i][j] == 0) return true
            if (i + 1 < N && b[i][j] == b[i + 1][j]) return true
            if (j + 1 < N && b[i][j] == b[i][j + 1]) return true
        }
        return false
    }

    // dir: 0左 1右 2上 3下
    fun move(dir: Int) {
        if (over || won) return
        val b = board.map { it.copyOf() }.toTypedArray()
        var gained = 0L
        var moved = false

        // 把每行/列按方向规整成一维数组处理
        fun lines(): List<MutableList<Int>> = when (dir) {
            0 -> (0 until N).map { i -> (0 until N).map { j -> b[i][j] }.toMutableList() }
            1 -> (0 until N).map { i -> (N - 1 downTo 0).map { j -> b[i][j] }.toMutableList() }
            2 -> (0 until N).map { j -> (0 until N).map { i -> b[i][j] }.toMutableList() }
            else -> (0 until N).map { j -> (N - 1 downTo 0).map { i -> b[i][j] }.toMutableList() }
        }

        val newLines = lines().map { line -> merge(line).also { gained += it.second } }
        newLines.forEachIndexed { idx, (merged, _) ->
            when (dir) {
                0 -> for (j in 0 until N) b[idx][j] = merged[j]
                1 -> for (j in 0 until N) b[idx][N - 1 - j] = merged[j]
                2 -> for (i in 0 until N) b[i][idx] = merged[i]
                else -> for (i in 0 until N) b[N - 1 - i][idx] = merged[i]
            }
        }
        // 判断是否移动
        for (i in 0 until N) for (j in 0 until N) if (b[i][j] != board[i][j]) moved = true
        if (!moved) return

        score += gained
        spawn(b)
        board = b
        if (gained > 0) Haptic.tap(ctx, 25)
        submit(score)
        if (!won && b.any { row -> row.any { it == 2048 } }) {
            won = true; Haptic.pattern(ctx, longArrayOf(0, 80, 80, 200, 80))
        }
        if (!canMove(b)) {
            over = true; Haptic.pattern(ctx, longArrayOf(0, 120, 80, 120))
        }
    }

    GameScaffold(def.title, "$score", "$best", def.color, onExit) {
        Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
            // 棋盘
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                for (i in 0 until N) {
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        for (j in 0 until N) {
                            Tile(board[i][j])
                        }
                    }
                }
            }
            if (over || won) {
                PillButton(if (won) "通关！再来" else "再来 · 得分 $score", def.color) { reset() }
            } else {
                Dpad4(onLeft = { move(0) }, onRight = { move(1) }, onUp = { move(2) }, onDown = { move(3) })
            }
        }
    }
}

@Composable
private fun Tile(v: Int) {
    val color = when (v) {
        2 -> Tile2; 4 -> Tile4; 8 -> Tile8; 16 -> Tile16; 32 -> Tile32; 64 -> Tile64
        128 -> Tile128; 256 -> Tile256; 512 -> Tile512; 1024 -> Tile1024; 2048 -> Tile2048
        else -> Surface
    }
    Box(
        Modifier
            .size(28.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(color),
        contentAlignment = Alignment.Center
    ) {
        if (v != 0) Text(
            "$v",
            color = if (v <= 4) Color(0xFF8A94A6) else Color(0xFF0B0F14),
            fontWeight = FontWeight.Bold,
            fontSize = if (v < 100) 13.sp else if (v < 1000) 11.sp else 9.sp
        )
    }
}

@Composable
private fun Dpad4(onLeft: () -> Unit, onRight: () -> Unit, onUp: () -> Unit, onDown: () -> Unit) {
    val b: @Composable (String, () -> Unit) -> Unit = { t, f ->
        Box(
            Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Surface)
                .clickable(onClick = f),
            contentAlignment = Alignment.Center
        ) { Text(t, color = Color(0xFFE8EDF2), fontWeight = FontWeight.Bold, fontSize = 14.sp) }
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        b("↑", onUp)
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { b("←", onLeft); b("→", onRight) }
        b("↓", onDown)
    }
}

// 合并一行（已朝左对齐），返回合并后的列表与新增分数
private fun merge(line: List<Int>): Pair<List<Int>, Long> {
    val nums = line.filter { it != 0 }
    val out = mutableListOf<Int>()
    var gained = 0L
    var i = 0
    while (i < nums.size) {
        if (i + 1 < nums.size && nums[i] == nums[i + 1]) {
            val v = nums[i] * 2
            out.add(v); gained += v; i += 2
        } else {
            out.add(nums[i]); i++
        }
    }
    while (out.size < N) out.add(0)
    return out to gained
}

private fun newBoard(): Array<IntArray> {
    val b = Array(N) { IntArray(N) }
    // spawn twice
    val e = mutableListOf<Pair<Int, Int>>()
    for (i in 0 until N) for (j in 0 until N) e.add(i to j)
    val (a, c) = e.random(Random) to e.random(Random)
    b[a.first][a.second] = 2
    if (a != c) b[c.first][c.second] = 2 else b[0][0] = 2
    return b
}
