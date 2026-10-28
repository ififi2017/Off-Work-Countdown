package com.rainif.doneat.widget

import android.content.Context
import android.widget.Toast
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.focus.FocusStep
import com.rainif.doneat.core.domain.focus.Planned
import com.rainif.doneat.core.domain.records.FocusEndReason
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/** Glance's internal callback, not an exported intent that could mutate a session from another app. */
class WidgetFocusActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val graph = (context.applicationContext as DoneAtApplication).graph
        graph.loaded.first { it }
        val action = parameters[ACTION]
        val start = parameters[START]
        val changed = when (action) {
            "stop" -> graph.focus.step { state, next, engine ->
                val now = graph.nowMs()
                if (widgetFocusActionAllowed(graph.plus.isAuthorizedNow(), action, start, engine.activeSession(state), now)) {
                    engine.stop(state, FocusEndReason.STOPPED_BY_USER, now)
                } else FocusStep(state, next, ok = false)
            }
            "add" -> graph.focus.plan { state, planning ->
                val now = graph.nowMs()
                val current = graph.focus.engine(state).activeSession(state)
                val taskID = current?.taskID
                if (widgetFocusActionAllowed(graph.plus.isAuthorizedNow(), action, start, current, now) && taskID != null) {
                    val result = planning.addOneBlock(state, taskID, now)
                    Planned(result.state, result.value.isSuccess)
                } else Planned(state, false)
            } ?: false
            else -> false
        }
        graph.widgets.refresh()
        if (!changed && action == "add") withContext(Dispatchers.Main) {
            val localized = widgetLocalizedContext(context, WidgetSuiteCoordinator.read(context)?.locale)
            Toast.makeText(localized, localized.getString(R.string.focusExtendNoRoom), Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        val ACTION = ActionParameters.Key<String>("widgetFocusAction")
        val START = ActionParameters.Key<Long>("widgetFocusStart")
    }
}
