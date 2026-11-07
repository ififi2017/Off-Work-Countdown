package com.rainif.doneat.ui.timer

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.schedule.OvertimePay
import com.rainif.doneat.core.domain.session.OvertimePayChoices
import com.rainif.doneat.ui.components.RowDivider
import java.text.NumberFormat
import java.util.Locale

/** "1.5×", with the locale's decimal separator (iOS `AppText.multiplierLabel`). */
fun multiplierLabel(multiplier: Double, locale: Locale): String = "${decimal(multiplier, locale)}×"

/** A number with at most one decimal, as iOS `formatDecimal`. */
fun decimal(value: Double, locale: Locale): String =
    NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 1
    }.format(value)

/**
 * How one overtime is paid while it is being chosen (iOS `OvertimePayCard`'s
 * three bindings): paid or not, at what multiple, and whether the stepper for
 * a custom multiple is showing.
 */
data class OvertimePayDraft(val isPaid: Boolean, val multiplier: Double, val showsCustom: Boolean) {
    /** What is saved: 0 for unpaid, otherwise the normalised multiple. */
    val payMultiplier: Double get() = if (isPaid) OvertimePay.normalized(multiplier) else 0.0

    companion object {
        /**
         * The draft for a saved [current] multiplier: unpaid shows [preferred]
         * (or 1) as the multiple it would return to.
         */
        fun of(current: Double, preferred: Double): OvertimePayDraft {
            val paid = current > 0
            val shown = if (paid) current else if (preferred > 0) preferred else 1.0
            return OvertimePayDraft(paid, shown, paid && !OvertimePayChoices.isPreset(shown))
        }
    }
}

/**
 * This overtime's pay: paid or not, and at what multiple of the usual rate.
 * The overtime sheet and the Records day editor share it.
 */
@Composable
fun OvertimePayCard(
    draft: OvertimePayDraft,
    locale: Locale,
    onChange: (OvertimePayDraft) -> Unit,
    modifier: Modifier = Modifier,
    // Pages use the grouped-row tone; a dialog passes one that stands apart from its own surface.
    containerColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.surfaceContainerLow,
) {
    Surface(shape = MaterialTheme.shapes.large, color = containerColor, modifier = modifier.fillMaxWidth()) {
        Column {
            val choice: @Composable (Modifier) -> Unit = { segmentModifier ->
                SingleChoiceSegmentedButtonRow(segmentModifier) {
                    listOf(true to R.string.overtimePayPaid, false to R.string.overtimePayUnpaid).forEachIndexed { index, (paid, label) ->
                        SegmentedButton(
                            selected = draft.isPaid == paid,
                            onClick = { onChange(draft.copy(isPaid = paid, showsCustom = paid && !OvertimePayChoices.isPreset(draft.multiplier))) },
                            shape = SegmentedButtonDefaults.itemShape(index, 2),
                        ) { Text(stringResource(label), maxLines = 1) }
                    }
                }
            }
            // In a dialog the title and the choice do not both fit; the choice then goes under
            // the title rather than breaking a word in it.
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                if (maxWidth < 360.dp || LocalDensity.current.fontScale >= 1.3f) {
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m),
                        verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s),
                    ) {
                        Text(stringResource(R.string.overtimePayRow), style = MaterialTheme.typography.bodyLarge)
                        choice(Modifier.fillMaxWidth())
                    }
                } else {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.overtimePayRow), Modifier.weight(1f).padding(end = DoneAtSpacing.m), style = MaterialTheme.typography.bodyLarge)
                        choice(Modifier.widthIn(max = 220.dp))
                    }
                }
            }
            if (draft.isPaid) {
                RowDivider(inset = false)
                MenuRow(
                    title = stringResource(R.string.overtimeMultiplierRow),
                    value = multiplierLabel(draft.multiplier, locale),
                    options = OvertimePayChoices.presets.map { multiplierLabel(it, locale) } + stringResource(R.string.overtimeMultiplierCustom),
                    selected = if (draft.showsCustom) OvertimePayChoices.presets.size else OvertimePayChoices.presets.indexOf(draft.multiplier),
                ) { index ->
                    onChange(
                        if (index == OvertimePayChoices.presets.size) draft.copy(showsCustom = true)
                        else draft.copy(showsCustom = false, multiplier = OvertimePayChoices.presets[index]),
                    )
                }
                if (draft.showsCustom) {
                    RowDivider(inset = false)
                    MultiplierStepperRow(draft.multiplier, locale) { onChange(draft.copy(multiplier = it)) }
                }
            }
        }
    }
}

/** A row whose trailing control steps a multiplier between 0.5× and 5× in 0.1s. */
@Composable
fun MultiplierStepperRow(multiplier: Double, locale: Locale, onChange: (Double) -> Unit) {
    val tenths = OvertimePayChoices.tenths(multiplier)
    StepperRow(
        title = stringResource(R.string.overtimeMultiplierRow),
        value = multiplierLabel(multiplier, locale),
        canDecrement = tenths > OvertimePayChoices.customTenths.first,
        canIncrement = tenths < OvertimePayChoices.customTenths.last,
        onDecrement = { onChange(OvertimePayChoices.multiplier(tenths - 1)) },
        onIncrement = { onChange(OvertimePayChoices.multiplier(tenths + 1)) },
    )
}

/** A title, the current value and a pair of − / + buttons (iOS `Stepper`). */
@Composable
fun StepperRow(
    title: String,
    value: String,
    canDecrement: Boolean,
    canIncrement: Boolean,
    onDecrement: () -> Unit,
    onIncrement: () -> Unit,
    supporting: String? = null,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs)
            .semantics(mergeDescendants = false) { contentDescription = title; stateDescription = value },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(vertical = DoneAtSpacing.s)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (supporting != null) Text(supporting, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            value,
            Modifier.padding(horizontal = DoneAtSpacing.s),
            style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        IconButton(onClick = onDecrement, enabled = canDecrement) { Icon(Icons.Outlined.Remove, "−") }
        IconButton(onClick = onIncrement, enabled = canIncrement) { Icon(Icons.Outlined.Add, "+") }
    }
}

/** A row that opens a short menu of choices, showing the current one (iOS `owcRowMenu`). */
@Composable
fun MenuRow(title: String, value: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.DropdownList) { open = true }
                .padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
        ) {
            Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Text(value, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.Outlined.UnfoldMore, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(open, { open = false }, Modifier.align(Alignment.TopEnd)) {
            options.forEachIndexed { index, option ->
                DropdownMenuItem(
                    text = { Text(option, color = if (index == selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface) },
                    onClick = {
                        open = false
                        onSelect(index)
                    },
                )
            }
        }
    }
}
