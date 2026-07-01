# 游戏厅 · WatchArcade

一款 **Wear OS（安卓手表）** 上的迷你游戏合集，内置 **8 款** 主题各异、操作极简的小游戏。
专为圆形 / 方形小屏幕设计，全部操作用「点 / 滑 / 方向键」即可完成，单手可玩。

> 已在沙箱内用 **Android SDK + AGP 8.10.1 + Kotlin 2.1 + Compose** 真实编译通过，
> 产出可安装的 `app-debug.apk`（见文末「构建验证」）。

---

## 内置 8 款游戏

| # | 游戏 | 玩法 | 操作 | 计分 |
|---|------|------|------|------|
| 1 | 反应速度 | 屏幕变绿立刻点，提前点算失败 | 点击 | 1000−反应毫秒 |
| 2 | 打地鼠 | 3×3 网格随机冒头，30 秒内点中越多越好 | 点击 | 命中数 |
| 3 | 翻牌配对 | 4×4 共 8 对符号，记住位置配对消除 | 点击 | 通关即满分 800 |
| 4 | 记忆顺序 | 四色块按序列亮起，按顺序重复，每轮 +1 | 点色块 | 成功轮数×10 |
| 5 | 滑动冲刺 | 屏幕给方向箭头，朝该方向滑，连对越多越快 | 滑动 | 连续正确数 |
| 6 | 数字记忆 | 显示一串数字（位数递增）后凭记忆输入 | 数字键盘 | 最长通过的位数 |
| 7 | 贪吃蛇 | 经典蛇吃方块，撞墙/自身结束 | 方向键 | 吃到数 |
| 8 | 2048 | 4×4 滑动合并相同数字，凑出 2048 | 方向键 | 合并累加 |

每款游戏都会把**最高分**持久化到本地（SharedPreferences），并显示在游戏卡片与对局顶栏。

---

## 技术栈

- **平台**：Wear OS（`android.hardware.type.watch`，`minSdk=30`，`targetSdk=34`）
- **语言**：Kotlin 2.1
- **UI**：Jetpack Compose + Material3 + Wear Compose
- **导航**：Navigation-Compose
- **构建**：Gradle 8.14（Kotlin DSL，已自带 gradlew wrapper）
- **无第三方游戏引擎**，全部用 Compose / Canvas 原生绘制，体积小、启动快

---

## 目录结构

```
WatchArcade/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── gradlew / gradlew.bat
├── gradle/wrapper/
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml          # Wear OS 声明、震动权限、独立应用标记
        ├── res/                         # 图标、主题、字符串、配色
        └── java/com/example/watcharcade/
            ├── MainActivity.kt          # 入口 + NavHost（hub ↔ game/{id}）
            ├── data/
            │   ├── GameRegistry.kt      # 游戏目录（新增游戏在这里登记一行）
            │   └── ScoreStore.kt        # 最高分持久化
            ├── ui/
            │   ├── theme/               # 配色、字体、MaterialTheme
            │   ├── common/              # GameScaffold / Haptic / GameIcon / PillButton
            │   └── screens/
            │       ├── HubScreen.kt     # 2 列游戏网格
            │       └── GameScreen.kt    # 按 id 调度到具体游戏
            └── games/
                ├── ReactionGame.kt
                ├── WhackAMole.kt
                ├── MemoryGame.kt
                ├── SimonGame.kt
                ├── SwipeDashGame.kt
                ├── NumberMemoryGame.kt
                ├── SnakeGame.kt
                └── Game2048.kt
```

---

## 构建方法

### 前置要求
- **JDK 17**（AGP 8.10 不兼容 JDK 21+，请用 17）
- **Android SDK**，含 `platforms;android-34` 与 `build-tools;34.0.0`

### 1. 配置 SDK 路径
在项目根目录创建 `local.properties`（已被 .gitignore 忽略），写入你的 SDK 路径：

```
sdk.dir=/path/to/Android/Sdk
```

> 若用 Android Studio 打开本工程，会自动生成该文件。

### 2. 命令行构建

```bash
# Debug APK
./gradlew :app:assembleDebug
# 产物：app/build/outputs/apk/debug/app-debug.apk

# Release APK（需自备签名配置）
./gradlew :app:assembleRelease
```

### 3. 安装到手表

```bash
# 手表开启「开发者选项 → ADB 调试」后：
adb install -r app/build/outputs/apk/debug/app-debug.apk
# 在手表应用列表中找到「游戏厅」启动
```

> 也可在 Android Studio 中直接选 Wear OS 设备/模拟器「Run」。

---

## 构建验证（沙箱内实测）

| 项 | 结果 |
|----|------|
| Gradle 配置评估 | ✅ `gradle help` 通过 |
| `:app:assembleDebug` | ✅ BUILD SUCCESSFUL |
| 产物 APK | ✅ `app-debug.apk`（约 56 MB，debug 含所有 so） |
| `aapt2 dump badging` | ✅ `package=com.example.watcharcade`，`launchable-activity=MainActivity`，`uses-feature: android.hardware.type.watch` |

> 注：本沙箱构建时为联网下载依赖临时启用了 Gradle 代理与 `org.gradle.java.home` 指向 JDK 17，
> 这两项**已从交付的 `gradle.properties` 中移除**——它们只在沙箱内验证用，不应进入你的工程。
> 你本地只需保证默认 `java` 为 JDK 17 即可直接 `./gradlew assembleDebug`。

---

## 新增一款游戏（扩展指南）

1. 在 `games/` 下新建 `XxxGame.kt`，签名统一为：
   ```kotlin
   @Composable
   fun XxxGame(def: GameDef, best: Long, onExit: () -> Unit, submit: (Long) -> Unit)
   ```
   得分后调用 `submit(score)` 即自动更新最高分。
2. 在 `data/GameRegistry.kt` 的 `games` 列表加一行 `GameDef("xxx", "标题", "副标题", "图标名", 颜色)`。
3. 在 `ui/screens/GameScreen.kt` 的 `when(gameId)` 加一个分支。

完成，无需改动其它文件——主菜单会自动多出一个卡片。

---

## 设计说明

- **视觉**：暗色舞台（`#0B0F14`）+ 青绿霓虹主色，各游戏配独立强调色，圆形表盘友好。
- **操作**：全部为「点 / 滑 / 四向键」，无长按、无多点、无复杂手势，单指可玩。
- **反馈**：得分、失误、通关均有触觉震动（`Haptic`），强化手表体感。
- **独立应用**：Manifest 标记 `com.google.android.wearable.standalone`，可不依赖手机独立运行。
