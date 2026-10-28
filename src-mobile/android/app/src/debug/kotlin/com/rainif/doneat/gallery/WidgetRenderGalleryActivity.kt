package com.rainif.doneat.gallery

import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Bundle
import android.os.LocaleList
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.widget.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/** Isolated QA only: exports the actual renderers, never modifies schedule or entitlement state. */
class WidgetRenderGalleryActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG || packageName != "com.rainif.doneat.parityqa") {
            finish()
            return
        }
        setContent { Text("Rendering isolated widget QA images…") }
        lifecycleScope.launch {
            val graph = (application as DoneAtApplication).graph
            graph.loaded.first { it }
            graph.widgets.refresh()
            val saved = withContext(Dispatchers.IO) {
                WidgetSuiteCoordinator.read(applicationContext) to WidgetCoordinator.read(applicationContext)
            }
            val samples = intent.getBooleanExtra("samples", false)
            val now = if (samples) WidgetRenderSamples.now else graph.nowMs().toLong()
            val locale = intent.getStringExtra("locale")?.takeIf { it in setOf("en", "zh-CN", "ar", "de") } ?: "en"
            val dark = intent.getBooleanExtra("dark", false)
            val fontScale = intent.getFloatExtra("fontScale", 1f).coerceIn(1f, 2f)
            val config = Configuration(resources.configuration).apply {
                setLocales(LocaleList(Locale.forLanguageTag(locale)))
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
                this.fontScale = fontScale
            }
            val context = createConfigurationContext(config)
            val rendered = if (samples) WidgetRenderSamples.make(context, intent.getBooleanExtra("locked", false)) else saved
            val folder = File(cacheDir, "widget-design/${if(samples) if(intent.getBooleanExtra("locked", false)) "samples-locked" else "samples" else "actual"}-$locale-${if (dark) "dark" else "light"}-$fontScale")
            withContext(Dispatchers.Default) {
                folder.mkdirs()
                val sizes = listOf("small" to DpSize(170.dp, 170.dp), "medium" to DpSize(364.dp, 170.dp), "large" to DpSize(364.dp, 382.dp))
                for (kind in DoneAtWidgetKind.entries) for ((label, size) in sizes) {
                    if (kind == DoneAtWidgetKind.DETAIL && label == "small") continue
                    val bitmap = if (kind.countdown) widgetCountdownPreviewBitmap(context, kind, rendered.second, rendered.first, now, size)
                    else widgetCardBitmap(context, widgetSuiteCard(context, kind, rendered.first, now), size)
                    File(folder, "${kind.name.lowercase()}-$label.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    bitmap.recycle()
                }
            }
            setContent { Text("Widget QA export complete: ${folder.name}") }
        }
    }
}
