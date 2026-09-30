package com.rainif.doneat.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance

/** Opaque RGB seeds; neutral surfaces and semantic status colours keep their meaning. */
object DoneAtAccent {
    val presets = listOf(0xDC2626, 0xEAB308, 0x16A34A, 0x0D9488, 0x2563EB, 0x6366F1, 0x9333EA, 0xDB2777)

    fun parseHex(text: String): Int? = text.trim().removePrefix("#")
        .takeIf { it.length == 6 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' } }
        ?.toIntOrNull(16)

    fun hex(rgb: Int) = "#%06X".format(rgb and 0xFFFFFF)
    fun color(rgb: Int) = Color(0xFF000000.toInt() or (rgb and 0xFFFFFF))

    fun scheme(rgb: Int, dark: Boolean): ColorScheme {
        val base = if (dark) DoneAtColors.dark else DoneAtColors.light
        val seed = color(rgb)
        val primary = readable(seed, base, dark)
        val container = lerp(base.surface, seed, if (dark) 0.22f else 0.14f)
        return base.copy(
            primary = primary,
            onPrimary = foreground(primary),
            primaryContainer = container,
            onPrimaryContainer = foreground(container),
            inversePrimary = readable(seed, if (dark) DoneAtColors.light else DoneAtColors.dark, !dark),
            surfaceTint = primary,
        )
    }

    fun foreground(background: Color) = if (contrast(Color.Black, background) >= contrast(Color.White, background)) Color.Black else Color.White

    private fun contrast(a: Color, b: Color): Float {
        val x = a.luminance()
        val y = b.luminance()
        return (maxOf(x, y) + 0.05f) / (minOf(x, y) + 0.05f)
    }

    /** Text buttons and links appear on every surface; preserve the seed until AA needs a tone change. */
    private fun readable(seed: Color, base: ColorScheme, dark: Boolean): Color {
        val surfaces = listOf(base.surface, base.surfaceContainerLowest, base.surfaceContainerLow,
            base.surfaceContainer, base.surfaceContainerHigh, base.surfaceContainerHighest)
        fun passes(color: Color) = surfaces.all { contrast(color, it) >= 4.6f }
        if (passes(seed)) return seed
        val end = if (dark) Color.White else Color.Black
        var low = 0f
        var high = 1f
        repeat(16) {
            val mid = (low + high) / 2f
            if (passes(lerp(seed, end, mid))) high = mid else low = mid
        }
        return lerp(seed, end, high)
    }
}
