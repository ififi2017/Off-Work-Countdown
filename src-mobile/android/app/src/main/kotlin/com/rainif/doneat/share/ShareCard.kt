package com.rainif.doneat.share

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip
import androidx.core.graphics.withSave
import com.rainif.doneat.R

/** The eight moods of the share picker (iOS `ShareMood`); the code point is the stable identity. */
enum class ShareMood(val code: String, val emoji: String, val label: Int) {
    HAPPY("1f604", "😄", R.string.moodHappy),
    RELAXED("1f60c", "😌", R.string.moodRelaxed),
    TIRED("1f62b", "😫", R.string.moodTired),
    CRYING("1f62d", "😭", R.string.moodCounting),
    FIRED_UP("1f525", "🔥", R.string.moodFiredUp),
    EXCITED("1f929", "🤩", R.string.moodExcited),
    CELEBRATING("1f973", "🥳", R.string.moodCelebrating),
    COFFEE("2615", "☕️", R.string.moodCoffee),
}

/** Everything the card draws, already worded: hours and times only, never salary. */
data class ShareCardModel(val mood: ShareMood, val hero: String, val message: String, val progress: Double, val percent: String)

/**
 * The shareable image (iOS `ShareCard`), drawn straight onto a bitmap.
 *
 * Every size is fixed in points on a 360 × 450 card and drawn at 3×, like
 * iOS's `ImageRenderer`: the picture leaves the device, so it must look the
 * same whatever the sender's font size. The composer previews this same
 * bitmap, so there is one drawing, not a preview and a copy.
 */
object ShareCard {
    const val WIDTH = 360f
    const val HEIGHT = 450f
    private const val SCALE = 3f

    private val orange = 0xFFF97316.toInt() // iOS OWCDesign.orange (0.976, 0.451, 0.086)
    private val red = 0xFFE82E3D.toInt() // (0.91, 0.18, 0.24)

    private fun typeface(weight: Int): Typeface =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) Typeface.create(Typeface.DEFAULT, weight, false)
        else if (weight >= 600) Typeface.DEFAULT_BOLD else Typeface.DEFAULT

    private fun paint(size: Float, weight: Int, alpha: Float = 1f) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = size
        typeface = typeface(weight)
        color = android.graphics.Color.WHITE
        this.alpha = (alpha * 255).toInt()
    }

    /** Shrinks [paint] toward [minimumScale] until [text] fits [width], as SwiftUI's `minimumScaleFactor`. */
    private fun fitWidth(paint: TextPaint, text: String, width: Float, minimumScale: Float) {
        val base = paint.textSize
        val measured = paint.measureText(text)
        if (measured > width) paint.textSize = base * maxOf(minimumScale, width / measured)
    }

    private fun layout(text: String, paint: TextPaint, width: Int, maxLines: Int) =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setIncludePad(false)
            .build()

    fun render(context: Context, model: ShareCardModel): Bitmap {
        val bitmap = createBitmap((WIDTH * SCALE).toInt(), (HEIGHT * SCALE).toInt())
        val canvas = Canvas(bitmap)
        canvas.scale(SCALE, SCALE)
        draw(context, canvas, model)
        return bitmap
    }

    private fun draw(context: Context, canvas: Canvas, model: ShareCardModel) {
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(0f, 0f, WIDTH, HEIGHT, orange, red, Shader.TileMode.CLAMP)
        }
        canvas.drawRect(0f, 0f, WIDTH, HEIGHT, background)
        val inset = 22f
        val inner = WIDTH - inset * 2

        // Brand row: the app icon and the mixed-case name.
        drawIcon(context, canvas, RectF(inset, inset, inset + 22f, inset + 22f))
        val brand = paint(10f, 700).apply { letterSpacing = 0.03f }
        canvas.drawText("DoneAt", inset + 30f, inset + 11f - (brand.descent() + brand.ascent()) / 2, brand)

        // Footer: progress capsule, then the percentage and the site.
        val footerText = paint(9f, 600, alpha = 0.85f).apply {
            letterSpacing = 0.04f
            fontFeatureSettings = "tnum"
        }
        val footerBaseline = HEIGHT - inset - footerText.descent()
        val barBottom = footerBaseline + footerText.ascent() - 8f
        val barTop = barBottom - 5f
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE; alpha = (0.35 * 255).toInt() }
        canvas.drawRoundRect(inset, barTop, inset + inner, barBottom, 2.5f, 2.5f, track)
        val filled = inner * (model.progress / 100).coerceIn(0.0, 1.0).toFloat()
        if (filled > 0) {
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
            canvas.drawRoundRect(inset, barTop, inset + filled, barBottom, 2.5f, 2.5f, fill)
        }
        canvas.drawText(model.percent, inset, footerBaseline, footerText)
        val site = "DoneAt.app"
        canvas.drawText(site, inset + inner - footerText.measureText(site), footerBaseline, footerText)

        // The middle block, centred between the brand row and the bar.
        val emoji = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 72f }
        val hero = paint(38f, 900).apply {
            letterSpacing = -1f / 38f
            fontFeatureSettings = "tnum"
            textAlign = Paint.Align.CENTER
        }
        fitWidth(hero, model.hero, inner, 0.58f)
        val message = paint(13f, 600)
        var messageLayout = layout(model.message, message, inner.toInt(), Int.MAX_VALUE)
        if (messageLayout.lineCount > 2) {
            message.textSize = 13f * 0.76f
            messageLayout = layout(model.message, message, inner.toInt(), 2)
        }
        val heroHeight = hero.descent() - hero.ascent()
        val blockHeight = 82f + 12f + heroHeight + 10f + messageLayout.height
        val top = inset + 22f + ((barTop - inset - 22f) - blockHeight) / 2

        val emojiWidth = emoji.measureText(model.mood.emoji)
        canvas.drawText(model.mood.emoji, (WIDTH - emojiWidth) / 2, top + 41f - (emoji.descent() + emoji.ascent()) / 2, emoji)
        val heroText = TextUtils.ellipsize(model.hero, hero, inner, TextUtils.TruncateAt.END).toString()
        canvas.drawText(heroText, WIDTH / 2, top + 82f + 12f - hero.ascent(), hero)
        canvas.withSave {
            translate(inset, top + 82f + 12f + heroHeight + 10f)
            messageLayout.draw(this)
        }
    }

    /** The launcher icon's two layers, cropped to the visible 72 of 108 units, in a rounded square. */
    private fun drawIcon(context: Context, canvas: Canvas, rect: RectF) {
        val clip = Path().apply { addRoundRect(rect, 6f, 6f, Path.Direction.CW) }
        canvas.withClip(clip) {
            val bleed = rect.width() * (108f / 72f - 1f) / 2
            val bounds = android.graphics.Rect(
                (rect.left - bleed).toInt(), (rect.top - bleed).toInt(),
                (rect.right + bleed).toInt(), (rect.bottom + bleed).toInt(),
            )
            for (id in listOf(R.drawable.ic_launcher_background, R.drawable.ic_launcher_foreground)) {
                ContextCompat.getDrawable(context, id)?.let {
                    it.bounds = bounds
                    it.draw(this)
                }
            }
        }
    }
}
