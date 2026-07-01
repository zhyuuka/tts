package com.example.watcharcade.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.watcharcade.data.GameDef
import com.example.watcharcade.data.GameRegistry
import com.example.watcharcade.data.ScoreStore
import com.example.watcharcade.ui.common.gameIcon
import com.example.watcharcade.ui.theme.Bg
import com.example.watcharcade.ui.theme.Surface

@Composable
fun HubScreen(onOpen: (String) -> Unit) {
    val ctx = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(Bg).padding(10.dp)
    ) {
        Text("游戏厅", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("共 ${GameRegistry.games.size} 款 · 点击开始", style = MaterialTheme.typography.labelSmall)
        Spacer(Modifier.height(6.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(GameRegistry.games, key = { it.id }) { g ->
                val best = ScoreStore.best(ctx, g.id)
                GameTile(g, best) { onOpen(g.id) }
            }
        }
    }
}

@Composable
private fun GameTile(g: GameDef, best: Long, onClick: () -> Unit) {
    Box(
        Modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(12.dp))
            .background(Surface)
            .border(1.dp, g.color.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(8.dp)
    ) {
        Icon(
            imageVector = gameIcon(g.icon),
            contentDescription = g.title,
            tint = g.color,
            modifier = Modifier.align(Alignment.TopStart).size(20.dp)
        )
        Column(Modifier.align(Alignment.BottomStart)) {
            Text(g.title, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = Color(0xFFE8EDF2))
            Text(g.subtitle, fontSize = 10.sp, color = Color(0xFF8A94A6))
            if (best > 0) Text("最高 $best", fontSize = 9.sp, color = g.color)
        }
    }
}
