package com.rainif.doneat.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.session.ShareContent
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.timer.Haptics
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.NumberFormat

/** The sentence a share carries (iOS `shareCopy`). */
fun shareMessage(content: ShareContent, text: TimerText, res: android.content.res.Resources): String = when (content.message) {
    ShareContent.Message.OFF_WORK -> res.getString(R.string.shareOffWorkText)
    ShareContent.Message.LUNCH -> Strings.shareLunchText(res, text.relativeDuration(content.messageRemainingMs))
    ShareContent.Message.UNTIL_START -> Strings.shareUntilStartText(res, text.relativeDuration(content.messageRemainingMs))
    ShareContent.Message.COUNTDOWN -> Strings.shareText(res, text.relativeDuration(content.messageRemainingMs))
}

private fun cardModel(session: ShiftSession, mood: ShareMood, nowMs: Double, text: TimerText, res: android.content.res.Resources): ShareCardModel {
    val content = ShareContent.of(session, nowMs)
    val percent = NumberFormat.getPercentInstance(text.locale).apply {
        minimumFractionDigits = 1
        maximumFractionDigits = 1
    }.format(content.progress / 100)
    return ShareCardModel(
        mood = mood,
        hero = if (content.isDone) res.getString(R.string.shareDone) else text.relativeDuration(content.heroRemainingMs),
        message = shareMessage(content, text, res),
        progress = content.progress,
        percent = percent,
    )
}

/**
 * Hands the card and one line of text (the sentence and the link) to the
 * system share sheet. The picture is written to the app's cache and lent
 * through a FileProvider for this share only; nothing else is exposed.
 */
private suspend fun share(context: Context, bitmap: Bitmap, text: String) {
    val file = withContext(Dispatchers.IO) {
        File(context.cacheDir, "share").apply { mkdirs() }.resolve("doneat.png").also { out ->
            out.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "image/png"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TEXT, text)
        putExtra(Intent.EXTRA_TITLE, "DoneAt")
        // The sheet's own preview reads the image from here.
        clipData = ClipData.newUri(context.contentResolver, "DoneAt", uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, null))
}

/**
 * The share composer (iOS `ShareComposerView`): a mood, the card as it will be
 * sent, and the system share sheet. Narrow windows stack them; wide ones put
 * the card beside the controls, with what the share carries spelled out.
 */
@Composable
fun ShareScreen(graph: AppGraph, onBack: () -> Unit) {
    val context = LocalContext.current
    val res = LocalResources.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val state by graph.sessions.session.collectAsStateWithLifecycle()
    var moodCode by rememberSaveable { mutableStateOf(ShareMood.HAPPY.code) }
    val mood = ShareMood.entries.first { it.code == moodCode }
    var now by remember { mutableDoubleStateOf(graph.nowMs()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000 - (now % 60_000).toLong())
            now = graph.nowMs()
        }
    }
    val text = TimerText(res, androidx.compose.ui.platform.LocalConfiguration.current.locales[0], android.text.format.DateFormat.is24HourFormat(context), hideEarnings = true)
    val model = cardModel(state, mood, now, text, res)
    val bitmap by produceState<Bitmap?>(null, model) {
        value = withContext(Dispatchers.Default) { ShareCard.render(context, model) }
    }
    val shareText = "${model.message} ${ShareContent.url(state.env.preferences.startMinutes, state.env.preferences.endMinutes)}"

    fun send() {
        val image = bitmap ?: return
        Haptics.confirm(view)
        scope.launch { share(context, image, shareText) }
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.timerTab)) }
                Text(stringResource(R.string.shareButton), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
            }
            BoxWithConstraints(Modifier.fillMaxSize()) {
                // Landscape phones and tablets: the card beside the controls, as two deliberate columns.
                val wide = maxWidth >= 520.dp && maxWidth > maxHeight
                if (wide) {
                    // Room for the full explanation, or just the sentence (iOS `ViewThatFits`).
                    val roomy = maxHeight >= 420.dp
                    Row(
                        Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Preview(bitmap, model, Modifier.widthIn(max = 360.dp).weight(1f, fill = false))
                        Column(
                            Modifier.widthIn(max = 390.dp).weight(1f).verticalScroll(rememberScrollState()),
                            verticalArrangement = Arrangement.spacedBy(if (roomy) 16.dp else 10.dp),
                        ) {
                            Text(
                                stringResource(R.string.shareMoodLabel),
                                style = if (roomy) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            MoodPicker(mood) { moodCode = it.code; view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK) }
                            if (roomy) {
                                Details(model.message)
                            } else {
                                Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
                                    Text(
                                        model.message, Modifier.fillMaxWidth().padding(12.dp),
                                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2,
                                    )
                                }
                            }
                            ShareButton(enabled = bitmap != null, onClick = ::send)
                        }
                    }
                } else {
                    Column(
                        Modifier.fillMaxSize().padding(start = DoneAtSpacing.page, end = DoneAtSpacing.page, top = 6.dp, bottom = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        MoodPicker(mood) { moodCode = it.code; view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK) }
                        // The card takes whatever the picker and the button leave, never more than it can fit.
                        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Preview(bitmap, model, Modifier)
                        }
                        ShareButton(enabled = bitmap != null, onClick = ::send)
                    }
                }
            }
        }
    }
}

@Composable
private fun Preview(bitmap: Bitmap?, model: ShareCardModel, modifier: Modifier) {
    val shape = RoundedCornerShape(24.dp)
    Box(
        modifier
            .aspectRatio(ShareCard.WIDTH / ShareCard.HEIGHT, matchHeightConstraintsFirst = true)
            .shadow(14.dp, shape, clip = false)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .semantics { contentDescription = "${model.hero}. ${model.message}" },
    ) {
        bitmap?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize()) }
    }
}

@Composable
private fun MoodPicker(selected: ShareMood, onSelect: (ShareMood) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val res = LocalResources.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        // One row when it fits, otherwise two rows of four.
        val rows = if (maxWidth >= (38 * ShareMood.entries.size).dp) listOf(ShareMood.entries) else ShareMood.entries.chunked(4)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            rows.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { mood ->
                        val isSelected = mood == selected
                        Box(
                            Modifier
                                .size(44.dp)
                                .clip(CircleShape)
                                .background(if (isSelected) scheme.surfaceContainerHighest else androidx.compose.ui.graphics.Color.Transparent)
                                .then(if (isSelected) Modifier.border(1.5.dp, scheme.primary, CircleShape) else Modifier)
                                .clickable(role = Role.RadioButton) { onSelect(mood) }
                                .semantics {
                                    contentDescription = res.getString(mood.label)
                                    this.selected = isSelected
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            // A fixed size: the emoji is a picture here, and grows with nothing.
                            Text(mood.emoji, Modifier.graphicsLayer { alpha = if (isSelected) 1f else 0.74f }, fontSize = with(androidx.compose.ui.platform.LocalDensity.current) { 26.dp.toSp() })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Details(message: String) {
    val scheme = MaterialTheme.colorScheme
    Surface(shape = RoundedCornerShape(18.dp), color = scheme.surfaceContainerLow) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DetailRow(Icons.Outlined.FormatQuote, message, emphasized = true)
            HorizontalDivider(color = scheme.outlineVariant)
            DetailRow(Icons.Outlined.Share, stringResource(R.string.shareComposerNote))
            DetailRow(Icons.Outlined.Lock, stringResource(R.string.sharePrivacyNote))
        }
    }
}

@Composable
private fun DetailRow(icon: ImageVector, text: String, emphasized: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    Row(horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Icon(icon, null, Modifier.size(18.dp), tint = if (emphasized) scheme.primary else scheme.onSurfaceVariant)
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (emphasized) FontWeight.Medium else FontWeight.Normal,
            color = if (emphasized) scheme.onSurface else scheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ShareButton(enabled: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = MaterialTheme.shapes.medium) {
        Icon(Icons.Outlined.Share, null, Modifier.size(18.dp))
        Text(stringResource(R.string.shareNative), Modifier.padding(start = 8.dp))
    }
}
