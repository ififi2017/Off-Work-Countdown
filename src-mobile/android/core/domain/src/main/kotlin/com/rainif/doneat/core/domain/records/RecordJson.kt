package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.FoundationCompat.canonicalDayKey
import com.rainif.doneat.core.domain.records.FoundationCompat.uuid
import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Locale
import java.util.UUID

/**
 * The records backup document (schema 6, reading 1–6): the Kotlin port of iOS
 * `RecordJSON`, held to its answers by `record-json-fixtures.json`.
 *
 * Two layers, as in Swift: [decode] is strict like `Codable` — a missing key,
 * a wrong type or an unknown enum value rejects the whole document — while
 * [apply] rejects individual rows whose values do not hold together. Unknown
 * keys are ignored, so an injected `purchaseToken` or `isPlus` never reaches
 * the archive, and entitlements never come from a backup.
 */
object RecordJson {
    const val SCHEMA_VERSION = 6
    val ACCEPTED_SCHEMA_VERSIONS = 1..6

    sealed class Error(message: String) : Exception(message) {
        class UnknownSchemaVersion(val version: Int) : Error("unknown schema version $version")
        class InvalidDocument(reason: String) : Error("invalid document: $reason")
    }

    enum class ImportMode {
        /** Skip erased identities; same-key conflicts keep the local row and report the incoming one. */
        SKIP_ERASED,
        /** Write erased rows back: UUID identities get a new id, natural keys keep theirs. */
        RESTORE_ERASED,
        /** Same-key conflicts pick `(editCount, editTieBreaker)`; wall clock never decides. */
        RESOLVE_BY_EDIT_STAMP,
        /** Explicit user choice in the local conflict center. */
        FORCE_INCOMING,
    }

    data class Rejection(val entityType: RecordEntityType, val logicalKey: String)
    data class Conflict(val entityType: RecordEntityType, val logicalKey: String, val incoming: Any, val localEditCount: Int, val incomingEditCount: Int, val appliedIncoming: Boolean)
    data class Adoption(val entityType: RecordEntityType, val logicalKey: String, val editCount: Int, val editTieBreaker: String)

    class Report {
        val inserted = LinkedHashMap<RecordEntityType, Int>()
        val unchanged = LinkedHashMap<RecordEntityType, Int>()
        val skippedErased = LinkedHashMap<RecordEntityType, Int>()
        val restored = LinkedHashMap<RecordEntityType, Int>()
        val rejected = ArrayList<Rejection>()
        val conflicts = ArrayList<Conflict>()
        val adopted = ArrayList<Adoption>()
    }

    /** A decoded document: rows are still raw objects until [apply] converts them. */
    class Document internal constructor(internal val root: JsonObject, val schemaVersion: Int) {
        val exportedAtMs: Double get() = root.num("exportedAtMs")
        val timeZoneIdentifier: String get() = root.str("timeZoneIdentifier")
        val calendarIdentifier: String get() = root.str("calendarIdentifier")
    }

    // Decoding

    fun decode(text: String): Document {
        val root = try {
            Json.parseToJsonElement(text) as? JsonObject ?: throw Error.InvalidDocument("not an object")
        } catch (e: Error) {
            throw e
        } catch (e: Exception) {
            throw Error.InvalidDocument("not JSON")
        }
        val version = try {
            validateDocument(root)
            root.int("schemaVersion")
        } catch (e: Error) {
            throw e
        } catch (e: Exception) {
            throw Error.InvalidDocument(e.message ?: "malformed")
        }
        if (version !in ACCEPTED_SCHEMA_VERSIONS) throw Error.UnknownSchemaVersion(version)
        return Document(root, version)
    }

    /** Everything `JSONDecoder` checks before a single row is looked at. */
    private fun validateDocument(o: JsonObject) {
        o.int("schemaVersion"); o.num("exportedAtMs"); o.str("timeZoneIdentifier"); o.str("calendarIdentifier")
        o.arr("careerPeriods").forEach { it.obj().apply {
            str("id"); str("startsOn"); optStr("endsBefore"); optStr("label"); optStr("timeZoneIdentifier"); optStr("calendarIdentifier")
            num("createdAtMs"); num("editedAtMs"); int("editCount"); str("editTieBreaker")
        } }
        o.arr("scheduleSnapshots").forEach { it.obj().apply {
            str("id"); str("periodID"); str("effectiveFrom"); data("configurationData"); str("fingerprint"); num("editedAtMs"); int("editCount"); str("editTieBreaker")
        } }
        o.arr("calendarExceptions").forEach { it.obj().apply {
            str("dayKey"); str("date"); enum("effect", CalendarEffect.entries) { it.raw }; enum("origin", CalendarExceptionOrigin.entries) { it.raw }
            bool("isCleared"); optStr("regionIdentifier"); optStr("datasetVersion"); optStr("label"); num("editedAtMs"); int("editCount"); str("editTieBreaker"); optStr("timeZoneIdentifier")
        } }
        o.arr("dayOverrides").forEach { it.obj().apply {
            str("dayKey"); enum("kind", DayOverrideKind.entries) { it.raw }; segments("segments"); optStr("note"); num("editedAtMs"); int("editCount"); str("editTieBreaker"); optStr("timeZoneIdentifier")
        } }
        o.arr("workObservations").forEach { it.obj().apply {
            str("eventID"); str("shiftAnchorDate"); num("occurredAtMs"); enum("kind", WorkObservationKind.entries) { it.raw }; optData("valueData")
            str("scheduleSnapshotID"); int("schemaVersion"); optStr("timeZoneIdentifier"); optNum("editedAtMs"); optInt("editCount"); optStr("editTieBreaker")
        } }
        o.optObj("lifeProfile")?.apply {
            str("profileID"); optInt("birthYear"); optStr("workStartedOn"); optInt("retirementAge"); optNum("averageSleepHours"); bool("hidesExactAges")
            listOf("bornOn", "schoolStartedOn", "workStartedPartial", "retirementOn").forEach { key -> optObj(key)?.let(::partialDate) }
            optInt("averageSleepMinutes"); optEnum("sleepSource", SleepSource.entries) { it.raw }; optNum("sleepSourceUpdatedAtMs")
            optEnum("workHistoryMode", LifeWorkHistoryMode.entries) { it.raw }; optObj("roughCurrentSalary")?.let(::salary)
            optArr("employmentPeriods")?.forEach { employmentPeriod(it.obj()) }
            optObj("futureIncomeDecline")?.let { LifeIncomeDecline(it.int("startsAtAge"), it.num("retirementRatio")) }
            num("editedAtMs"); int("editCount"); str("editTieBreaker")
        }
        o.optArr("focusTasks")?.forEach { it.obj().apply {
            str("id"); num("createdAtMs"); optStr("plannedForDate"); optNum("scheduledStartAtMs"); str("title"); int("estimatedPomodoros"); optStr("icon"); optBool("isFavorite")
            optNum("completedAtMs"); optNum("deletedAtMs"); int("sortIndex"); num("editedAtMs"); int("editCount"); str("editTieBreaker"); optStr("templateID"); optStr("templateTaskKey")
        } }
        o.optArr("focusSessions")?.forEach { it.obj().apply {
            str("id"); optStr("taskID"); str("shiftAnchorDate"); num("startedAtMs"); num("plannedEndAtMs"); optNum("endedAtMs"); optEnum("endReason", FocusEndReason.entries) { it.raw }
            num("editedAtMs"); int("editCount"); str("editTieBreaker"); optEnum("kind", FocusSessionKind.entries) { it.raw }; optStr("timeZoneIdentifier"); optStr("anchorDayKey")
            optInt("actualDurationSeconds"); optEnum("plannedEndReason", FocusEndReason.entries) { it.raw }
        } }
        o.optObj("focusPlanningConfiguration")?.apply {
            arr("plans").forEach { it.obj().apply { str("dayKey"); long("shiftStartAtMs"); arr("assignments").forEach { a -> assignment(a.obj()) }; optStr("appliedTemplateID") } }
            arr("templates").forEach { it.obj().apply { str("id"); str("name"); arr("slots").forEach { s -> slot(s.obj()) }; num("createdAtMs"); num("updatedAtMs") } }
            optStr("defaultTemplateID"); arr("autoAppliedDayKeys").forEach { it.string() }
            int("focusMinutes"); int("shortBreakMinutes"); int("longBreakMinutes"); int("longBreakEvery"); num("editedAtMs"); int("editCount"); str("editTieBreaker")
        }
        o.optObj("syncedPreferences")?.let(::preferences)
        o.optStr("recordsStartedOn")
        o.optObj("extendedSchedule")?.apply {
            bool("isEnabled"); arr("shiftTypes").forEach { shiftType(it.obj()) }; optObj("rule")?.let(::rule)
            optStr("holidayRegionIdentifier"); optStr("clearedFromDayKey"); str("timeZoneIdentifier"); num("editedAtMs"); int("editCount"); str("editTieBreaker")
        }
        o.optArr("rosterDays")?.forEach { it.obj().apply {
            str("dayKey"); str("shiftTypeID"); optObj("assignedShiftType")?.let(::shiftType); optBool("generatedFromPattern")
            str("timeZoneIdentifier"); num("editedAtMs"); int("editCount"); str("editTieBreaker")
        } }
    }

    // Typed values that `Codable` decodes itself (a bad UUID or enum fails the document).

    private fun partialDate(o: JsonObject) = PartialCivilDate(o.int("year"), o.optInt("month"), o.optInt("day"), o.enum("precision", CivilDatePrecision.entries) { it.raw })
    private fun salary(o: JsonObject) = LifeSalary(o.num("amount"), o.enum("cadence", LifeSalaryCadence.entries) { it.raw })
    private fun employmentPeriod(o: JsonObject) = LifeEmploymentPeriod(o.typedUuid("id"), partialDate(o.obj("startsOn")), o.optObj("endsOn")?.let(::partialDate), salary(o.obj("salary")))
    private fun assignment(o: JsonObject) = FocusPlanAssignment(
        o.long("blockStartAtMs"), o.enum("kind", FocusPlanBlockKind.entries) { it.raw }, o.optTypedUuid("taskID"), o.optStr("taskTitle"),
        o.optEnum("taskIcon", FocusTaskIcon.entries) { it.raw },
    )
    private fun slot(o: JsonObject) = FocusTemplateSlot(
        o.int("blockIndex"), o.enum("kind", FocusPlanBlockKind.entries) { it.raw }, o.optTypedUuid("taskKey"), o.optStr("taskTitle"),
        o.optEnum("taskIcon", FocusTaskIcon.entries) { it.raw },
    )

    internal fun shiftType(o: JsonObject) = ShiftType(
        id = UUID.fromString(o.typedUuid("id")),
        name = o.str("name"),
        kind = o.enum("kind", ShiftType.Kind.entries) { it.raw },
        startMinutes = o.int("startMinutes"),
        endMinutes = o.int("endMinutes"),
        breakEnabled = o.bool("breakEnabled"),
        breakStartMinutes = o.int("breakStartMinutes"),
        breakDurationMinutes = o.int("breakDurationMinutes"),
        colorHex = o.str("colorHex"),
        isArchived = o.bool("isArchived"),
    )

    private fun rule(o: JsonObject) = ShiftCycleRule(
        ShiftCycleRule.Preset.fromRaw(o.str("preset")),
        o.str("anchorDayKey"),
        o.arr("days").map { UUID.fromString(it.typedUuid()) },
    )

    private fun preferences(o: JsonObject): SyncedPreferences {
        fun choice(key: String, allowed: Set<String>) = o.str(key).also { if (it !in allowed) throw IllegalArgumentException("$key") }
        return SyncedPreferences(
            startMinutes = o.int("startMinutes"), endMinutes = o.int("endMinutes"),
            workdays = o.arr("workdays").map { it.int() },
            scheduleMode = choice("scheduleMode", SyncedPreferences.SCHEDULE_MODES),
            alternatingWeekType = choice("alternatingWeekType", SyncedPreferences.WEEK_TYPES),
            alternatingWeekendWorkday = o.int("alternatingWeekendWorkday"),
            alternatingReferenceWeekStartMs = o.num("alternatingReferenceWeekStartMs"),
            rotationWorkDays = o.int("rotationWorkDays"), rotationRestDays = o.int("rotationRestDays"), rotationAnchorMs = o.num("rotationAnchorMs"),
            lunchEnabled = o.bool("lunchEnabled"), lunchStartMinutes = o.int("lunchStartMinutes"), lunchDurationMinutes = o.int("lunchDurationMinutes"),
            recordsTimeZoneIdentifier = o.str("recordsTimeZoneIdentifier"),
            salaryAmount = o.str("salaryAmount"), salaryEnabled = o.bool("salaryEnabled"),
            salaryType = choice("salaryType", SyncedPreferences.SALARY_TYPES),
            monthlyWorkingDays = o.num("monthlyWorkingDays"), annualBonusEnabled = o.bool("annualBonusEnabled"), annualBonusMonths = o.num("annualBonusMonths"),
            notificationMode = choice("notificationMode", SyncedPreferences.NOTIFICATION_MODES),
            cycleEndSummaryNotificationEnabled = o.bool("cycleEndSummaryNotificationEnabled"),
            lunchStartReminderEnabled = o.bool("lunchStartReminderEnabled"), lunchEndReminderEnabled = o.bool("lunchEndReminderEnabled"),
            microBreakEnabled = o.bool("microBreakEnabled"), microBreakIntervalMinutes = o.int("microBreakIntervalMinutes"),
            theme = choice("theme", SyncedPreferences.THEMES),
            languageOverride = o.optStr("languageOverride"),
            // Older archives stored `editedAt` as Foundation seconds since 2001.
            editedAtMs = o.optNum("editedAtMs") ?: FoundationCompat.referenceDateSecondsToUnixMs(o.num("editedAt")),
            editCount = o.int("editCount"),
            editTieBreaker = o.typedUuid("editTieBreaker"),
        )
    }

    // Applying

    private class Calendars(val zone: String, val identifier: String)

    /**
     * `rowCalendar`: an explicit `iso8601` wins; `gregorian`, absent or unknown
     * fall back to the document's identifier. An unknown zone falls back too.
     */
    private fun rowCalendar(zone: String?, identifier: String?, fallback: Calendars) = Calendars(
        zone = zone?.let(FoundationCompat::timeZoneIdentifier) ?: fallback.zone,
        identifier = if (identifier == "iso8601") "iso8601" else fallback.identifier,
    )

    private fun documentCalendar(document: Document) = rowCalendar(
        document.timeZoneIdentifier, document.calendarIdentifier, Calendars("GMT", "gregorian"),
    )

    /**
     * Merges [document] into [state] (iOS `RecordJSON.apply`). Row order and
     * the early returns after a rejected life profile or Focus plan are the
     * source's, and the fixtures hold them.
     */
    fun apply(document: Document, state: RecordState, mode: ImportMode, newId: () -> String = { UUID.randomUUID().toString().uppercase(Locale.ROOT) }): Pair<RecordState, Report> {
        val work = Work(state, mode, newId)
        work.run(document)
        return work.state to work.report
    }

    private class Work(var state: RecordState, val mode: ImportMode, val newId: () -> String) {
        val report = Report()
        val periodIDMap = HashMap<String, String>()
        val snapshotIDMap = HashMap<String, String>()
        val taskIDMap = HashMap<String, String>()
        private val erasedKeys = state.erased.mapTo(HashSet()) { it.entityType to it.logicalKey }
        private val periods = Rows(state.periods) { it.id }
        private val snapshots = Rows(state.snapshots) { it.id }
        private val exceptions = Rows(state.exceptions) { it.dayKey }
        private val overrides = Rows(state.overrides) { it.dayKey }
        private val rosterDays = Rows(state.rosterDays) { it.dayKey }
        private val observations = Rows(state.observations) { it.eventID }
        private val focusTasks = Rows(state.focusTasks) { it.id }
        private val focusSessions = Rows(state.focusSessions) { it.id }

        private class Rows<T>(initial: List<T>, private val key: (T) -> String) {
            private val values = initial.toMutableList()
            private val positions = HashMap<String, Int>(values.size)
            init { values.forEachIndexed { index, row -> positions.putIfAbsent(key(row), index) } }
            operator fun get(id: String): T? = positions[id]?.let(values::get)
            fun add(row: T) { positions[key(row)] = values.size; values.add(row) }
            fun replace(row: T) { positions[key(row)]?.let { values[it] = row } ?: error("missing row") }
            fun all(): List<T> = values.toList()
        }

        fun run(document: Document) {
            val root = document.root
            val calendar = documentCalendar(document)
            val periodCalendars = LinkedHashMap<String, Calendars>()
            for (dto in root.arr("careerPeriods").map { it.obj() }) {
                val id = dto.str("id")
                if (uuid(id) != null && id !in periodCalendars) {
                    periodCalendars[id] = rowCalendar(dto.optStr("timeZoneIdentifier"), dto.optStr("calendarIdentifier"), calendar)
                }
            }

            for (dto in root.arr("careerPeriods").map { it.obj() }) {
                val incoming = period(dto, periodCalendars[dto.str("id")] ?: calendar)
                    ?: run { reject(RecordEntityType.CAREER_PERIOD, dto.str("id")); null } ?: continue
                merge(incoming, RecordEntityType.CAREER_PERIOD, incoming.id,
                    existing = { periods[incoming.id] },
                    insert = { s, v ->
                        var next = v
                        if (mode == ImportMode.RESTORE_ERASED && (RecordEntityType.CAREER_PERIOD to incoming.id) in erasedKeys) {
                            next = v.copy(id = newId()).also { periodIDMap[incoming.id] = it.id }
                        }
                        periods.add(next); s to next
                    },
                    replace = { s, v -> periods.replace(v); s to v },
                )
            }
            for (dto in root.arr("scheduleSnapshots").map { it.obj() }) {
                val incoming = snapshot(dto)
                    ?: run { reject(RecordEntityType.SCHEDULE_SNAPSHOT, dto.str("id")); null } ?: continue
                merge(incoming, RecordEntityType.SCHEDULE_SNAPSHOT, incoming.id,
                    existing = { snapshots[incoming.id] },
                    insert = { s, v ->
                        var next = v
                        if (mode == ImportMode.RESTORE_ERASED && (RecordEntityType.SCHEDULE_SNAPSHOT to incoming.id) in erasedKeys) {
                            next = v.copy(id = newId()).also { snapshotIDMap[incoming.id] = it.id }
                        }
                        periodIDMap[next.periodID]?.let { next = next.copy(periodID = it) }
                        snapshots.add(next); s to next
                    },
                    replace = { s, v ->
                        val next = periodIDMap[v.periodID]?.let { v.copy(periodID = it) } ?: v
                        snapshots.replace(next); s to next
                    },
                )
            }
            for (dto in root.arr("calendarExceptions").map { it.obj() }) {
                val incoming = exception(dto, rowCalendar(dto.optStr("timeZoneIdentifier"), null, calendar))
                    ?: run { reject(RecordEntityType.CALENDAR_EXCEPTION, dto.str("dayKey")); null } ?: continue
                merge(incoming, RecordEntityType.CALENDAR_EXCEPTION, incoming.dayKey,
                    existing = { exceptions[incoming.dayKey] },
                    insert = { s, v -> exceptions.add(v); s to v },
                    replace = { s, v -> exceptions.replace(v); s to v },
                )
            }
            for (dto in root.arr("dayOverrides").map { it.obj() }) {
                val incoming = override(dto, rowCalendar(dto.optStr("timeZoneIdentifier"), null, calendar))
                    ?: run { reject(RecordEntityType.DAY_OVERRIDE, dto.str("dayKey")); null } ?: continue
                merge(incoming, RecordEntityType.DAY_OVERRIDE, incoming.dayKey,
                    existing = { overrides[incoming.dayKey] },
                    insert = { s, v -> overrides.add(v); s to v },
                    replace = { s, v -> overrides.replace(v); s to v },
                )
            }
            for (dto in root.optArr("rosterDays").orEmpty().map { it.obj() }) {
                val incoming = rosterDay(dto) ?: run { reject(RecordEntityType.ROSTER_DAY, dto.str("dayKey")); null } ?: continue
                merge(incoming, RecordEntityType.ROSTER_DAY, incoming.dayKey,
                    existing = { rosterDays[incoming.dayKey] },
                    insert = { s, v -> rosterDays.add(v); s to v },
                    replace = { s, v -> rosterDays.replace(v); s to v },
                )
            }
            for (dto in root.arr("workObservations").map { it.obj() }) {
                val incoming = observation(dto, rowCalendar(dto.optStr("timeZoneIdentifier"), null, calendar))
                    ?: run { reject(RecordEntityType.WORK_OBSERVATION, dto.str("eventID")); null } ?: continue
                merge(incoming, RecordEntityType.WORK_OBSERVATION, incoming.eventID,
                    existing = { observations[incoming.eventID] },
                    insert = { s, v ->
                        var next = v
                        if (mode == ImportMode.RESTORE_ERASED && (RecordEntityType.WORK_OBSERVATION to incoming.eventID) in erasedKeys) next = next.copy(eventID = newId())
                        snapshotIDMap[next.scheduleSnapshotID]?.let { next = next.copy(scheduleSnapshotID = it) }
                        observations.add(next); s to next
                    },
                    replace = { s, v ->
                        val next = snapshotIDMap[v.scheduleSnapshotID]?.let { v.copy(scheduleSnapshotID = it) } ?: v
                        observations.replace(next); s to next
                    },
                )
            }
            for (dto in root.optArr("focusTasks").orEmpty().map { it.obj() }) {
                val incoming = focusTask(dto) ?: run { reject(RecordEntityType.FOCUS_TASK, dto.str("id")); null } ?: continue
                merge(incoming, RecordEntityType.FOCUS_TASK, incoming.id,
                    existing = { focusTasks[incoming.id] },
                    insert = { s, v ->
                        var next = v
                        if (mode == ImportMode.RESTORE_ERASED && (RecordEntityType.FOCUS_TASK to incoming.id) in erasedKeys) {
                            next = v.copy(id = newId()).also { taskIDMap[incoming.id] = it.id }
                        }
                        focusTasks.add(next); s to next
                    },
                    replace = { s, v -> focusTasks.replace(v); s to v },
                )
            }
            for (dto in root.optArr("focusSessions").orEmpty().map { it.obj() }) {
                val incoming = focusSession(dto, calendar) ?: run { reject(RecordEntityType.FOCUS_SESSION, dto.str("id")); null } ?: continue
                merge(incoming, RecordEntityType.FOCUS_SESSION, incoming.id,
                    existing = { focusSessions[incoming.id] },
                    insert = { s, v ->
                        var next = v
                        if (mode == ImportMode.RESTORE_ERASED && (RecordEntityType.FOCUS_SESSION to incoming.id) in erasedKeys) next = next.copy(id = newId())
                        next.taskID?.let { taskIDMap[it] }?.let { next = next.copy(taskID = it) }
                        focusSessions.add(next); s to next
                    },
                    replace = { s, v ->
                        val next = v.taskID?.let { taskIDMap[it] }?.let { v.copy(taskID = it) } ?: v
                        focusSessions.replace(next); s to next
                    },
                )
            }
            root.optObj("lifeProfile")?.let { dto ->
                val incoming = lifeProfile(dto)
                if (incoming == null) {
                    reject(RecordEntityType.LIFE_PROFILE, dto.str("profileID"))
                    finish(false)
                    return
                }
                merge(incoming, RecordEntityType.LIFE_PROFILE, LifeProfile.PROFILE_ID,
                    existing = { it.lifeProfile },
                    insert = { s, v -> s.copy(lifeProfile = v) to v },
                    replace = { s, v -> s.copy(lifeProfile = v) to v },
                )
            }
            // Before the Focus planning block, whose rejection returns early.
            root.optObj("extendedSchedule")?.let { dto ->
                val incoming = extendedSchedule(dto)
                if (incoming == null) {
                    reject(RecordEntityType.EXTENDED_SCHEDULE, ExtendedSchedule.LOGICAL_KEY)
                } else {
                    merge(incoming, RecordEntityType.EXTENDED_SCHEDULE, ExtendedSchedule.LOGICAL_KEY,
                        existing = { it.extendedSchedule },
                        insert = { s, v -> s.copy(extendedSchedule = v) to v },
                        replace = { s, v -> s.copy(extendedSchedule = v) to v },
                    )
                }
            }
            root.optObj("focusPlanningConfiguration")?.let { dto ->
                val incoming = focusPlanning(dto)
                if (incoming == null) {
                    reject(RecordEntityType.FOCUS_PLANNING_CONFIGURATION, FocusPlanningConfiguration.LOGICAL_KEY)
                    finish(false)
                    return
                }
                merge(incoming, RecordEntityType.FOCUS_PLANNING_CONFIGURATION, FocusPlanningConfiguration.LOGICAL_KEY,
                    existing = { it.focusPlanningConfiguration },
                    insert = { s, v -> s.copy(focusPlanningConfiguration = v) to v },
                    replace = { s, v -> s.copy(focusPlanningConfiguration = v) to v },
                )
            }
            root.optObj("syncedPreferences")?.let { dto ->
                val incoming = preferences(dto)
                if (incoming.isValid) {
                    merge(incoming, RecordEntityType.SYNCED_PREFERENCES, SyncedPreferences.LOGICAL_KEY,
                        existing = { it.syncedPreferences },
                        insert = { s, v -> s.copy(syncedPreferences = v) to v },
                        replace = { s, v -> s.copy(syncedPreferences = v) to v },
                    )
                } else {
                    reject(RecordEntityType.SYNCED_PREFERENCES, SyncedPreferences.LOGICAL_KEY)
                }
            }

            finish(true)
            root.optStr("recordsStartedOn")?.let(::canonicalDayKey)?.let { started ->
                val current = state.recordsStartedOn
                if (current == null || started < current) state = state.copy(recordsStartedOn = started)
            }
        }

        private fun finish(remapReferences: Boolean) {
            state = state.copy(
                periods = periods.all(),
                snapshots = snapshots.all().map { s -> if (remapReferences) periodIDMap[s.periodID]?.let { s.copy(periodID = it) } ?: s else s },
                exceptions = exceptions.all(),
                overrides = overrides.all(),
                rosterDays = rosterDays.all(),
                observations = observations.all().map { o -> if (remapReferences) snapshotIDMap[o.scheduleSnapshotID]?.let { o.copy(scheduleSnapshotID = it) } ?: o else o },
                focusTasks = focusTasks.all(),
                focusSessions = focusSessions.all().map { f -> if (remapReferences) f.taskID?.let { taskIDMap[it] }?.let { f.copy(taskID = it) } ?: f else f },
                lifeProfile = if (remapReferences) state.lifeProfile?.let(::migrateLegacyFields) else state.lifeProfile,
            )
        }

        fun reject(type: RecordEntityType, key: String) {
            report.rejected += Rejection(type, key)
        }

        fun <T : Any> merge(
            incoming: T,
            type: RecordEntityType,
            key: String,
            existing: (RecordState) -> T?,
            insert: (RecordState, T) -> Pair<RecordState, T>,
            replace: (RecordState, T) -> Pair<RecordState, T>,
        ) {
            if ((type to key) in erasedKeys) {
                when {
                    mode != ImportMode.RESTORE_ERASED && mode != ImportMode.FORCE_INCOMING -> {
                        report.skippedErased.increment(type)
                        return
                    }
                    existing(state) == null -> {
                        val (next, written) = insert(state, incoming)
                        state = next
                        report.restored.increment(type)
                        report.adopted += adoption(written, type)
                        return
                    }
                    // A natural key can exist again under its tombstone; fall through rather than append a duplicate.
                }
            }
            val current = existing(state)
            if (current != null) {
                if (current == incoming) {
                    report.unchanged.increment(type)
                    return
                }
                val takeIncoming = mode == ImportMode.FORCE_INCOMING || mode == ImportMode.RESOLVE_BY_EDIT_STAMP && incomingWins(incoming, current)
                if (takeIncoming) {
                    val (next, written) = replace(state, incoming)
                    state = next
                    report.adopted += adoption(written, type)
                }
                report.conflicts += Conflict(type, key, incoming, editCount(current), editCount(incoming), takeIncoming)
                return
            }
            val (next, written) = insert(state, incoming)
            state = next
            report.inserted.increment(type)
            report.adopted += adoption(written, type)
        }
    }

    // Rows (Swift `value(calendar:)`): null rejects the row.

    private fun period(o: JsonObject, calendar: Calendars): CareerPeriod? {
        val id = uuid(o.str("id")) ?: return null
        val startsOn = canonicalDayKey(o.str("startsOn")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val endsBefore = o.optStr("endsBefore")?.let { canonicalDayKey(it) ?: return null }
        if (endsBefore != null && endsBefore <= startsOn) return null
        return CareerPeriod(
            id, startsOn, endsBefore, o.optStr("label"),
            timeZoneIdentifier = o.optStr("timeZoneIdentifier") ?: calendar.zone,
            calendarIdentifier = o.optStr("calendarIdentifier") ?: calendar.identifier,
            createdAtMs = o.num("createdAtMs"), editedAtMs = o.num("editedAtMs"), editCount = o.int("editCount"), editTieBreaker = tie,
        )
    }

    private fun snapshot(o: JsonObject): ScheduleSnapshot? {
        val id = uuid(o.str("id")) ?: return null
        val periodID = uuid(o.str("periodID")) ?: return null
        val effectiveFrom = canonicalDayKey(o.str("effectiveFrom")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        return ScheduleSnapshot(id, periodID, effectiveFrom, FoundationCompat.base64(o.data("configurationData")), o.str("fingerprint"), o.num("editedAtMs"), o.int("editCount"), tie)
    }

    private fun exception(o: JsonObject, calendar: Calendars): CalendarException? {
        val date = canonicalDayKey(o.str("date")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        return CalendarException(
            o.str("dayKey"), date,
            o.enum("effect", CalendarEffect.entries) { it.raw }, o.enum("origin", CalendarExceptionOrigin.entries) { it.raw },
            o.bool("isCleared"), o.optStr("regionIdentifier"), o.optStr("datasetVersion"), o.optStr("label"),
            o.num("editedAtMs"), o.int("editCount"), tie, o.optStr("timeZoneIdentifier") ?: calendar.zone,
        )
    }

    private fun override(o: JsonObject, calendar: Calendars): DayOverride? {
        val kind = o.enum("kind", DayOverrideKind.entries) { it.raw }
        val segments = o.segments("segments")
        if (!validOverrideSegments(segments, kind)) return null
        canonicalDayKey(o.str("dayKey")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        return DayOverride(o.str("dayKey"), kind, segments, o.optStr("note"), o.num("editedAtMs"), o.int("editCount"), tie, o.optStr("timeZoneIdentifier") ?: calendar.zone)
    }

    /** Custom segments must be sorted, positive and non-overlapping; every other kind carries none. */
    fun validOverrideSegments(segments: List<ShiftSegment>, kind: DayOverrideKind): Boolean {
        if (kind == DayOverrideKind.CUSTOM_SEGMENTS) {
            if (segments.isEmpty()) return false
        } else if (segments.isNotEmpty()) {
            return false
        }
        var previousEnd: Double? = null
        for (segment in segments) {
            if (!segment.startAtMs.isFinite() || !segment.endAtMs.isFinite() || segment.endAtMs <= segment.startAtMs) return false
            if (previousEnd != null && segment.startAtMs < previousEnd) return false
            previousEnd = segment.endAtMs
        }
        return true
    }

    private fun observation(o: JsonObject, calendar: Calendars): WorkObservation? {
        val eventID = uuid(o.str("eventID")) ?: return null
        val anchor = canonicalDayKey(o.str("shiftAnchorDate")) ?: return null
        val snapshotID = uuid(o.str("scheduleSnapshotID")) ?: return null
        val occurredAtMs = o.num("occurredAtMs")
        return WorkObservation(
            eventID, anchor, occurredAtMs, o.enum("kind", WorkObservationKind.entries) { it.raw },
            o.optData("valueData")?.let(FoundationCompat::base64), snapshotID, o.int("schemaVersion"),
            o.optStr("timeZoneIdentifier") ?: calendar.zone,
            // v1/v2 rows predate stamps: they migrate to their immutable event values.
            editedAtMs = o.optNum("editedAtMs") ?: occurredAtMs,
            editCount = maxOf(1, o.optInt("editCount") ?: 1),
            editTieBreaker = o.optStr("editTieBreaker")?.let(::uuid) ?: eventID,
        )
    }

    private fun lifeProfile(o: JsonObject): LifeProfile? {
        val profileID = uuid(o.str("profileID")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val workStartedOn = o.optStr("workStartedOn")?.let { canonicalDayKey(it) ?: return null }
        val periods = o.optArr("employmentPeriods")?.map { employmentPeriod(it.obj()) } ?: emptyList()
        val rough = o.optObj("roughCurrentSalary")?.let(::salary)
        val decline = o.optObj("futureIncomeDecline")?.let { LifeIncomeDecline(it.int("startsAtAge"), it.num("retirementRatio")) }
        if (rough != null && !isValid(rough)) return null
        if (!periods.all(::isValid)) return null
        if (periods.map { it.id }.toSet().size != periods.size) return null
        if (decline != null && !(decline.startsAtAge in 0..120 && decline.retirementRatio.isFinite() && decline.retirementRatio in 0.0..1.0)) return null
        return migrateLegacyFields(
            LifeProfile(
                profileID = profileID,
                birthYear = o.optInt("birthYear"),
                workStartedOn = workStartedOn,
                retirementAge = o.optInt("retirementAge"),
                averageSleepHours = o.optNum("averageSleepHours"),
                hidesExactAges = o.bool("hidesExactAges"),
                bornOn = o.optObj("bornOn")?.let(::partialDate),
                schoolStartedOn = o.optObj("schoolStartedOn")?.let(::partialDate),
                workStartedPartial = o.optObj("workStartedPartial")?.let(::partialDate),
                retirementOn = o.optObj("retirementOn")?.let(::partialDate),
                averageSleepMinutes = o.optInt("averageSleepMinutes"),
                sleepSource = o.optEnum("sleepSource", SleepSource.entries) { it.raw },
                sleepSourceUpdatedAtMs = o.optNum("sleepSourceUpdatedAtMs"),
                workHistoryMode = o.optEnum("workHistoryMode", LifeWorkHistoryMode.entries) { it.raw } ?: LifeWorkHistoryMode.ROUGH,
                roughCurrentSalary = rough,
                employmentPeriods = periods,
                futureIncomeDecline = decline,
                editedAtMs = o.num("editedAtMs"),
                editCount = o.int("editCount"),
                editTieBreaker = tie,
            ),
        )
    }

    private fun isValid(salary: LifeSalary) = salary.amount.isFinite() && salary.amount > 0

    /** Year-only dates anchor mid-year; day dates roll over like `Calendar.date(from:)`. */
    private fun anchor(date: PartialCivilDate) = when (date.precision) {
        CivilDatePrecision.YEAR -> FoundationCompat.lenientDate(date.year, 7, 1)
        CivilDatePrecision.DAY -> if (date.month == null || date.day == null) null else FoundationCompat.lenientDate(date.year, date.month, date.day)
    }

    private fun isValid(period: LifeEmploymentPeriod): Boolean {
        if (period.startsOn.precision != CivilDatePrecision.DAY || !isValid(period.salary)) return false
        val start = anchor(period.startsOn) ?: return false
        val end = period.endsOn ?: return true
        return end.precision == CivilDatePrecision.DAY && anchor(end)?.let { it > start } == true
    }

    private fun exactDate(year: Int, month: Int, day: Int): PartialCivilDate? {
        if (month !in 1..12 || day !in 1..31) return null
        runCatching { java.time.LocalDate.of(year, month, day) }.getOrNull() ?: return null
        return PartialCivilDate(year, month, day, CivilDatePrecision.DAY)
    }

    /** iOS `LifeProfile.migrateLegacyFields`, run on decode and after every apply. */
    fun migrateLegacyFields(profile: LifeProfile): LifeProfile {
        var p = profile
        if (p.bornOn == null && p.birthYear != null) p = p.copy(bornOn = PartialCivilDate(p.birthYear!!, null, null, CivilDatePrecision.YEAR))
        if (p.workStartedPartial == null && p.workStartedOn != null) {
            val (y, m, d) = p.workStartedOn!!.split("-").map { it.toInt() }
            p = p.copy(workStartedPartial = exactDate(y, m, d))
        }
        if (p.retirementOn == null && p.birthYear != null && p.retirementAge != null) {
            p = p.copy(retirementOn = PartialCivilDate(p.birthYear!! + p.retirementAge!!, null, null, CivilDatePrecision.YEAR))
        }
        val bornYear = p.bornOn?.year ?: p.birthYear
        if (p.retirementOn == null && bornYear != null) {
            p = p.copy(retirementAge = 60, retirementOn = PartialCivilDate(bornYear + 60, null, null, CivilDatePrecision.YEAR))
        }
        if (p.averageSleepMinutes == null && p.averageSleepHours != null) {
            p = p.copy(averageSleepMinutes = FoundationCompat.roundedHalfAwayFromZero(p.averageSleepHours!! * 60).toInt())
        }
        if (p.sleepSource == null && (p.averageSleepMinutes != null || p.averageSleepHours != null)) p = p.copy(sleepSource = SleepSource.MANUAL)
        if (p.workHistoryMode == LifeWorkHistoryMode.DETAILED) {
            val first = p.employmentPeriods.minWithOrNull(
                compareBy<LifeEmploymentPeriod> { it.startsOn.year }.thenBy { it.startsOn.month ?: 0 }.thenBy { it.startsOn.day ?: 0 },
            )
            if (first != null) p = p.copy(workStartedPartial = first.startsOn, workStartedOn = anchor(first.startsOn)?.let(FoundationCompat::dayKey))
        }
        return p
    }

    private fun focusTask(o: JsonObject): FocusTask? {
        val id = uuid(o.str("id")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val planned = o.optStr("plannedForDate")?.let { canonicalDayKey(it) ?: return null }
        return FocusTask(
            id, o.num("createdAtMs"), planned, o.optNum("scheduledStartAtMs"), o.str("title"), o.int("estimatedPomodoros"),
            icon = o.optStr("icon")?.let { raw -> FocusTaskIcon.entries.firstOrNull { it.raw == raw } } ?: FocusTaskIcon.FOCUS,
            isFavorite = o.optBool("isFavorite") ?: false,
            completedAtMs = o.optNum("completedAtMs"), deletedAtMs = o.optNum("deletedAtMs"), sortIndex = o.int("sortIndex"),
            editedAtMs = o.num("editedAtMs"), editCount = o.int("editCount"), editTieBreaker = tie,
            templateID = o.optStr("templateID")?.let(::uuid), templateTaskKey = o.optStr("templateTaskKey")?.let(::uuid),
        )
    }

    private fun focusSession(o: JsonObject, calendar: Calendars): FocusSession? {
        val id = uuid(o.str("id")) ?: return null
        val anchor = canonicalDayKey(o.str("shiftAnchorDate")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val started = o.num("startedAtMs")
        val plannedEnd = o.num("plannedEndAtMs")
        return FocusSession(
            id, o.optStr("taskID")?.let(::uuid), anchor, started, plannedEnd, o.optNum("endedAtMs"),
            o.optEnum("endReason", FocusEndReason.entries) { it.raw },
            o.num("editedAtMs"), o.int("editCount"), tie,
            kind = o.optEnum("kind", FocusSessionKind.entries) { it.raw } ?: FocusSessionKind.FOCUS,
            timeZoneIdentifier = o.optStr("timeZoneIdentifier") ?: calendar.zone,
            anchorDayKey = o.optStr("anchorDayKey") ?: anchor,
            actualDurationSeconds = o.optInt("actualDurationSeconds"),
            // A second of slack on a 25-minute block (FocusPlanner.endReason).
            plannedEndReason = o.optEnum("plannedEndReason", FocusEndReason.entries) { it.raw }
                ?: if (plannedEnd / 1_000 - started / 1_000 >= 25 * 60 - 1) FocusEndReason.COMPLETED else FocusEndReason.STOPPED_AT_BOUNDARY,
        )
    }

    private fun focusPlanning(o: JsonObject): FocusPlanningConfiguration? {
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val editedAtMs = o.num("editedAtMs")
        if (!editedAtMs.isFinite() || o.int("editCount") < 0) return null
        val plans = LinkedHashMap<String, FocusDayPlan>()
        for (plan in o.arr("plans").map { it.obj() }) {
            val applied = plan.optStr("appliedTemplateID")?.let { uuid(it) ?: return null }
            val dayKey = plan.str("dayKey")
            if (dayKey in plans) return null
            plans[dayKey] = FocusDayPlan(dayKey, plan.long("shiftStartAtMs"), plan.arr("assignments").map { assignment(it.obj()) }.sortedBy { it.blockStartAtMs }, applied)
        }
        val templates = o.arr("templates").map { t ->
            val id = uuid(t.obj().str("id")) ?: return null
            val created = t.obj().num("createdAtMs")
            val updated = t.obj().num("updatedAtMs")
            if (!created.isFinite() || !updated.isFinite()) return null
            FocusTemplate(id, t.obj().str("name"), t.obj().arr("slots").map { slot(it.obj()) }.sortedBy { it.blockIndex }, created, updated)
        }
        if (templates.map { it.id }.toSet().size != templates.size) return null
        val defaultID = o.optStr("defaultTemplateID")?.let { uuid(it) ?: return null }
        return FocusPlanningConfiguration(
            plans = plans,
            templates = templates,
            defaultTemplateID = defaultID?.takeIf { id -> templates.any { it.id == id } },
            autoAppliedDayKeys = o.arr("autoAppliedDayKeys").map { it.string() }.toSet(),
            timerSettings = FocusTimerSettings(o.int("focusMinutes"), o.int("shortBreakMinutes"), o.int("longBreakMinutes"), o.int("longBreakEvery")).normalized,
            editedAtMs = editedAtMs, editCount = o.int("editCount"), editTieBreaker = tie,
        )
    }

    private fun extendedSchedule(o: JsonObject): ExtendedSchedule? {
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val editedAtMs = o.num("editedAtMs")
        if (!editedAtMs.isFinite()) return null
        val schedule = ExtendedSchedule(
            isEnabled = o.bool("isEnabled"),
            content = ExtendedScheduleContent(
                shiftTypes = o.arr("shiftTypes").map { shiftType(it.obj()) },
                rule = o.optObj("rule")?.let(::rule),
                holidayRegionIdentifier = o.optStr("holidayRegionIdentifier"),
                clearedFromDayKey = o.optStr("clearedFromDayKey"),
            ),
            timeZoneIdentifier = o.str("timeZoneIdentifier"),
            editedAtMs = editedAtMs,
            editCount = o.int("editCount"),
            editTieBreaker = tie,
        )
        val valid = FoundationCompat.isValidTimeZone(schedule.timeZoneIdentifier) && schedule.editCount >= 0 && schedule.content.isValid
        return schedule.takeIf { valid }
    }

    private fun rosterDay(o: JsonObject): RosterDay? {
        val shiftTypeID = uuid(o.str("shiftTypeID")) ?: return null
        val tie = uuid(o.str("editTieBreaker")) ?: return null
        val zone = o.str("timeZoneIdentifier")
        val editedAtMs = o.num("editedAtMs")
        val editCount = o.int("editCount")
        val frozen = o.optObj("assignedShiftType")?.let(::shiftType)
        if (!FoundationCompat.isValidTimeZone(zone) || !editedAtMs.isFinite() || editCount < 0) return null
        if (frozen != null && !(frozen.id.toString().equals(shiftTypeID, ignoreCase = true) && frozen.isValid)) return null
        canonicalDayKey(o.str("dayKey")) ?: return null
        return RosterDay(o.str("dayKey"), UUID.fromString(shiftTypeID), frozen, o.optBool("generatedFromPattern"), zone, editedAtMs, editCount, tie)
    }

    // Merge ranking

    private fun editCount(value: Any): Int = when (value) {
        is CareerPeriod -> value.editCount
        is ScheduleSnapshot -> value.editCount
        is CalendarException -> value.editCount
        is DayOverride -> value.editCount
        is WorkObservation -> if (value.editCount > 0) value.editCount else 1
        is LifeProfile -> value.editCount
        is FocusTask -> value.editCount
        is FocusSession -> value.editCount
        is FocusPlanningConfiguration -> value.editCount
        is SyncedPreferences -> value.editCount
        is ExtendedSchedule -> value.editCount
        is RosterDay -> value.editCount
        else -> error("not a record: $value")
    }

    private fun tieBreaker(value: Any): String = when (value) {
        is CareerPeriod -> value.editTieBreaker
        is ScheduleSnapshot -> value.editTieBreaker
        is CalendarException -> value.editTieBreaker
        is DayOverride -> value.editTieBreaker
        is WorkObservation -> if (value.editTieBreaker == ZERO_UUID) value.eventID else value.editTieBreaker
        is LifeProfile -> value.editTieBreaker
        is FocusTask -> value.editTieBreaker
        is FocusSession -> value.editTieBreaker
        is FocusPlanningConfiguration -> value.editTieBreaker
        is SyncedPreferences -> value.editTieBreaker
        is ExtendedSchedule -> value.editTieBreaker
        is RosterDay -> value.editTieBreaker
        else -> error("not a record: $value")
    }

    private fun identityKey(value: Any): String = when (value) {
        is CareerPeriod -> value.id
        is ScheduleSnapshot -> value.id
        is CalendarException -> value.dayKey
        is DayOverride -> value.dayKey
        is WorkObservation -> value.eventID
        is FocusTask -> value.id
        is FocusSession -> value.id
        is FocusPlanningConfiguration -> FocusPlanningConfiguration.LOGICAL_KEY
        is LifeProfile -> LifeProfile.PROFILE_ID
        is SyncedPreferences -> SyncedPreferences.LOGICAL_KEY
        is ExtendedSchedule -> ExtendedSchedule.LOGICAL_KEY
        is RosterDay -> value.dayKey
        else -> error("not a record: $value")
    }

    /** Higher `editCount` wins; a tie compares upper-case tie-breaker strings. */
    fun incomingWins(incoming: Any, current: Any): Boolean {
        val incomingCount = editCount(incoming)
        val localCount = editCount(current)
        if (incomingCount != localCount) return incomingCount > localCount
        return tieBreaker(incoming) > tieBreaker(current)
    }

    private fun adoption(value: Any, type: RecordEntityType) = Adoption(type, identityKey(value), editCount(value), tieBreaker(value))

    private const val ZERO_UUID = "00000000-0000-0000-0000-000000000000"

    /** Removes a row and leaves a tombstone at its version, so a revival must out-rank it. */
    fun erase(state: RecordState, type: RecordEntityType, key: String, atMs: Double): RecordState {
        fun same(id: String) = id.equals(key, ignoreCase = true)
        var buried = 0
        fun <T : Any> drop(list: List<T>, matches: (T) -> Boolean) = list.filter { item ->
            val hit = matches(item)
            if (hit) buried = maxOf(buried, editCount(item))
            !hit
        }
        var next = when (type) {
            RecordEntityType.CAREER_PERIOD -> state.copy(periods = drop(state.periods) { same(it.id) })
            RecordEntityType.SCHEDULE_SNAPSHOT -> state.copy(snapshots = drop(state.snapshots) { same(it.id) })
            RecordEntityType.CALENDAR_EXCEPTION -> state.copy(exceptions = drop(state.exceptions) { it.dayKey == key })
            RecordEntityType.DAY_OVERRIDE -> state.copy(overrides = drop(state.overrides) { it.dayKey == key })
            RecordEntityType.WORK_OBSERVATION -> state.copy(observations = drop(state.observations) { same(it.eventID) })
            RecordEntityType.LIFE_PROFILE -> { state.lifeProfile?.let { buried = editCount(it) }; state.copy(lifeProfile = null) }
            RecordEntityType.FOCUS_TASK -> state.copy(focusTasks = drop(state.focusTasks) { same(it.id) })
            RecordEntityType.FOCUS_SESSION -> state.copy(focusSessions = drop(state.focusSessions) { same(it.id) })
            RecordEntityType.FOCUS_PLANNING_CONFIGURATION -> { state.focusPlanningConfiguration?.let { buried = editCount(it) }; state.copy(focusPlanningConfiguration = null) }
            RecordEntityType.SYNCED_PREFERENCES -> { state.syncedPreferences?.let { buried = editCount(it) }; state.copy(syncedPreferences = null) }
            RecordEntityType.EXTENDED_SCHEDULE -> { state.extendedSchedule?.let { buried = editCount(it) }; state.copy(extendedSchedule = null) }
            RecordEntityType.ROSTER_DAY -> state.copy(rosterDays = drop(state.rosterDays) { it.dayKey == key })
        }
        val existing = next.erased.indexOfFirst { it.entityType == type && it.logicalKey == key }
        next = if (existing >= 0) {
            next.copy(erased = next.erased.mapIndexed { i, e -> if (i == existing) e.copy(editCount = maxOf(e.editCount, buried)) else e })
        } else {
            next.copy(erased = next.erased + ErasedID(type, key, atMs, buried))
        }
        return next
    }

    // Export

    private val encoder = Json { prettyPrint = false }

    /** A schema-6 document of [state]. Absent optionals are omitted, as Swift's encoder does. */
    fun export(state: RecordState, exportedAtMs: Double, timeZoneIdentifier: String, calendarIdentifier: String): String {
        val root = buildJsonObject {
            put("schemaVersion", SCHEMA_VERSION)
            put("exportedAtMs", exportedAtMs)
            put("timeZoneIdentifier", timeZoneIdentifier)
            put("calendarIdentifier", calendarIdentifier)
            put("careerPeriods", JsonArray(state.periods.map { p ->
                obj("id" to p.id, "startsOn" to p.startsOn, "endsBefore" to p.endsBefore, "label" to p.label, "timeZoneIdentifier" to p.timeZoneIdentifier,
                    "calendarIdentifier" to p.calendarIdentifier, "createdAtMs" to p.createdAtMs, "editedAtMs" to p.editedAtMs, "editCount" to p.editCount, "editTieBreaker" to p.editTieBreaker)
            }))
            put("scheduleSnapshots", JsonArray(state.snapshots.map { s ->
                obj("id" to s.id, "periodID" to s.periodID, "effectiveFrom" to s.effectiveFrom, "configurationData" to s.configurationData, "fingerprint" to s.fingerprint,
                    "editedAtMs" to s.editedAtMs, "editCount" to s.editCount, "editTieBreaker" to s.editTieBreaker)
            }))
            put("calendarExceptions", JsonArray(state.exceptions.map { e ->
                obj("dayKey" to e.dayKey, "date" to e.date, "effect" to e.effect.raw, "origin" to e.origin.raw, "isCleared" to e.isCleared, "regionIdentifier" to e.regionIdentifier,
                    "datasetVersion" to e.datasetVersion, "label" to e.label, "editedAtMs" to e.editedAtMs, "editCount" to e.editCount, "editTieBreaker" to e.editTieBreaker, "timeZoneIdentifier" to e.timeZoneIdentifier)
            }))
            put("dayOverrides", JsonArray(state.overrides.map { d ->
                obj("dayKey" to d.dayKey, "kind" to d.kind.raw, "segments" to segmentsJson(d.segments), "note" to d.note, "editedAtMs" to d.editedAtMs,
                    "editCount" to d.editCount, "editTieBreaker" to d.editTieBreaker, "timeZoneIdentifier" to d.timeZoneIdentifier)
            }))
            put("workObservations", JsonArray(state.observations.map { w ->
                obj("eventID" to w.eventID, "shiftAnchorDate" to w.shiftAnchorDate, "occurredAtMs" to w.occurredAtMs, "kind" to w.kind.raw, "valueData" to w.valueData,
                    "scheduleSnapshotID" to w.scheduleSnapshotID, "schemaVersion" to w.schemaVersion, "timeZoneIdentifier" to w.timeZoneIdentifier,
                    "editedAtMs" to w.editedAtMs, "editCount" to (if (w.editCount > 0) w.editCount else 1),
                    "editTieBreaker" to (if (w.editTieBreaker == ZERO_UUID) w.eventID else w.editTieBreaker))
            }))
            state.lifeProfile?.let { put("lifeProfile", lifeProfileJson(it)) }
            put("focusTasks", JsonArray(state.focusTasks.map { t ->
                obj("id" to t.id, "createdAtMs" to t.createdAtMs, "plannedForDate" to t.plannedForDate, "scheduledStartAtMs" to t.scheduledStartAtMs, "title" to t.title,
                    "estimatedPomodoros" to t.estimatedPomodoros, "icon" to t.icon.raw, "isFavorite" to t.isFavorite, "completedAtMs" to t.completedAtMs,
                    "deletedAtMs" to t.deletedAtMs, "sortIndex" to t.sortIndex, "editedAtMs" to t.editedAtMs, "editCount" to t.editCount,
                    "editTieBreaker" to t.editTieBreaker, "templateID" to t.templateID, "templateTaskKey" to t.templateTaskKey)
            }))
            put("focusSessions", JsonArray(state.focusSessions.map { f ->
                obj("id" to f.id, "taskID" to f.taskID, "shiftAnchorDate" to f.shiftAnchorDate, "startedAtMs" to f.startedAtMs, "plannedEndAtMs" to f.plannedEndAtMs,
                    "endedAtMs" to f.endedAtMs, "endReason" to f.endReason?.raw, "editedAtMs" to f.editedAtMs, "editCount" to f.editCount,
                    "editTieBreaker" to f.editTieBreaker, "kind" to f.kind.raw, "timeZoneIdentifier" to f.timeZoneIdentifier, "anchorDayKey" to f.anchorDayKey,
                    "actualDurationSeconds" to f.actualDurationSeconds, "plannedEndReason" to f.plannedEndReason.raw)
            }))
            state.focusPlanningConfiguration?.let { put("focusPlanningConfiguration", focusPlanningJson(it)) }
            state.syncedPreferences?.let { put("syncedPreferences", preferencesJson(it)) }
            state.recordsStartedOn?.let { put("recordsStartedOn", it) }
            state.extendedSchedule?.let { e ->
                put("extendedSchedule", obj("isEnabled" to e.isEnabled, "shiftTypes" to JsonArray(e.content.shiftTypes.map(::shiftTypeJson)),
                    "rule" to e.content.rule?.let { r -> obj("preset" to r.preset.raw, "anchorDayKey" to r.anchorDayKey, "days" to JsonArray(r.days.map { JsonPrimitive(upper(it)) })) },
                    "holidayRegionIdentifier" to e.content.holidayRegionIdentifier, "clearedFromDayKey" to e.content.clearedFromDayKey,
                    "timeZoneIdentifier" to e.timeZoneIdentifier, "editedAtMs" to e.editedAtMs, "editCount" to e.editCount, "editTieBreaker" to e.editTieBreaker))
            }
            put("rosterDays", JsonArray(state.rosterDays.map { r ->
                obj("dayKey" to r.dayKey, "shiftTypeID" to upper(r.shiftTypeID), "assignedShiftType" to r.assignedShiftType?.let(::shiftTypeJson),
                    "generatedFromPattern" to r.generatedFromPattern, "timeZoneIdentifier" to r.timeZoneIdentifier, "editedAtMs" to r.editedAtMs,
                    "editCount" to r.editCount, "editTieBreaker" to r.editTieBreaker)
            }))
        }
        return encoder.encodeToString(JsonObject.serializer(), root)
    }

    private fun upper(id: UUID) = id.toString().uppercase(Locale.ROOT)

    private fun segmentsJson(segments: List<ShiftSegment>) = JsonArray(segments.map { obj("startAtMs" to it.startAtMs, "endAtMs" to it.endAtMs) })

    internal fun shiftTypeJson(t: ShiftType) = obj(
        "id" to upper(t.id), "name" to t.name, "kind" to t.kind.raw, "startMinutes" to t.startMinutes, "endMinutes" to t.endMinutes,
        "breakEnabled" to t.breakEnabled, "breakStartMinutes" to t.breakStartMinutes, "breakDurationMinutes" to t.breakDurationMinutes,
        "colorHex" to t.colorHex, "isArchived" to t.isArchived,
    )

    private fun partialJson(d: PartialCivilDate?) = d?.let { obj("year" to it.year, "month" to it.month, "day" to it.day, "precision" to it.precision.raw) }
    private fun salaryJson(s: LifeSalary?) = s?.let { obj("amount" to it.amount, "cadence" to it.cadence.raw) }

    private fun lifeProfileJson(p: LifeProfile) = obj(
        "profileID" to p.profileID, "birthYear" to p.birthYear, "workStartedOn" to p.workStartedOn, "retirementAge" to p.retirementAge,
        "averageSleepHours" to p.averageSleepHours, "hidesExactAges" to p.hidesExactAges, "bornOn" to partialJson(p.bornOn),
        "schoolStartedOn" to partialJson(p.schoolStartedOn), "workStartedPartial" to partialJson(p.workStartedPartial), "retirementOn" to partialJson(p.retirementOn),
        "averageSleepMinutes" to p.averageSleepMinutes, "sleepSource" to p.sleepSource?.raw, "sleepSourceUpdatedAtMs" to p.sleepSourceUpdatedAtMs,
        "workHistoryMode" to p.workHistoryMode.raw, "roughCurrentSalary" to salaryJson(p.roughCurrentSalary),
        "employmentPeriods" to JsonArray(p.employmentPeriods.map { e ->
            obj("id" to e.id, "startsOn" to partialJson(e.startsOn), "endsOn" to partialJson(e.endsOn), "salary" to salaryJson(e.salary))
        }),
        "futureIncomeDecline" to p.futureIncomeDecline?.let { obj("startsAtAge" to it.startsAtAge, "retirementRatio" to it.retirementRatio) },
        "editedAtMs" to p.editedAtMs, "editCount" to p.editCount, "editTieBreaker" to p.editTieBreaker,
    )

    private fun focusPlanningJson(c: FocusPlanningConfiguration): JsonObject {
        val settings = c.timerSettings.normalized
        return obj(
            "plans" to JsonArray(c.plans.values.sortedBy { it.dayKey }.map { plan ->
                obj("dayKey" to plan.dayKey, "shiftStartAtMs" to plan.shiftStartAtMs,
                    "assignments" to JsonArray(plan.assignments.sortedBy { it.blockStartAtMs }.map { a ->
                        obj("blockStartAtMs" to a.blockStartAtMs, "kind" to a.kind.raw, "taskID" to a.taskID, "taskTitle" to a.taskTitle, "taskIcon" to a.taskIcon?.raw)
                    }),
                    "appliedTemplateID" to plan.appliedTemplateID)
            }),
            "templates" to JsonArray(c.templates.sortedBy { it.id }.map { t ->
                obj("id" to t.id, "name" to t.name, "slots" to JsonArray(t.slots.sortedBy { it.blockIndex }.map { s ->
                    obj("blockIndex" to s.blockIndex, "kind" to s.kind.raw, "taskKey" to s.taskKey, "taskTitle" to s.taskTitle, "taskIcon" to s.taskIcon?.raw)
                }), "createdAtMs" to t.createdAtMs, "updatedAtMs" to t.updatedAtMs)
            }),
            "defaultTemplateID" to c.defaultTemplateID,
            "autoAppliedDayKeys" to JsonArray(c.autoAppliedDayKeys.sorted().map(::JsonPrimitive)),
            "focusMinutes" to settings.focusMinutes, "shortBreakMinutes" to settings.shortBreakMinutes,
            "longBreakMinutes" to settings.longBreakMinutes, "longBreakEvery" to settings.longBreakEvery,
            "editedAtMs" to c.editedAtMs, "editCount" to c.editCount, "editTieBreaker" to c.editTieBreaker,
        )
    }

    private fun preferencesJson(p: SyncedPreferences) = obj(
        "startMinutes" to p.startMinutes, "endMinutes" to p.endMinutes, "workdays" to JsonArray(p.workdays.map(::JsonPrimitive)),
        "scheduleMode" to p.scheduleMode, "alternatingWeekType" to p.alternatingWeekType, "alternatingWeekendWorkday" to p.alternatingWeekendWorkday,
        "alternatingReferenceWeekStartMs" to p.alternatingReferenceWeekStartMs, "rotationWorkDays" to p.rotationWorkDays, "rotationRestDays" to p.rotationRestDays,
        "rotationAnchorMs" to p.rotationAnchorMs, "lunchEnabled" to p.lunchEnabled, "lunchStartMinutes" to p.lunchStartMinutes,
        "lunchDurationMinutes" to p.lunchDurationMinutes, "recordsTimeZoneIdentifier" to p.recordsTimeZoneIdentifier, "salaryAmount" to p.salaryAmount,
        "salaryEnabled" to p.salaryEnabled, "salaryType" to p.salaryType, "monthlyWorkingDays" to p.monthlyWorkingDays,
        "annualBonusEnabled" to p.annualBonusEnabled, "annualBonusMonths" to p.annualBonusMonths, "notificationMode" to p.notificationMode,
        "cycleEndSummaryNotificationEnabled" to p.cycleEndSummaryNotificationEnabled, "lunchStartReminderEnabled" to p.lunchStartReminderEnabled,
        "lunchEndReminderEnabled" to p.lunchEndReminderEnabled, "microBreakEnabled" to p.microBreakEnabled,
        "microBreakIntervalMinutes" to p.microBreakIntervalMinutes, "theme" to p.theme, "languageOverride" to p.languageOverride,
        "editedAtMs" to p.editedAtMs, "editCount" to p.editCount, "editTieBreaker" to p.editTieBreaker,
    )

    /** An object from pairs, leaving out nulls. */
    private fun obj(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(
        pairs.filter { it.second != null }.associate { (key, value) ->
            key to when (value) {
                is JsonElement -> value
                is String -> JsonPrimitive(value)
                is Boolean -> JsonPrimitive(value)
                is Int -> JsonPrimitive(value)
                is Long -> JsonPrimitive(value)
                is Double -> JsonPrimitive(value)
                else -> error("unsupported $value")
            }
        },
    )

    // Strict reading: `Codable` semantics.

    private fun fail(what: String): Nothing = throw Error.InvalidDocument(what)

    private fun JsonElement.obj(): JsonObject = this as? JsonObject ?: fail("expected object")
    private fun JsonElement.string(): String = (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("expected string")
    private fun JsonElement.number(): Double {
        val p = this as? JsonPrimitive ?: fail("expected number")
        if (p.isString || p is JsonNull || p.content == "true" || p.content == "false") fail("expected number")
        return p.content.toDoubleOrNull()?.takeIf { it.isFinite() } ?: fail("expected number")
    }
    private fun JsonElement.int(): Int {
        val value = number()
        if (value != Math.rint(value) || value < Int.MIN_VALUE || value > Int.MAX_VALUE) fail("expected integer")
        return value.toInt()
    }
    private fun JsonElement.long(): Long {
        val value = number()
        if (value != Math.rint(value)) fail("expected integer")
        val p = this as JsonPrimitive
        return runCatching { java.math.BigDecimal(p.content).toBigIntegerExact().longValueExact() }.getOrNull()
            ?: fail("expected integer")
    }
    private fun JsonElement.boolean(): Boolean {
        val p = this as? JsonPrimitive ?: fail("expected bool")
        if (p.isString) fail("expected bool")
        return when (p.content) { "true" -> true; "false" -> false; else -> fail("expected bool") }
    }
    private fun JsonElement.typedUuid(): String = uuid(string()) ?: fail("expected UUID")

    private fun JsonObject.required(key: String): JsonElement = get(key)?.takeIf { it !is JsonNull } ?: fail("missing $key")
    private fun JsonObject.optional(key: String): JsonElement? = get(key)?.takeIf { it !is JsonNull }

    private fun JsonObject.str(key: String) = required(key).string()
    private fun JsonObject.optStr(key: String) = optional(key)?.string()
    private fun JsonObject.num(key: String) = required(key).number()
    private fun JsonObject.optNum(key: String) = optional(key)?.number()
    private fun JsonObject.int(key: String) = required(key).int()
    private fun JsonObject.optInt(key: String) = optional(key)?.int()
    private fun JsonObject.long(key: String) = required(key).long()
    private fun JsonObject.bool(key: String) = required(key).boolean()
    private fun JsonObject.optBool(key: String) = optional(key)?.boolean()
    private fun JsonObject.obj(key: String) = required(key).obj()
    private fun JsonObject.optObj(key: String) = optional(key)?.obj()
    private fun JsonObject.arr(key: String) = required(key) as? JsonArray ?: fail("expected array $key")
    private fun JsonObject.optArr(key: String) = optional(key)?.let { it as? JsonArray ?: fail("expected array $key") }
    private fun JsonObject.typedUuid(key: String) = required(key).typedUuid()
    private fun JsonObject.optTypedUuid(key: String) = optional(key)?.typedUuid()
    private fun JsonObject.data(key: String) = FoundationCompat.base64(str(key)) ?: fail("bad base64 $key")
    private fun JsonObject.optData(key: String) = optStr(key)?.let { FoundationCompat.base64(it) ?: fail("bad base64 $key") }
    private fun <E> JsonObject.enum(key: String, entries: List<E>, raw: (E) -> String): E =
        str(key).let { value -> entries.firstOrNull { raw(it) == value } ?: fail("unknown $key $value") }
    private fun <E> JsonObject.optEnum(key: String, entries: List<E>, raw: (E) -> String): E? =
        optStr(key)?.let { value -> entries.firstOrNull { raw(it) == value } ?: fail("unknown $key $value") }
    private fun JsonObject.segments(key: String) = arr(key).map { ShiftSegment(it.obj().num("startAtMs"), it.obj().num("endAtMs")) }

    private fun <K> LinkedHashMap<K, Int>.increment(key: K) {
        this[key] = (this[key] ?: 0) + 1
    }

    private fun <T> List<T>.replaceFirst(matches: (T) -> Boolean, value: T): List<T> {
        val index = indexOfFirst(matches)
        return if (index < 0) this else toMutableList().also { it[index] = value }
    }
}
