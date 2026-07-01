package com.example.watcharcade.data

/**
 * 游戏目录。新增游戏时在这里登记一行即可。
 * icon 是 Material 图标名（见 GameIcon 映射）。
 */
data class GameDef(
    val id: String,
    val title: String,
    val subtitle: String,
    val icon: String,
    val color: androidx.compose.ui.graphics.Color
)

object GameRegistry {
    val games: List<GameDef> = listOf(
        GameDef("reaction",   "反应速度",   "变绿就点",   "bolt",       androidx.compose.ui.graphics.Color(0xFF22E3C6)),
        GameDef("whack",      "打地鼠",     "点了就得分", "pest_control",androidx.compose.ui.graphics.Color(0xFFFFB454)),
        GameDef("memory",     "翻牌配对",   "记住位置",   "style",      androidx.compose.ui.graphics.Color(0xFF6FA8FF)),
        GameDef("simon",      "记忆顺序",   "跟我重复",   "queue_music", androidx.compose.ui.graphics.Color(0xFFB482FF)),
        GameDef("swipe",      "滑动冲刺",   "按方向滑",   "swipe",      androidx.compose.ui.graphics.Color(0xFF3FB1E3)),
        GameDef("number",     "数字记忆",   "记数字",     "pin",        androidx.compose.ui.graphics.Color(0xFFFF5C8A)),
        GameDef("snake",      "贪吃蛇",     "吃方块",     "gamepad",    androidx.compose.ui.graphics.Color(0xFF22E3C6)),
        GameDef("merge",      "2048",       "合并数字",   "apps",       androidx.compose.ui.graphics.Color(0xFFFFD66B))
    )

    fun byId(id: String): GameDef? = games.firstOrNull { it.id == id }
}
