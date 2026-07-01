package com.example.watcharcade.ui.common

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Gamepad
import androidx.compose.material.icons.outlined.Pin
import androidx.compose.material.icons.outlined.PestControl
import androidx.compose.material.icons.outlined.QueueMusic
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material.icons.outlined.Swipe
import androidx.compose.ui.graphics.vector.ImageVector

/** 把 GameDef.icon 字符串映射到具体图标。 */
fun gameIcon(name: String): ImageVector = when (name) {
    "bolt"         -> Icons.Outlined.Bolt
    "pest_control" -> Icons.Outlined.PestControl
    "style"        -> Icons.Outlined.Style
    "queue_music"  -> Icons.Outlined.QueueMusic
    "swipe"        -> Icons.Outlined.Swipe
    "pin"          -> Icons.Outlined.Pin
    "gamepad"      -> Icons.Outlined.Gamepad
    "apps"         -> Icons.Outlined.Apps
    else           -> Icons.Outlined.Apps
}
