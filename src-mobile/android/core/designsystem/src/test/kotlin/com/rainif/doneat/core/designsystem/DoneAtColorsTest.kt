package com.rainif.doneat.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertTrue
import org.junit.Test

/** Every text-on-background pair the tokens define meets WCAG AA (4.5:1) in both schemes. */
class DoneAtColorsTest {
    private fun contrast(a: Color, b: Color): Double {
        val (hi, lo) = listOf(a.luminance().toDouble(), b.luminance().toDouble()).sortedDescending()
        return (hi + 0.05) / (lo + 0.05)
    }

    private fun pairs(s: ColorScheme) = listOf(
        "onPrimary/primary" to (s.onPrimary to s.primary),
        "onPrimaryContainer/primaryContainer" to (s.onPrimaryContainer to s.primaryContainer),
        "onSecondary/secondary" to (s.onSecondary to s.secondary),
        "onSecondaryContainer/secondaryContainer" to (s.onSecondaryContainer to s.secondaryContainer),
        "onTertiary/tertiary" to (s.onTertiary to s.tertiary),
        "onTertiaryContainer/tertiaryContainer" to (s.onTertiaryContainer to s.tertiaryContainer),
        "onSurface/surface" to (s.onSurface to s.surface),
        "onSurfaceVariant/surface" to (s.onSurfaceVariant to s.surface),
        "onSurfaceVariant/surfaceContainerHighest" to (s.onSurfaceVariant to s.surfaceContainerHighest),
        "onSurface/surfaceContainerLow" to (s.onSurface to s.surfaceContainerLow),
        "primary/surface (text buttons, links)" to (s.primary to s.surface),
        "primary/surfaceContainerLow" to (s.primary to s.surfaceContainerLow),
        "inverseOnSurface/inverseSurface" to (s.inverseOnSurface to s.inverseSurface),
        "error/surface" to (s.error to s.surface),
        "paused meter bubble" to (s.surface to s.onSurfaceVariant),
    )

    private fun states(s: DoneAtStateColors) = listOf(
        "work" to (s.onWork to s.work),
        "rest" to (s.onRest to s.rest),
        "offWork" to (s.onOffWork to s.offWork),
        "overtime" to (s.onOvertime to s.overtime),
        "overtime meter bubble" to (s.onOvertimeMeter to s.overtimeMeter),
    )

    @Test fun textPairsMeetAaInBothSchemes() {
        val failures = ArrayList<String>()
        for ((name, scheme) in listOf("light" to DoneAtColors.light, "dark" to DoneAtColors.dark)) {
            val all = pairs(scheme) + states(DoneAtStateColors.from(scheme, name == "dark"))
            for ((pair, colors) in all) {
                val ratio = contrast(colors.first, colors.second)
                if (ratio < 4.5) failures += "$name $pair: %.2f".format(ratio)
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    @Test fun customAccentsStayReadableAcrossTheRgbCube() {
        val samples = listOf(0, 64, 128, 192, 255)
        val seeds = DoneAtAccent.presets + samples.flatMap { r -> samples.flatMap { g -> samples.map { b -> (r shl 16) or (g shl 8) or b } } }
        for (rgb in seeds) for (dark in listOf(false, true)) {
            val scheme = DoneAtAccent.scheme(rgb, dark)
            for ((name, colors) in pairs(scheme)) {
                assertTrue("${DoneAtAccent.hex(rgb)} dark=$dark $name", contrast(colors.first, colors.second) >= 4.5)
            }
            for (surface in listOf(scheme.surfaceContainerLowest, scheme.surfaceContainer,
                scheme.surfaceContainerHigh, scheme.surfaceContainerHighest)) {
                assertTrue("accent text on tonal surfaces", contrast(scheme.primary, surface) >= 4.5)
            }
        }
    }

    @Test fun hexInputAcceptsOpaqueRgbAndRejectsPartialOrAlphaValues() {
        org.junit.Assert.assertEquals(0x12ABEF, DoneAtAccent.parseHex(" #12aBEf "))
        org.junit.Assert.assertEquals(0, DoneAtAccent.parseHex("000000"))
        org.junit.Assert.assertEquals("#00ABEF", DoneAtAccent.hex(0xABEF))
        for (bad in listOf("", "#123", "#12345G", "FF123456", "-12345", "0x123456")) {
            org.junit.Assert.assertNull(bad, DoneAtAccent.parseHex(bad))
        }
    }

    @Test fun pageAndCardBackgroundsMatchIosAndRemainNeutralWithWallpaperColors() {
        org.junit.Assert.assertEquals(Color(0xFFF2F2F7), DoneAtColors.light.surface)
        org.junit.Assert.assertEquals(Color.White, DoneAtColors.light.surfaceContainerLow)
        org.junit.Assert.assertEquals(Color.Black, DoneAtColors.dark.surface)
        org.junit.Assert.assertEquals(Color(0xFF1C1C1E), DoneAtColors.dark.surfaceContainerLow)
        for (dark in listOf(false, true)) {
            val base = if (dark) DoneAtColors.dark else DoneAtColors.light
            val wallpaper = base.copy(primary = Color.Magenta, surface = Color.Red, surfaceContainerLow = Color.Green)
            val neutral = DoneAtColors.withNeutralSurfaces(wallpaper, dark)
            org.junit.Assert.assertEquals(base.surface, neutral.surface)
            org.junit.Assert.assertEquals(base.surfaceContainerLow, neutral.surfaceContainerLow)
            org.junit.Assert.assertEquals(Color.Magenta, neutral.primary)
        }
    }

    @Test fun outlinesStayVisibleAgainstTheSurface() {
        // Non-text UI (field borders, dividers that carry meaning) needs 3:1.
        for (scheme in listOf(DoneAtColors.light, DoneAtColors.dark)) {
            assertTrue(contrast(scheme.outline, scheme.surface) >= 3.0)
        }
    }

    @Test fun theVividBrandOrangeIsNotReadableAsTextOnLightSurfaces() {
        // Why `primary` is a deeper tone: the brand orange alone would fail AA.
        assertTrue(contrast(DoneAtColors.brand, DoneAtColors.light.surface) < 4.5)
    }
}
