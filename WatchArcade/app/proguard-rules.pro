# 默认 ProGuard 规则
-keep class com.example.watcharcade.** { *; }

# Compose / Kotlin 反射相关，避免运行时崩溃
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**
-keep class kotlin.reflect.** { *; }

# SharedPreferences
-keep class android.content.SharedPreferences { *; }
