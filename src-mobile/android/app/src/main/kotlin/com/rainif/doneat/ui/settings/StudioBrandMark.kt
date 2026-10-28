package com.rainif.doneat.ui.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import kotlinx.coroutines.delay

/** Exact outlined iOS studio artwork. Its fixed brand colours are not app accent colours. */
@Composable
fun StudioBrandMark() {
    val context = LocalContext.current
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val reduced = LocalDoneAtMotion.current.reduced
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    var lit by remember { mutableStateOf(true) }
    LaunchedEffect(reduced, lifecycle) {
        lit = true
        if (!reduced && lifecycle.isAtLeast(Lifecycle.State.RESUMED)) {
            while (true) { delay(550); lit = !lit }
        }
    }
    val height = with(LocalDensity.current) { MaterialTheme.typography.bodyMedium.fontSize.toDp() }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        TextButton(onClick = { openUrl(context, "https://finiar.app") }) {
            Box(Modifier.height(height).aspectRatio(9950f / 1053f)) {
                Image(painterResource(if (dark) R.drawable.studio_mark_dark else R.drawable.studio_mark_light), "fi_niaR Studio", Modifier.fillMaxSize())
                Canvas(Modifier.fillMaxSize()) {
                    if (lit) drawRect(
                        color = (if (dark) Color(0xFF7AA7FF) else Color(0xFF2F6FDB)).copy(alpha = 0.85f),
                        topLeft = Offset(size.width * 0.9447f, 0f),
                        size = Size(size.width * 0.0553f, size.height * 0.902f),
                    )
                }
            }
        }
    }
}
