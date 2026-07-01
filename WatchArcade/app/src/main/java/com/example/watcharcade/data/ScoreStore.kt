package com.example.watcharcade.data

import android.content.Context
import android.content.SharedPreferences

/**
 * 各游戏最佳分数持久化。键 = 游戏id，值 = 该游戏的最高分（含义由各游戏定义）。
 */
object ScoreStore {
    private const val PREFS = "watch_arcade_scores"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun best(ctx: Context, gameId: String): Long =
        prefs(ctx).getLong(gameId, 0L)

    fun submit(ctx: Context, gameId: String, score: Long): Long {
        val p = prefs(ctx)
        val prev = p.getLong(gameId, 0L)
        // 分数越高越好（反应、记忆等通用规则）。具体游戏内部已把"用时"换算为分数。
        val newBest = if (score > prev) score else prev
        if (newBest != prev) p.edit().putLong(gameId, newBest).apply()
        return newBest
    }

    fun reset(ctx: Context, gameId: String) {
        prefs(ctx).edit().remove(gameId).apply()
    }

    fun resetAll(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }
}
