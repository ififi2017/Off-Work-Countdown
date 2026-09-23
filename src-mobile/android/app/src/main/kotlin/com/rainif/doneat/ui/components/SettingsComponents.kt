package com.rainif.doneat.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtSpacing

/**
 * A settings-style page: an optional back arrow, a large title, then grouped
 * content that scrolls. The back arrow is named after the page it returns to,
 * as iOS names its back button.
 */
@Composable
fun DoneAtPage(
    title: String,
    onBack: (() -> Unit)? = null,
    backLabel: String? = null,
    actions: @Composable () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        // A readable measure on wide windows: centred, not stretched edge to edge.
        Column(
            Modifier
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(bottom = DoneAtSpacing.xl)
                .wrapContentWidth(Alignment.CenterHorizontally)
                .widthIn(max = 720.dp),
        ) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onBack != null) {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = backLabel)
                    }
                }
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) { actions() }
            }
            Text(
                title,
                modifier = Modifier.padding(horizontal = DoneAtSpacing.page).padding(bottom = DoneAtSpacing.s).semantics { heading() },
                style = MaterialTheme.typography.headlineMedium,
            )
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l), content = content)
        }
    }
}

/** A titled group of rows on one tonal surface; rows are divided, the group is not outlined. */
@Composable
fun SettingsGroup(title: String? = null, footer: String? = null, rows: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = DoneAtSpacing.page)) {
        if (title != null) {
            Text(
                title,
                modifier = Modifier.padding(start = DoneAtSpacing.l, bottom = DoneAtSpacing.s).semantics { heading() },
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(content = rows)
        }
        if (footer != null) SettingsFooter(footer)
    }
}

/** A note under the whole page rather than one group, aligned with the groups' text. */
@Composable
fun PageFooter(text: String) {
    Column(Modifier.padding(horizontal = DoneAtSpacing.page)) { SettingsFooter(text) }
}

@Composable
fun SettingsFooter(text: String) {
    Text(
        text,
        modifier = Modifier.padding(start = DoneAtSpacing.l, end = DoneAtSpacing.l, top = DoneAtSpacing.s),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** A divider inset past the icon column, drawn between rows, never after the last. */
@Composable
fun RowDivider(inset: Boolean = true) {
    HorizontalDivider(Modifier.padding(start = if (inset) 56.dp else DoneAtSpacing.l), color = MaterialTheme.colorScheme.outlineVariant)
}

private val transparent
    @Composable get() = ListItemDefaults.colors(containerColor = Color.Transparent)

/** A row that opens a page: icon, title, the current value, and a chevron. */
@Composable
fun NavigationRow(title: String, onClick: () -> Unit, icon: ImageVector? = null, value: String? = null, supporting: String? = null) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = supporting?.let { { Text(it) } },
        leadingContent = icon?.let { { Icon(it, contentDescription = null, modifier = Modifier.size(24.dp)) } },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                if (value != null) Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        colors = transparent,
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick),
    )
}

/** A row that performs an action, such as opening a link; [trailing] says where it goes. */
@Composable
fun ActionRow(title: String, onClick: () -> Unit, icon: ImageVector? = null, trailing: ImageVector? = null) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = icon?.let { { Icon(it, contentDescription = null) } },
        trailingContent = trailing?.let { { Icon(it, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } },
        colors = transparent,
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick),
    )
}

/** One choice among several; the chosen row shows a check (iOS checkmark rows). */
@Composable
fun ChoiceRow(title: String, selected: Boolean, onSelect: () -> Unit, icon: ImageVector? = null, supporting: String? = null) {
    val check: (@Composable () -> Unit)? = if (selected) {
        { Icon(Icons.Outlined.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
    } else {
        null
    }
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = supporting?.let { { Text(it) } },
        leadingContent = icon?.let { { Icon(it, contentDescription = null) } },
        trailingContent = check,
        colors = transparent,
        modifier = Modifier.selectable(selected = selected, role = Role.RadioButton, onClick = onSelect),
    )
}

/** A switch the whole row toggles, so the target is the row, not only the switch. */
@Composable
fun SwitchRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, supporting: String? = null, enabled: Boolean = true, badge: String? = null) {
    val secondLine: (@Composable () -> Unit)? = when {
        badge != null -> { { Text(badge, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium) } }
        supporting != null -> { { Text(supporting) } }
        else -> null
    }
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = secondLine,
        trailingContent = { Switch(checked = checked, onCheckedChange = null, enabled = enabled) },
        colors = transparent,
        modifier = Modifier.toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange),
    )
}

/** A label and a value that is shown, not edited. */
@Composable
fun ValueRow(title: String, value: String, valueColor: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = { Text(value, style = MaterialTheme.typography.bodyMedium, color = valueColor) },
        colors = transparent,
    )
}
