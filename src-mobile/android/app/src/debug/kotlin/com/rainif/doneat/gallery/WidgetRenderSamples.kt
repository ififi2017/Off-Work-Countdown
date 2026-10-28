package com.rainif.doneat.gallery

import android.content.Context
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.util.Locale

/** Synthetic visual fixtures only. Never passed to app stores, entitlement stores or the launcher. */
internal object WidgetRenderSamples {
    val now = Instant.parse("2026-10-22T15:18:52Z").toEpochMilli()
    private fun at(day: String, hour: Int = 0) = LocalDate.parse(day).atTime(hour, 0).toInstant(ZoneOffset.UTC).toEpochMilli()
    fun make(context: Context, locked: Boolean): Pair<WidgetSuiteSnapshot, WidgetSnapshot> {
        val res = context.resources
        val locale = res.configuration.locales[0]
        val access = if (locked) WidgetAccess.LOCKED else WidgetAccess(true)
        val days = (0L..60L).map { i ->
            val d = LocalDate.of(2026, 10, 1).plusDays(i)
            val work = d.dayOfWeek.value < 6
            WidgetCalendarDay(d.toString(), at(d.toString()), if (work) WidgetCalendarDayKind.WORK else WidgetCalendarDayKind.REST,
                res.getString(if (work) R.string.widgetSuiteWork else R.string.widgetSuiteRest),
                if (work) "#F47A32" else null,
                if (work) listOf(WidgetTimeSegment(at(d.toString(),9),at(d.toString(),12)), WidgetTimeSegment(at(d.toString(),13),at(d.toString(),18))) else emptyList())
        }
        val todaySegments = days.first { it.dayKey == "2026-10-22" }.segments
        fun hours(n: Double) = (n * 3_600_000).toLong()
        val periods = WidgetSummaryPeriodKind.entries.map { kind ->
            val weekly = kind == WidgetSummaryPeriodKind.WEEK
            val yearly = kind == WidgetSummaryPeriodKind.YEAR
            val values = if (yearly) listOf(120.0,102.0,143.0,141.0,130.0,139.0,148.0,144.0,132.0,99.0,0.0,0.0)
                else if (weekly) listOf(8.0,8.4,8.0,5.2,0.0,0.0,0.0) else List(31) { if (it < 21 && it % 7 < 5) 8.0 else 0.0 }
            WidgetSummaryPeriod(kind, res.getString(when(kind) { WidgetSummaryPeriodKind.WEEK -> R.string.widgetSuiteThisWeek; WidgetSummaryPeriodKind.MONTH -> R.string.widgetSuiteThisMonth; WidgetSummaryPeriodKind.YEAR -> R.string.widgetSuiteThisYear }),
                null, if (yearly) "2026-01-01" else if (weekly) "2026-10-19" else "2026-10-01", if (yearly) "2026-12-31" else if (weekly) "2026-10-25" else "2026-10-31",
                hours(if (yearly) 1590.0 else if (weekly) 31.6 else 118.5),hours(if (yearly) 74.0 else 6.5),
                if (yearly) 198 else if (weekly) 4 else 14,if (yearly) 250 else if (weekly) 5 else 21,if (yearly) 52 else if (weekly) 1 else 7,.67,
                values.mapIndexed { i, v -> WidgetSummaryBar(if (weekly) java.time.DayOfWeek.of(i+1).getDisplayName(TextStyle.NARROW,locale) else (i+1).toString(), hours(v),if ((yearly && i==9)||(weekly && i==3)) WidgetSummaryBarState.CURRENT else if(v==0.0) WidgetSummaryBarState.FUTURE else WidgetSummaryBarState.PAST) })
        }
        val leaveDays = (0L..10L).map { i -> WidgetLeaveDay(LocalDate.of(2027,2,6).plusDays(i).toString(), if(i<2) WidgetLeaveDayKind.REST else if(i>8) WidgetLeaveDayKind.LEAVE else WidgetLeaveDayKind.HOLIDAY) }
        val suite = WidgetSuiteSnapshot(generatedAtMs=now,locale=locale.toLanguageTag(),timeZoneIdentifier="UTC",
            calendar=WidgetCalendarPayload("UTC",1,WidgetCalendarScheduleKind.WEEKLY,days),
            summary=WidgetSummaryPayload(access,periods,todaySegments),
            life=WidgetLifePayload(access,LocalDate.of(1995,5,22).toEpochDay(),false,LocalDate.of(2017,5,22).toEpochDay(),LocalDate.of(2055,5,22).toEpochDay(),80),
            holiday=WidgetHolidayPayload(access,at("2026-10-23",18),WidgetHoliday(if(locale.language=="zh") "元旦" else "New Year", "2027-01-01",at("2027-01-01"),"2027-01-03",3,false),
                WidgetLeave("2027-02-06",at("2027-02-06"),2.0,11,leaveDays),5.0,
                labels=mapOf("requested" to res.getString(R.string.widgetSuiteLeavePlan,
                    res.getString(R.string.widgetSuiteDaysCount,"2"),res.getString(R.string.widgetSuiteDaysCount,"11")),
                    "remaining" to res.getString(R.string.widgetSuiteLeaveRemaining,res.getString(R.string.widgetSuiteDaysCount,"5")))),
            focus=WidgetFocusPayload(access,listOf(WidgetFocusBlock(res.getString(R.string.focusDemoWriting),startMs=now-7*60_000,endMs=now+18*60_000+24_000,round=2,rounds=4,isRunning=true),
                WidgetFocusBlock(res.getString(R.string.focusDemoLearning),startMs=now+23*60_000,endMs=now+48*60_000,round=3,rounds=4))),
            countdownSegments=todaySegments)
        val end=at("2026-10-22",18)
        val countdown=WidgetSnapshot(1,now,end,locale.toLanguageTag(),listOf(WidgetEntry(now,end,WidgetPhase.WORKING,"widgetWorking",WidgetCountdownKind.WORK_REMAINING,end-now,end,end-now,66.0,end)),
            listOf(WidgetUpcomingItem("qa-focus","focus",res.getString(R.string.focusDemoWriting),res.getString(R.string.focusTitle),now+41*60_000),WidgetUpcomingItem("qa-end","end",res.getString(R.string.endTime),"",end)))
        return suite.redacted(now) to countdown
    }
}
