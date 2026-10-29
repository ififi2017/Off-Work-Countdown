package com.rainif.doneat.gallery

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.util.SizeF
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.widget.DoneAtWidgetKind
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** Debug-only native RemoteViews host. Own package only; deletes its allocated IDs on exit. */
class WidgetHostGalleryActivity : ComponentActivity() {
    private lateinit var host: AppWidgetHost
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG || packageName != "com.rainif.doneat.parityqa") { finish(); return }
        host = AppWidgetHost(this, 323)
        // This host is dedicated to this single QA activity, never the user's Launcher.
        host.deleteHost()
        val kind = DoneAtWidgetKind.entries.firstOrNull { it.name == intent.getStringExtra("kind") } ?: DoneAtWidgetKind.RING
        val width = intent.getIntExtra("width", 380).coerceIn(110, 400)
        val height = intent.getIntExtra("height", 180).coerceIn(110, 500)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(12.dp(), 40.dp(), 12.dp(), 16.dp())
            setBackgroundColor(0xffd9dce3.toInt())
        }
        root.addView(TextView(this).apply {
            text = "Native widget QA · ${kind.name} · $width × $height dp\nIsolated test data · production RemoteViews"
            gravity = Gravity.CENTER
            setTextColor(0xff202124.toInt())
            textSize = 16f
            setPadding(0, 8.dp(), 0, 20.dp())
        })
        setContentView(root)
        val manager = AppWidgetManager.getInstance(this)
        widgetId = host.allocateAppWidgetId()
        val component = ComponentName(this, kind.receiver)
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
            putInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, 1)
            if (android.os.Build.VERSION.SDK_INT >= 31) putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf(SizeF(width.toFloat(), height.toFloat())))
        }
        if (!manager.bindAppWidgetIdIfAllowed(widgetId, component, options)) {
            root.addView(TextView(this).apply { text = "QA widget binding is not authorized." })
            return
        }
        val view = host.createView(this, widgetId, manager.getAppWidgetInfo(widgetId))
        view.setPadding(0, 0, 0, 0)
        root.addView(view, LinearLayout.LayoutParams(width.dp(), height.dp()))
        view.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
            val origin = IntArray(2)
            v.getLocationOnScreen(origin)
            java.io.File(cacheDir, "widget-host-bounds.txt").writeText("${origin[0]},${origin[1]},${v.width},${v.height}")
        }
        manager.updateAppWidgetOptions(widgetId, options)
        root.addView(Button(this).apply {
            text = "Add this test widget to Home"
            setOnClickListener { kind.pin(this@WidgetHostGalleryActivity) }
        })
        lifecycleScope.launch {
            val graph = (application as DoneAtApplication).graph
            graph.loaded.first { it }
            graph.widgets.refresh()
            sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(component)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId)))
        }
    }
    override fun onStart() { super.onStart(); if (::host.isInitialized) host.startListening() }
    override fun onStop() { if (::host.isInitialized) host.stopListening(); super.onStop() }
    override fun onDestroy() {
        if (::host.isInitialized && widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) host.deleteAppWidgetId(widgetId)
        super.onDestroy()
    }
    private fun Int.dp() = (this * resources.displayMetrics.density).toInt()
}
