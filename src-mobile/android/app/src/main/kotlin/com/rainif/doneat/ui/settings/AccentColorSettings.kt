package com.rainif.doneat.ui.settings

import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtAccent
import com.rainif.doneat.core.designsystem.DoneAtColors
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.ui.components.ChoiceRow
import com.rainif.doneat.ui.components.NavigationRow
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup

@Composable
fun AccentColorSettings(accent: Int?, dynamic: Boolean, onSelect: (Int?) -> Unit) {
    var picking by rememberSaveable { mutableStateOf(false) }
    val labels = listOf(R.string.accentRed, R.string.accentYellow, R.string.accentGreen, R.string.accentTeal,
        R.string.accentBlue, R.string.accentIndigo, R.string.accentPurple, R.string.accentPink)
    SettingsGroup(title = stringResource(R.string.accentColor), footer = stringResource(R.string.accentColorFooter)) {
        ChoiceRow(stringResource(R.string.accentDoneAt), accent == null && !dynamic, { onSelect(null) })
        RowDivider(inset = false)
        Column(Modifier.padding(DoneAtSpacing.l).selectableGroup(), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            DoneAtAccent.presets.chunked(4).forEachIndexed { row, colors ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    colors.forEachIndexed { column, rgb ->
                        val selected = accent == rgb && !dynamic
                        val description = stringResource(labels[row * 4 + column])
                        val color = DoneAtAccent.color(rgb)
                        Box(Modifier.size(DoneAtSpacing.minTouch)
                            .selectable(selected = selected, role = Role.RadioButton, onClick = { onSelect(rgb) })
                            .semantics { contentDescription = description }, contentAlignment = Alignment.Center) {
                            Box(Modifier.size(32.dp).background(color, CircleShape)
                                .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape), contentAlignment = Alignment.Center) {
                                if (selected) Icon(Icons.Outlined.Check, contentDescription = null,
                                    tint = DoneAtAccent.foreground(color), modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            }
        }
        RowDivider(inset = false)
        NavigationRow(stringResource(R.string.accentCustom), { picking = true }, Icons.Outlined.Palette,
            value = accent?.let(DoneAtAccent::hex))
    }
    if (picking) AccentColorDialog(accent ?: (DoneAtColors.brand.toArgb() and 0xFFFFFF),
        onDismiss = { picking = false }, onSave = { onSelect(it); picking = false })
}

/** Edits a draft; dismissal never writes settings or replaces the wallpaper choice. */
@Composable
private fun AccentColorDialog(initial: Int, onDismiss: () -> Unit, onSave: (Int) -> Unit) {
    val hsv = remember(initial) { FloatArray(3).also { AndroidColor.colorToHSV(DoneAtAccent.color(initial).toArgb(), it) } }
    var hue by rememberSaveable(initial) { mutableFloatStateOf(hsv[0]) }
    var saturation by rememberSaveable(initial) { mutableFloatStateOf(hsv[1]) }
    var brightness by rememberSaveable(initial) { mutableFloatStateOf(hsv[2]) }
    var hex by rememberSaveable(initial) { mutableStateOf(DoneAtAccent.hex(initial)) }
    val parsed = DoneAtAccent.parseHex(hex)
    val candidate = parsed ?: (AndroidColor.HSVToColor(floatArrayOf(hue, saturation, brightness)) and 0xFFFFFF)
    fun updateHex() { hex = DoneAtAccent.hex(AndroidColor.HSVToColor(floatArrayOf(hue, saturation, brightness))) }
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.accentCustom)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    Box(Modifier.size(DoneAtSpacing.minTouch).background(DoneAtAccent.color(candidate), CircleShape)
                        .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
                    Text(DoneAtAccent.hex(candidate), style = MaterialTheme.typography.titleMedium.copy(textDirection = TextDirection.Ltr))
                }
                AccentSlider(stringResource(R.string.accentHue), hue, 0f..360f) { hue = it; updateHex() }
                AccentSlider(stringResource(R.string.accentSaturation), saturation, 0f..1f) { saturation = it; updateHex() }
                AccentSlider(stringResource(R.string.accentBrightness), brightness, 0f..1f) { brightness = it; updateHex() }
                OutlinedTextField(value = hex, onValueChange = { typed ->
                    if (typed.length <= 9) {
                        hex = typed
                        DoneAtAccent.parseHex(typed)?.let { rgb ->
                            val next = FloatArray(3)
                            AndroidColor.colorToHSV(DoneAtAccent.color(rgb).toArgb(), next)
                            // Achromatic colours have no hue: retain it for the next saturation change.
                            if (next[1] > 0f) hue = next[0]
                            saturation = next[1]
                            brightness = next[2]
                        }
                    }
                }, label = { Text(stringResource(R.string.accentHex)) }, singleLine = true,
                    isError = parsed == null,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(textDirection = TextDirection.Ltr),
                    supportingText = { Text(if (parsed == null) stringResource(R.string.accentHexError) else "#RRGGBB",
                        style = LocalTextStyle.current.copy(textDirection = if (parsed == null) TextDirection.Content else TextDirection.Ltr)) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false,
                        // Some IMEs compose pinyin even for Ascii. Request direct Latin keys;
                        // no PasswordVisualTransformation is used, so the HEX value stays visible.
                        keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { parsed?.let(onSave) }),
                    modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton(onClick = { parsed?.let(onSave) }, enabled = parsed != null) { Text(stringResource(R.string.saveAction)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun AccentSlider(label: String, value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit) {
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Slider(value = value, onValueChange = onChange, valueRange = range,
            modifier = Modifier.semantics { contentDescription = label })
    }
}
