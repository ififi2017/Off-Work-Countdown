import Foundation
import Observation

@MainActor
@Observable
final class FocusStore {
  struct Sources {
    var calendar: () -> Calendar
    var snapshot: (Date) -> NativeShiftSnapshot?
    var scheduleEnabled: (Date) -> Bool
    var shouldQuerySnapshot: (Date) -> Bool
    var isWorkday: (NativeShiftSnapshot, Date) -> Bool
    var overtimeEnd: () -> Double?
    var microBreakEnabled: () -> Bool
    var text: (String, [String: String]) -> String
    var count: (Int) -> String
    var time: (Date) -> String
  }

  let records: RecordCoordinator
  let plus: PlusEntitlement
  private let defaults: UserDefaults
  let sources: Sources
  @ObservationIgnored private var focusExpiryTask: Task<Void, Never>?

  private enum Key {
    static let focusPlanning = "ios.native.focusPlanning.v1"
    static let focusTimerSettings = "ios.native.focusTimerSettings.v1"
    static let focusNotificationsEnabled = "ios.native.focusNotificationsEnabled"
  }

  var recordsCalendar: Calendar { sources.calendar() }
  var overtimeEndAtMs: Double? { sources.overtimeEnd() }
  var microBreakEnabled: Bool { sources.microBreakEnabled() }
  func snapshot(at date: Date = .now) -> NativeShiftSnapshot? { sources.snapshot(date) }
  func shouldQuerySnapshot(at date: Date = .now) -> Bool { sources.shouldQuerySnapshot(date) }
  func t(_ key: String, values: [String: String] = [:]) -> String { sources.text(key, values) }
  func formatCount(_ value: Int) -> String { sources.count(value) }
  func formatTime(_ date: Date) -> String { sources.time(date) }

  private(set) var focusPlanning = FocusPlanningState()
  /// Synced with the planning configuration. Existing sessions carry their
  /// own fixed `plannedEndAt`, so a remote preference never rewrites a timer
  /// already in flight.
  private(set) var focusTimerSettings = FocusTimerSettings.default
  /// Cheap invalidation token for Widget / notification publication. The
  /// plan itself can contain hundreds of assignments, so ServiceCoordinator observes
  /// this instead of comparing or encoding the complete value on every frame.
  private(set) var focusPlanningRevision: UInt64 = 0
  /// Import, CloudKit and conflict resolution can replace an active focus
  /// row without changing local preferences. ServiceCoordinator observes this token to
  /// rebuild the one Live Activity and notification channel immediately.
  private(set) var focusRuntimeRevision: UInt64 = 0
  var focusNotificationsEnabled: Bool {
    didSet {
      guard oldValue != focusNotificationsEnabled else { return }
      defaults.set(focusNotificationsEnabled, forKey: Key.focusNotificationsEnabled)
      focusNotificationGeneration &+= 1
      if !focusNotificationsEnabled {
        focusNotificationIssue = nil
        if let session = activeFocusSession() {
          NotificationService.cancelFocusTimer(id: session.id)
        }
      }
    }
  }
  init(records: RecordCoordinator, defaults: UserDefaults, plus: PlusEntitlement, sources: Sources)
  {
    self.records = records
    self.defaults = defaults
    self.plus = plus
    self.sources = sources
    focusNotificationsEnabled =
      defaults.object(forKey: Key.focusNotificationsEnabled) as? Bool ?? true
    if let data = defaults.data(forKey: Key.focusPlanning),
      let stored = try? JSONDecoder().decode(FocusPlanningState.self, from: data)
    {
      focusPlanning = stored
    }
    if let data = defaults.data(forKey: Key.focusTimerSettings),
      let stored = try? JSONDecoder().decode(FocusTimerSettings.self, from: data)
    {
      focusTimerSettings = stored.normalized
    }
    if let configuration = self.records.state.focusPlanningConfiguration {
      focusPlanning = configuration.planning
      focusTimerSettings = configuration.timerSettings.normalized
      mirrorFocusConfigurationToLegacyDefaults()
    } else {
      let legacy = FocusPlanningConfiguration(
        planning: focusPlanning,
        timerSettings: focusTimerSettings,
        editedAt: .now,
        editCount: 0,
        editTieBreaker: UUID()
      )
      if legacy.hasUserContent {
        self.records.upsertFocusPlanningConfiguration(legacy)
      }
    }
  }

  func reconcileExternalState(at date: Date = .now) -> RecordCommand<Void> {
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        let syncedPlanning =
          records.state.focusPlanningConfiguration?.planning ?? FocusPlanningState()
        let syncedSettings =
          records.state.focusPlanningConfiguration?.timerSettings.normalized ?? .default
        if syncedPlanning != focusPlanning || syncedSettings != focusTimerSettings.normalized {
          focusPlanning = syncedPlanning
          focusTimerSettings = syncedSettings
          mirrorFocusConfigurationToLegacyDefaults()
          focusPlanningRevision &+= 1
        }
        carryIncompleteFocusTasks(at: date).synchronousResult
        restoreScheduledFocus(at: date).synchronousResult
        reconcileOpenFocusSessions(at: date).synchronousResult
        focusRuntimeRevision &+= 1
      }
    }
  }

  func focusScheduleSlots(at date: Date = .now) -> [FocusScheduleSlot] {
    var slots: [FocusScheduleSlot] = []
    if let current = snapshot(at: date) {
      for segment in current.segments where segment.endAtMs > date.timeIntervalSince1970 * 1_000 {
        slots.append(
          FocusScheduleSlot(
            start: Date(
              timeIntervalSince1970: max(segment.startAtMs, date.timeIntervalSince1970 * 1_000)
                / 1_000),
            end: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
            shiftAnchor: recordsCalendar.startOfDay(for: current.startDate),
            isCurrentShift: true
          )
        )
      }
    }
    if let nextStart = snapshot(at: date)?.nextShiftStartDate {
      if let upcoming = snapshot(at: nextStart.addingTimeInterval(60)) {
        for segment in upcoming.segments {
          slots.append(
            FocusScheduleSlot(
              start: Date(timeIntervalSince1970: segment.startAtMs / 1_000),
              end: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
              shiftAnchor: recordsCalendar.startOfDay(for: upcoming.startDate),
              isCurrentShift: false
            )
          )
        }
      }
    }
    return slots
  }

  func focusWorkBlocks(at date: Date = .now) -> [FocusWorkBlock] {
    guard let current = snapshot(at: date) else { return [] }
    return FocusPlanner.workBlocks(
      segments: current.segments,
      settings: focusTimerSettings
    )
  }

  @discardableResult
  func updateFocusTimerSettings(_ settings: FocusTimerSettings) -> RecordCommand<Bool> {
    return records.submitCommand { [self] in
      // Template slots are indexed against the current focus/break cycle.
      // Rejecting a cadence change is safer than silently mapping a saved
      // task slot onto a recovery block.
      guard focusPlanning.templates.isEmpty else { return false }
      let normalized = settings.normalized
      guard normalized != focusTimerSettings else { return true }
      focusTimerSettings = normalized
      persistFocusConfiguration()
      return true
    }
  }

  func updateFocusSettings(
    _ settings: FocusTimerSettings,
    liveActivityEnabled: Bool,
    notificationsEnabled: Bool,
    preferences: PreferencesStore
  ) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      guard updateFocusTimerSettings(settings).synchronousResult else { return false }
      preferences.focusLiveActivityEnabled = liveActivityEnabled
      focusNotificationsEnabled = notificationsEnabled
      return true
    }
  }

  func focusAssignment(for block: FocusWorkBlock, at date: Date = .now) -> FocusPlanAssignment? {
    guard let current = snapshot(at: date) else { return nil }
    if block.kind == .breakTime {
      return FocusPlanAssignment(
        blockStartAtMs: block.startAtMs,
        kind: .breakTime,
        taskID: nil,
        taskTitle: nil,
        taskIcon: nil
      )
    }
    let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
    return focusPlanning.plans[key]?.assignments.first { $0.blockStartAtMs == block.startAtMs }
  }

  func assignFocusBlock(
    _ block: FocusWorkBlock,
    to task: FocusTask,
    in shift: NativeShiftSnapshot? = nil,
    at date: Date = .now
  ) -> RecordCommand<Void> {
    let taskID = task.id
    let blockStartAtMs = block.startAtMs
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        guard let task = records.state.focusTasks.first(where: { $0.id == taskID }),
          plus.isAuthorized, task.deletedAt == nil,
          let current = shift.flatMap({ snapshot(at: $0.startDate) }) ?? snapshot(at: date),
          let block = focusPlanningBlocks(for: current).first(where: {
            $0.startAtMs == blockStartAtMs && $0.kind == .task
          })
        else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let replacedTaskID = focusPlanning.plans[key]?.assignments
          .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        let assignment = FocusPlanAssignment(
          blockStartAtMs: block.startAtMs,
          kind: .task,
          taskID: task.id,
          taskTitle: task.title,
          taskIcon: task.icon
        )
        updateFocusPlan(assignment, dayKey: key, shiftStartAtMs: Int64(current.startAtMs))
        var next = task
        next.plannedForDate = recordsCalendar.startOfDay(for: current.startDate)
        next.scheduledStartAt = earliestFocusAssignment(for: task.id)
        if next.templateID != nil { next.estimatedPomodoros = templateTaskEstimate(for: task.id) }
        records.upsertFocusTask(next)
        if let replacedTaskID, replacedTaskID != task.id {
          releaseTemplateTasks([replacedTaskID], at: date)
        }
      }
    }
  }

  func assignFocusBreak(
    _ block: FocusWorkBlock,
    in shift: NativeShiftSnapshot? = nil,
    at date: Date = .now
  ) -> RecordCommand<Void> {
    let blockStartAtMs = block.startAtMs
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        guard plus.isAuthorized,
          let current = shift.flatMap({ snapshot(at: $0.startDate) }) ?? snapshot(at: date),
          let block = focusPlanningBlocks(for: current).first(where: {
            $0.startAtMs == blockStartAtMs && $0.kind == .task
          })
        else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let replacedTaskID = focusPlanning.plans[key]?.assignments
          .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        updateFocusPlan(
          FocusPlanAssignment(
            blockStartAtMs: block.startAtMs,
            kind: .breakTime,
            taskID: nil,
            taskTitle: nil,
            taskIcon: nil
          ),
          dayKey: key,
          shiftStartAtMs: Int64(current.startAtMs)
        )
        if let replacedTaskID {
          releaseTemplateTasks([replacedTaskID], at: date)
        }
      }
    }
  }

  func clearFocusBlock(
    _ block: FocusWorkBlock,
    in shift: NativeShiftSnapshot? = nil,
    at date: Date = .now
  ) -> RecordCommand<Void> {
    let blockStartAtMs = block.startAtMs
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        guard let current = shift.flatMap({ snapshot(at: $0.startDate) }) ?? snapshot(at: date),
          let block = focusPlanningBlocks(for: current).first(where: {
            $0.startAtMs == blockStartAtMs
          })
        else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let removedTaskID = focusPlanning.plans[key]?.assignments
          .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        focusPlanning.plans[key]?.assignments.removeAll { $0.blockStartAtMs == block.startAtMs }
        // Clearing even one slot means this is no longer an untouched copy of
        // the template.  Keeping the old marker made a later Apply appear to
        // succeed while silently leaving the cleared slot empty.
        focusPlanning.plans[key]?.appliedTemplateID = nil
        focusPlanning.autoAppliedDayKeys.insert(key)
        if let removedTaskID { releaseTemplateTasks([removedTaskID], at: date) }
        persistFocusPlanning()
      }
    }
  }

  @discardableResult
  func saveFocusTemplate(name: String, at date: Date = .now) -> RecordCommand<FocusTemplate?> {
    records.submitCommand { [self] in
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard plus.isAuthorized, !trimmed.isEmpty,
        let current = snapshot(at: date)
      else { return nil }
      let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
      let assignments = focusPlanning.plans[key]?.assignments ?? []
      let blocks = focusWorkBlocks(at: date)
      var taskKeys: [UUID: UUID] = [:]
      let slots = blocks.compactMap { block -> FocusTemplateSlot? in
        let assignment =
          assignments.first(where: { $0.blockStartAtMs == block.startAtMs })
          ?? (block.kind == .breakTime
            ? FocusPlanAssignment(
              blockStartAtMs: block.startAtMs, kind: .breakTime, taskID: nil, taskTitle: nil,
              taskIcon: nil)
            : nil)
        guard let assignment, assignment.kind == block.kind else { return nil }
        let taskKey = assignment.taskID.map { taskID in
          if let existing = taskKeys[taskID] { return existing }
          let created = UUID()
          taskKeys[taskID] = created
          return created
        }
        return FocusTemplateSlot(
          blockIndex: block.index,
          kind: assignment.kind,
          taskKey: taskKey,
          taskTitle: assignment.taskTitle,
          taskIcon: assignment.taskIcon
        )
      }
      guard !slots.isEmpty else { return nil }
      let now = Date.now
      let template = FocusTemplate(
        id: UUID(), name: trimmed, slots: slots, createdAt: now, updatedAt: now)
      focusPlanning.templates.append(template)
      persistFocusPlanning()
      return template
    }
  }

  /// Writes for the template editor. They live here rather than in
  /// `FocusStore+Templates` because `focusPlanning` is
  /// `private(set)` on purpose — the editor owns what a usual day looks
  /// like, not how planning state is stored.
  func appendFocusTemplate(_ template: FocusTemplate) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      focusPlanning.templates.append(template)
      persistFocusPlanning()
    }
  }

  @discardableResult
  func replaceFocusTemplate(
    id: UUID, name: String, slots: [FocusTemplateSlot], at date: Date = .now
  ) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        guard let index = focusPlanning.templates.firstIndex(where: { $0.id == id }) else {
          return false
        }
        guard
          focusPlanning.templates[index].name != name
            || focusPlanning.templates[index].slots != slots
        else {
          return true
        }
        focusPlanning.templates[index].name = name
        focusPlanning.templates[index].slots = slots
        focusPlanning.templates[index].updatedAt = date
        reflowLinkedFocusPlans(templateID: id, at: date).synchronousResult
        persistFocusPlanning()
        return true
      }
    }
  }

  @discardableResult
  func applyFocusTemplate(
    _ template: FocusTemplate, in shift: NativeShiftSnapshot? = nil, at date: Date = .now,
    preservingStartedBlocks: Bool = false
  ) -> RecordCommand<Bool> {
    let templateID = template.id
    return records.submitCommand { [self] in
      guard let template = focusPlanning.templates.first(where: { $0.id == templateID }) else {
        return false
      }
      let started = ContinuousClock.now
      defer { LaunchTrace.report("applyFocusTemplate", since: started) }
      let currentShift =
        shift.flatMap { snapshot(at: $0.startDate) }
        ?? focusCanvasShift(at: date)?.snapshot
      guard plus.isAuthorized, let current = currentShift else { return false }
      let blocks = focusPlanningBlocks(for: current)
      let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
      let placedSlots = template.placedSlots(in: blocks)
      // The template identifier alone is insufficient: a user can clear or
      // replace a slot while the old plan still points at that template.  A
      // genuine repeat application is a no-op only when every rendered
      // assignment and its task provenance still matches the template.
      if focusTemplatePlanMatches(template, blocks: blocks, dayKey: key, anchor: current.startDate)
      {
        return true
      }
      return records.withBatchedWrites {
        let previousAssignments = focusPlanning.plans[key]?.assignments ?? []
        let previousTaskIDs = Set(previousAssignments.compactMap(\.taskID))
        let activeEnd = activeFocusSession().map {
          Int64($0.plannedEndAt.timeIntervalSince1970 * 1_000)
        }
        let protectedStarts = Set(
          blocks.filter { block in
            preservingStartedBlocks
              && (block.end <= date || activeEnd.map { block.startAtMs < $0 } == true)
          }.map(\.startAtMs))
        var materializedTasks: [String: FocusTask] = [:]
        var assignments = previousAssignments.filter { protectedStarts.contains($0.blockStartAtMs) }

        for slot in placedSlots {
          guard blocks.indices.contains(slot.blockIndex) else { continue }
          let block = blocks[slot.blockIndex]
          guard !protectedStarts.contains(block.startAtMs) else { continue }
          // Tasks cannot replace automatic recovery. A user-drawn break
          // may occupy either a task slot or an automatic recovery slot.
          guard slot.kind == .breakTime || block.kind == .task else { continue }
          if slot.kind == .breakTime {
            assignments.append(
              FocusPlanAssignment(
                blockStartAtMs: block.startAtMs,
                kind: .breakTime,
                taskID: nil,
                taskTitle: nil,
                taskIcon: nil
              ))
            continue
          }

          // Current templates persist a task key.  The slot-index fallback
          // keeps old key-less templates from collapsing multiple task slots
          // into one task during migration.
          let groupID = slot.taskKey?.uuidString ?? "legacy-slot-\(slot.blockIndex)"
          let task: FocusTask
          if let existing = materializedTasks[groupID] {
            task = existing
          } else {
            let matching =
              slot.taskKey.map { taskKey in
                placedSlots.count { $0.kind == .task && $0.taskKey == taskKey }
              } ?? 1
            if var reusable = reusableTemplateTask(
              template,
              slot: slot,
              anchor: current.startDate,
              block: block,
              includingCompleted: preservingStartedBlocks
            ) {
              reusable.title = slot.taskTitle ?? t("focusTitle")
              reusable.icon = slot.taskIcon ?? .focus
              reusable.deletedAt = nil
              reusable.plannedForDate = recordsCalendar.startOfDay(for: current.startDate)
              reusable.scheduledStartAt = block.start
              let upcomingCount =
                slot.taskKey == nil
                ? 1
                : placedSlots.count { candidate in
                  candidate.kind == .task && candidate.taskKey == slot.taskKey
                    && blocks.indices.contains(candidate.blockIndex)
                    && !protectedStarts.contains(blocks[candidate.blockIndex].startAtMs)
                }
              reusable.estimatedPomodoros = max(
                1, matching,
                completedFocusBlocks(for: reusable) + (preservingStartedBlocks ? upcomingCount : 0))
              if preservingStartedBlocks { reusable.completedAt = nil }
              records.upsertFocusTask(reusable)
              materializedTasks[groupID] = reusable
              task = reusable
            } else {
              var created = addFocusTaskAuthorized(
                title: slot.taskTitle ?? t("focusTitle"),
                pomodoros: max(1, matching),
                plannedFor: current.startDate,
                scheduledStartAt: block.start,
                icon: slot.taskIcon ?? .focus
              ).synchronousResult
              created.templateID = template.id
              created.templateTaskKey = slot.taskKey
              records.upsertFocusTask(created)
              materializedTasks[groupID] = created
              task = created
            }
          }
          assignments.append(
            FocusPlanAssignment(
              blockStartAtMs: block.startAtMs,
              kind: .task,
              taskID: task.id,
              taskTitle: task.title,
              taskIcon: task.icon
            ))
        }
        focusPlanning.plans[key] = FocusDayPlan(
          dayKey: key,
          shiftStartAtMs: Int64(current.startAtMs),
          assignments: assignments.sorted { $0.blockStartAtMs < $1.blockStartAtMs },
          appliedTemplateID: template.id
        )
        focusPlanning.autoAppliedDayKeys.insert(key)
        let materializedTaskIDs = Set(assignments.compactMap(\.taskID))
        releaseTemplateTasks(
          previousTaskIDs,
          preserving: materializedTaskIDs,
          at: date
        )
        for taskID in previousTaskIDs.union(materializedTaskIDs)
        where records.state.focusTasks
          .first(where: { $0.id == taskID })?.deletedAt == nil
        {
          refreshFocusTaskSchedule(for: taskID)
        }
        persistFocusPlanning()
        return !assignments.isEmpty
      }
    }
  }

  /// Refill only attached plans. Completed history is untouched, and a
  /// manual day edit remains detached even when the template or hours change.
  func reflowLinkedFocusPlans(templateID: UUID? = nil, at date: Date = .now) -> RecordCommand<Void>
  {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        let activeShift = snapshot(at: date)
        let firstDay =
          activeShift.map { RecordJSON.dayKey($0.startDate, calendar: recordsCalendar) }
          ?? RecordJSON.dayKey(date, calendar: recordsCalendar)
        let linked = focusPlanning.plans.values.filter {
          $0.dayKey >= firstDay && $0.appliedTemplateID != nil
            && (templateID == nil || $0.appliedTemplateID == templateID)
        }
        for plan in linked {
          guard
            let template = focusPlanning.templates.first(where: { $0.id == plan.appliedTemplateID }
            ),
            let day = RecordJSON.date(fromDayKey: plan.dayKey, calendar: recordsCalendar)
          else { continue }
          let shift: NativeShiftSnapshot?
          if let activeShift,
            RecordJSON.dayKey(activeShift.startDate, calendar: recordsCalendar) == plan.dayKey
          {
            shift = activeShift
          } else {
            let probe =
              recordsCalendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
            shift = snapshot(at: probe)
          }
          guard let shift,
            RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar) == plan.dayKey
          else { continue }
          _ =
            applyFocusTemplate(template, in: shift, at: date, preservingStartedBlocks: true)
            .synchronousResult
        }
      }
    }
  }

  func setDefaultFocusTemplate(_ template: FocusTemplate?) -> RecordCommand<Void> {
    let templateID = template?.id
    return records.submitCommand { [self] in
      focusPlanning.defaultTemplateID = templateID.flatMap { id in
        focusPlanning.templates.first(where: { $0.id == id })?.id
      }
      persistFocusPlanning()
    }
  }

  func deleteFocusTemplate(_ template: FocusTemplate) -> RecordCommand<Void> {
    let templateID = template.id
    return records.submitCommand { [self] in
      focusPlanning.templates.removeAll { $0.id == templateID }
      if focusPlanning.defaultTemplateID == templateID { focusPlanning.defaultTemplateID = nil }
      persistFocusPlanning()
    }
  }

  @discardableResult
  func applyDefaultFocusTemplateIfNeeded(at date: Date = .now) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      guard plus.isAuthorized,
        let current = focusCanvasShift(at: date)?.snapshot
      else { return false }
      let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
      guard !focusPlanning.autoAppliedDayKeys.contains(key) else { return false }
      if focusPlanning.plans[key]?.assignments.isEmpty == false {
        focusPlanning.autoAppliedDayKeys.insert(key)
        persistFocusPlanning()
        return false
      }
      guard let id = focusPlanning.defaultTemplateID,
        let template = focusPlanning.templates.first(where: { $0.id == id })
      else { return false }
      return applyFocusTemplate(template, at: date).synchronousResult
    }
  }

  /// Stored assignments, or a non-mutating projection of the default
  /// template for a future widget shift that the app has not opened yet.
  func focusPlanAssignments(
    for snapshot: NativeShiftSnapshot
  ) -> [(block: FocusWorkBlock, assignment: FocusPlanAssignment)] {
    let blocks = focusPlanningBlocks(for: snapshot)
    let key = RecordJSON.dayKey(snapshot.startDate, calendar: recordsCalendar)
    let assignments: [FocusPlanAssignment]
    if let plan = focusPlanning.plans[key] {
      assignments = plan.assignments
    } else if let id = focusPlanning.defaultTemplateID,
      let template = focusPlanning.templates.first(where: { $0.id == id })
    {
      assignments = template.placedSlots(in: blocks).compactMap { slot in
        guard blocks.indices.contains(slot.blockIndex) else { return nil }
        let block = blocks[slot.blockIndex]
        guard block.kind == .task else { return nil }
        return FocusPlanAssignment(
          blockStartAtMs: block.startAtMs, kind: slot.kind,
          taskID: nil, taskTitle: slot.taskTitle, taskIcon: slot.taskIcon
        )
      }
    } else {
      return []
    }
    return blocks.enumerated().compactMap { index, block in
      if block.kind == .breakTime {
        guard index > 0 else { return nil }
        let previous = blocks[index - 1]
        guard previous.kind == .task, previous.end == block.start,
          assignments.contains(where: {
            $0.blockStartAtMs == previous.startAtMs && $0.kind == .task
              && ($0.taskID != nil || $0.taskTitle?.isEmpty == false)
          })
        else { return nil }
        return (
          block,
          FocusPlanAssignment(
            blockStartAtMs: block.startAtMs, kind: .breakTime,
            taskID: nil, taskTitle: nil, taskIcon: nil
          )
        )
      }
      return assignments.first(where: { $0.blockStartAtMs == block.startAtMs }).map { (block, $0) }
    }
  }

  func focusPlanningBlocks(for snapshot: NativeShiftSnapshot) -> [FocusWorkBlock] {
    FocusPlanner.workBlocks(
      segments: snapshot.segments,
      settings: focusTimerSettings
    )
  }

  /// Widget range expansion deliberately carries a salary-free snapshot.
  /// It still needs the same planner inputs and shared-rule boundaries as
  /// the foreground view, so keep the projection-specific conversion here.
  func focusPlanningBlocks(for snapshot: NativeWidgetShiftSnapshot) -> [FocusWorkBlock] {
    FocusPlanner.workBlocks(
      segments: snapshot.segments,
      settings: focusTimerSettings
    )
  }

  private func updateFocusPlan(
    _ assignment: FocusPlanAssignment,
    dayKey: String,
    shiftStartAtMs: Int64
  ) {
    var plan =
      focusPlanning.plans[dayKey]
      ?? FocusDayPlan(
        dayKey: dayKey,
        shiftStartAtMs: shiftStartAtMs,
        assignments: [],
        appliedTemplateID: nil
      )
    plan.assignments.removeAll { $0.blockStartAtMs == assignment.blockStartAtMs }
    plan.assignments.append(assignment)
    plan.assignments.sort { $0.blockStartAtMs < $1.blockStartAtMs }
    plan.appliedTemplateID = nil
    focusPlanning.plans[dayKey] = plan
    focusPlanning.autoAppliedDayKeys.insert(dayKey)
    persistFocusPlanning()
  }

  private func earliestFocusAssignment(for taskID: UUID) -> Date? {
    focusPlanning.plans.values
      .flatMap(\.assignments)
      .filter { $0.taskID == taskID }
      .map { Date(timeIntervalSince1970: Double($0.blockStartAtMs) / 1_000) }
      .min()
  }

  private func refreshFocusTaskSchedule(for taskID: UUID) {
    guard var task = records.state.focusTasks.first(where: { $0.id == taskID }) else { return }
    task.scheduledStartAt = earliestFocusAssignment(for: taskID)
    if task.templateID != nil {
      task.estimatedPomodoros = templateTaskEstimate(for: taskID)
    }
    records.upsertFocusTask(task)
  }

  /// A template task's estimate follows the live plan, but a restored
  /// history can already contain more completed rounds than that plan.
  /// Never make a completed task look unfinished by shrinking below either
  /// its durable completion count or one visible Pomodoro.
  private func templateTaskEstimate(for taskID: UUID) -> Int {
    max(
      1,
      records.state.focusSessions.count {
        $0.taskID == taskID && $0.kind == .focus && $0.endReason == .completed
      },
      focusPlanning.plans.values.flatMap(\.assignments).count { $0.taskID == taskID }
    )
  }

  private func focusTemplatePlanMatches(
    _ template: FocusTemplate,
    blocks: [FocusWorkBlock],
    dayKey: String,
    anchor: Date
  ) -> Bool {
    guard let plan = focusPlanning.plans[dayKey], plan.appliedTemplateID == template.id else {
      return false
    }
    let expected = template.placedSlots(in: blocks).compactMap {
      slot -> (FocusTemplateSlot, FocusWorkBlock)? in
      guard blocks.indices.contains(slot.blockIndex) else { return nil }
      let block = blocks[slot.blockIndex]
      return slot.kind == .breakTime || block.kind == .task ? (slot, block) : nil
    }
    guard plan.assignments.count == expected.count else { return false }

    for (slot, block) in expected {
      guard
        let assignment = plan.assignments.first(where: { $0.blockStartAtMs == block.startAtMs }),
        assignment.kind == slot.kind
      else { return false }
      guard slot.kind == .task else {
        if assignment.taskID != nil { return false }
        continue
      }
      guard let taskID = assignment.taskID,
        let task = records.state.focusTasks.first(where: { $0.id == taskID }),
        task.deletedAt == nil,
        task.templateID == template.id,
        task.templateTaskKey == slot.taskKey,
        let plannedForDate = task.plannedForDate,
        recordsCalendar.isDate(plannedForDate, inSameDayAs: anchor)
      else { return false }
      guard assignment.taskTitle == task.title,
        assignment.taskIcon == task.icon,
        slot.taskTitle.map({ $0 == task.title }) ?? true,
        slot.taskIcon.map({ $0 == task.icon }) ?? true
      else { return false }
    }
    return true
  }

  /// Finds the task materialized by this template for this specific shift.
  /// Reusing a soft-deleted row preserves its CloudKit identity and makes a
  /// clear followed by Apply reversible.  Templates applied on another day
  /// deliberately receive their own tasks.
  private func reusableTemplateTask(
    _ template: FocusTemplate,
    slot: FocusTemplateSlot,
    anchor: Date,
    block: FocusWorkBlock,
    includingCompleted: Bool = false
  ) -> FocusTask? {
    records.state.focusTasks
      .filter { task in
        guard task.templateID == template.id,
          includingCompleted || task.completedAt == nil,
          let plannedForDate = task.plannedForDate,
          recordsCalendar.isDate(plannedForDate, inSameDayAs: anchor)
        else { return false }
        if let taskKey = slot.taskKey {
          return task.templateTaskKey == taskKey
        }
        // Key-less v1 templates had one task per slot.  A soft-deleted
        // row retains its original scheduled slot so it can still be
        // recovered without conflating neighbouring legacy slots.
        return task.templateTaskKey == nil && task.scheduledStartAt == block.start
      }
      .sorted { lhs, rhs in
        if (lhs.deletedAt == nil) != (rhs.deletedAt == nil) { return lhs.deletedAt == nil }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .first
  }

  /// Turns a removed template assignment into either a reversible soft
  /// deletion or an ordinary user task.  Durable history, a favourite, or a
  /// remaining plan reference is evidence that the task has meaning beyond
  /// this template and must never disappear with it.
  private func releaseTemplateTasks(
    _ taskIDs: Set<UUID>,
    preserving preservedTaskIDs: Set<UUID> = [],
    at date: Date
  ) {
    for taskID in taskIDs where !preservedTaskIDs.contains(taskID) {
      guard var task = records.state.focusTasks.first(where: { $0.id == taskID }),
        task.templateID != nil
      else { continue }
      let hasSessionHistory = records.state.focusSessions.contains { $0.taskID == taskID }
      let hasPlanReference = focusPlanning.plans.values.contains {
        $0.assignments.contains { $0.taskID == taskID }
      }
      if hasSessionHistory || task.isFavorite || hasPlanReference {
        task.templateID = nil
        task.templateTaskKey = nil
        task.scheduledStartAt = earliestFocusAssignment(for: taskID)
      } else if task.deletedAt == nil {
        // Keep the old slot on a tombstone.  It is invisible to the
        // user, while allowing a legacy key-less template to revive
        // the exact task if they immediately apply it again.
        task.deletedAt = date
      } else {
        continue
      }
      records.upsertFocusTask(task, at: date)
    }
  }

  /// Not private: the template editor in `FocusStore+Templates`
  /// writes slots the user drew rather than slots derived from today.
  func persistFocusPlanning() {
    persistFocusConfiguration()
  }

  private func persistFocusConfiguration(at date: Date = .now) {
    let current = records.state.focusPlanningConfiguration
    guard
      current?.planning != focusPlanning
        || current?.timerSettings != focusTimerSettings.normalized
    else { return }
    records.upsertFocusPlanningConfiguration(
      FocusPlanningConfiguration(
        planning: focusPlanning,
        timerSettings: focusTimerSettings.normalized,
        editedAt: current?.editedAt ?? date,
        editCount: current?.editCount ?? 0,
        editTieBreaker: current?.editTieBreaker ?? UUID()
      ),
      at: date
    )
    mirrorFocusConfigurationToLegacyDefaults()
    focusPlanningRevision &+= 1
  }

  private func mirrorFocusConfigurationToLegacyDefaults() {
    if let planningData = try? JSONEncoder().encode(focusPlanning) {
      defaults.set(planningData, forKey: Key.focusPlanning)
    }
    if let settingsData = try? JSONEncoder().encode(focusTimerSettings.normalized) {
      defaults.set(settingsData, forKey: Key.focusTimerSettings)
    }
  }

  /// Focus appointments remain meaningful when no work shift is running.
  /// Shared by the app timeline and its salary-free widget projection.
  func focusUpcomingTimelineEvents(
    for snapshot: NativeShiftSnapshot?,
    at now: Date = .now
  ) -> [UpcomingTimelineEvent] {
    var events: [UpcomingTimelineEvent] = []
    if plus.isAuthorized {
      if let session = activeFocusSession(), session.plannedEndAt > now {
        let icon = session.taskID
          .flatMap { id in records.state.focusTasks.first(where: { $0.id == id }) }
          .map { $0.icon.systemName }
        events.append(
          .init(
            id: "focus-session-\(session.id.uuidString)",
            kind: .focus,
            date: session.plannedEndAt,
            title: t("focusRunning"),
            detail: t("focusEndsAt", values: ["time": formatTime(session.plannedEndAt)]),
            symbolName: icon
          ))
      }

      let horizon = now.addingTimeInterval(2 * 86_400)
      let planned = (snapshot.map { focusPlanAssignments(for: $0) } ?? []).filter {
        $0.block.start > now && $0.block.start <= horizon
      }
      let plannedTaskIDs = Set(planned.compactMap { $0.assignment.taskID })
      for item in planned {
        let isBreak = item.assignment.kind == .breakTime
        events.append(
          .init(
            id: "focus-plan-\(item.assignment.blockStartAtMs)",
            kind: isBreak ? .focusBreak : .focus,
            date: item.block.start,
            title: isBreak
              ? t("focusBreak")
              : (item.assignment.taskTitle ?? t("focusTitle")),
            detail: t(
              "focusPomodoroSummary",
              values: [
                "count": formatCount(1),
                "minutes": formatCount(item.block.durationMinutes),
              ]
            ),
            symbolName: isBreak ? "cup.and.saucer.fill" : item.assignment.taskIcon?.systemName
          ))
      }

      for task in records.state.focusTasks where task.completedAt == nil && task.deletedAt == nil {
        guard !plannedTaskIDs.contains(task.id),
          let start = task.scheduledStartAt,
          start > now,
          start <= horizon
        else { continue }
        events.append(
          .init(
            id: "focus-task-\(task.id.uuidString)",
            kind: .focus,
            date: start,
            title: task.title,
            detail: t(
              "focusPomodoroSummary",
              values: [
                "count": formatCount(max(1, task.estimatedPomodoros)),
                "minutes": formatCount(focusTimerSettings.normalized.focusMinutes),
              ]
            ),
            symbolName: task.icon.systemName
          ))
      }
    }

    return events.sorted { $0.date < $1.date }
  }

  func carryIncompleteFocusTasks(at date: Date) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        let today = recordsCalendar.startOfDay(for: date)
        for task in records.state.focusTasks where task.completedAt == nil && task.deletedAt == nil
        {
          guard let planned = task.plannedForDate, planned < today else { continue }
          var next = task
          next.plannedForDate = today
          next.scheduledStartAt = nil
          records.upsertFocusTask(next)
        }
      }
    }
  }

  /// Not private: the placement helpers in `FocusStore+Placement`
  /// re-check entitlement themselves and then need the task back to put it
  /// somewhere. The name is the contract.
  @discardableResult
  func addAndStartFocusTaskAuthorized(
    title: String,
    pomodoros: Int,
    icon: FocusTaskIcon = .focus,
    isFavorite: Bool = false,
    at date: Date = .now
  ) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        let task = addFocusTaskAuthorized(
          title: title, pomodoros: pomodoros,
          plannedFor: date, icon: icon, isFavorite: isFavorite
        ).synchronousResult
        return startFocusAuthorized(task, at: date).synchronousResult
      }
    }
  }

  @discardableResult
  func addFocusTaskAuthorized(
    title: String,
    pomodoros: Int,
    plannedFor: Date? = nil,
    scheduledStartAt: Date? = nil,
    icon: FocusTaskIcon = .focus,
    isFavorite: Bool = false
  ) -> RecordCommand<FocusTask> {
    records.submitCommand { [self] in
      let nextIndex = (records.state.focusTasks.map(\.sortIndex).max() ?? -1) + 1
      let task = FocusTask(
        id: UUID(),
        createdAt: .now,
        plannedForDate: recordsCalendar.startOfDay(for: plannedFor ?? .now),
        scheduledStartAt: scheduledStartAt,
        title: title,
        estimatedPomodoros: max(1, pomodoros),
        icon: icon,
        isFavorite: isFavorite,
        completedAt: nil,
        sortIndex: nextIndex,
        editedAt: .now,
        editCount: 0,
        editTieBreaker: UUID()
      )
      records.upsertFocusTask(task)
      return task
    }
  }

  func focusTasksForToday(at date: Date = .now) -> [FocusTask] {
    let today = focusTaskDay(at: date)
    return FocusTaskOrder.sorted(
      records.state.focusTasks.filter { task in
        guard task.deletedAt == nil, !(task.isFavorite && task.plannedForDate == nil) else {
          return false
        }
        guard let planned = task.plannedForDate else { return true }
        return recordsCalendar.isDate(planned, inSameDayAs: today)
      })
  }

  /// The Focus page includes the next scheduled task as well as today's
  /// work. A task created for tomorrow used to disappear immediately after
  /// the add sheet pushed this page, because the page only queried today.
  func focusTasksForFocusPage(at date: Date = .now) -> [FocusTask] {
    let today = focusTaskDay(at: date)
    let tomorrow =
      recordsCalendar.date(byAdding: .day, value: 1, to: recordsCalendar.startOfDay(for: date))
      ?? date
    return records.state.focusTasks.filter { task in
      guard task.deletedAt == nil, !(task.isFavorite && task.plannedForDate == nil) else {
        return false
      }
      if task.completedAt == nil {
        return task.plannedForDate.map { $0 >= today } ?? true
      }
      return task.completedAt.map { $0 >= today && $0 < tomorrow } ?? false
    }.sorted { lhs, rhs in
      let lhsDate = lhs.scheduledStartAt ?? lhs.plannedForDate ?? lhs.createdAt
      let rhsDate = rhs.scheduledStartAt ?? rhs.plannedForDate ?? rhs.createdAt
      if lhsDate != rhsDate { return lhsDate < rhsDate }
      if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// A night shift's task list stays on its start day across midnight.
  /// Future planning must still include unfinished tasks from today.
  private func focusTaskDay(at date: Date) -> Date {
    let shiftStart = focusCanvasShift(at: date)?.snapshot.startDate ?? date
    return recordsCalendar.startOfDay(for: min(date, shiftStart))
  }

  /// Blocks finished for a task, so the estimate the user typed has something
  /// to be measured against on screen.
  func completedFocusBlocks(for task: FocusTask) -> Int {
    records.state.focusSessions.count(where: {
      $0.taskID == task.id && $0.kind == .focus && $0.endReason == .completed
    })
  }

  func focusSessions(forDayKey dayKey: String) -> [FocusSession] {
    records.state.focusSessions
      .filter {
        ($0.anchorDayKey ?? RecordJSON.dayKey($0.shiftAnchorDate, calendar: recordsCalendar))
          == dayKey
      }
      .sorted {
        if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
        return $0.id.uuidString < $1.id.uuidString
      }
  }

  func favoriteFocusTasks() -> [FocusTask] {
    FocusTaskOrder.sorted(records.state.focusTasks.filter { $0.deletedAt == nil && $0.isFavorite })
  }

  func savedFocusFavorite(title: String, icon: FocusTaskIcon) -> FocusTask? {
    favoriteFocusTasks().first { $0.title == title && $0.icon == icon }
  }

  /// A library-only task has no planned day. It appears in the picker, not
  /// today's work or completion calculation, until the user places a copy.
  func saveFocusFavorite(title: String, pomodoros: Int, icon: FocusTaskIcon) -> RecordCommand<Void>
  {
    records.submitCommand { [self] in
      guard plus.isAuthorized else { return }
      if var existing = savedFocusFavorite(title: title, icon: icon) {
        existing.estimatedPomodoros = max(1, pomodoros)
        records.upsertFocusTask(existing)
        return
      }
      let task = FocusTask(
        id: UUID(), createdAt: .now, plannedForDate: nil,
        scheduledStartAt: nil, title: title, estimatedPomodoros: max(1, pomodoros),
        icon: icon, isFavorite: true, completedAt: nil, sortIndex: 0,
        editedAt: .now, editCount: 0, editTieBreaker: UUID())
      records.upsertFocusTask(task)
    }
  }

  func toggleFocusFavorite(_ task: FocusTask) -> RecordCommand<Void> {
    let taskID = task.id
    return records.submitCommand { [self] in
      guard let task = records.state.focusTasks.first(where: { $0.id == taskID }),
        task.deletedAt == nil
      else { return }
      var next = task
      next.isFavorite.toggle()
      if !next.isFavorite, next.plannedForDate == nil {
        next.deletedAt = .now
      }
      records.upsertFocusTask(next)
    }
  }

  @discardableResult
  func applyFavoriteFocusTask(_ task: FocusTask, at date: Date = .now) -> RecordCommand<FocusTask?>
  {
    let taskID = task.id
    return records.submitCommand { [self] in
      guard plus.isAuthorized,
        let task = records.state.focusTasks.first(where: { $0.id == taskID && $0.deletedAt == nil })
      else { return nil }
      return addFocusTaskAuthorized(
        title: task.title,
        pomodoros: task.estimatedPomodoros,
        plannedFor: date,
        icon: task.icon
      ).synchronousResult
    }
  }

  func detachFocusTemplate(at date: Date = .now) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      guard let shift = focusCanvasShift(at: date)?.snapshot else { return }
      let key = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
      guard focusPlanning.plans[key]?.appliedTemplateID != nil else { return }
      focusPlanning.plans[key]?.appliedTemplateID = nil
      focusPlanning.autoAppliedDayKeys.insert(key)
      persistFocusPlanning()
    }
  }

  func appliedFocusTemplate(at date: Date = .now) -> FocusTemplate? {
    guard let shift = focusCanvasShift(at: date)?.snapshot else { return nil }
    let key = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
    guard let id = focusPlanning.plans[key]?.appliedTemplateID else { return nil }
    return focusPlanning.templates.first { $0.id == id }
  }

  /// Completed and running rounds cannot be removed by changing an estimate.
  func protectedFocusPomodoros(_ task: FocusTask, at date: Date = .now) -> Int {
    let running = activeFocusSession().flatMap {
      $0.taskID == task.id && $0.kind == .focus ? $0 : nil
    }
    let runningEnd = activeFocusSession().map {
      Int64($0.plannedEndAt.timeIntervalSince1970 * 1_000)
    }
    let fixed = focusDayCanvas(at: date).blocks.filter { block in
      block.taskID == task.id
        && (block.state == .past || runningEnd.map { block.startAtMs < $0 } == true)
    }
    return max(fixed.count, completedFocusBlocks(for: task) + (running == nil ? 0 : 1))
  }

  func editedFocusTaskBlocks(_ task: FocusTask, pomodoros: Int, at date: Date = .now)
    -> [FocusDayCanvasModel.Block]?
  {
    let canvas = focusDayCanvas(at: date)
    let owned = canvas.blocks.filter { $0.taskID == task.id }
    let consumed = protectedFocusPomodoros(task, at: date)
    guard pomodoros >= max(1, consumed) else { return nil }
    guard !owned.isEmpty else { return [] }
    let runningEnd = activeFocusSession().map {
      Int64($0.plannedEndAt.timeIntervalSince1970 * 1_000)
    }
    let fixed = owned.filter { block in
      block.state == .past || runningEnd.map { block.startAtMs < $0 } == true
    }
    let editable = canvas.blocks.filter { block in
      block.isEditable && (runningEnd.map { block.startAtMs >= $0 } ?? true)
    }
    let start =
      editable.first(where: { $0.taskID == task.id })?.startAtMs
      ?? editable.first(where: { !$0.hasAssignment })?.startAtMs
    let remaining = pomodoros - consumed
    let next =
      start.map {
        FocusLiveChain.projectedBlocks(
          taskID: task.id, remaining: remaining, blocks: editable, fromMs: $0)
      } ?? []
    guard next.count == remaining else { return nil }
    return fixed + next
  }

  @discardableResult
  func editFocusTask(
    _ task: FocusTask, title: String, icon: FocusTaskIcon, pomodoros: Int,
    isFavorite: Bool, at date: Date = .now
  ) -> RecordCommand<Bool> {
    let taskID = task.id
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !title.isEmpty,
          var next = records.state.focusTasks.first(where: {
            $0.id == taskID && $0.deletedAt == nil
          })
        else { return false }
        let oldFavorite = savedFocusFavorite(title: next.title, icon: next.icon)
        let changed =
          next.title != title || next.icon != icon || next.estimatedPomodoros != pomodoros
        if next.estimatedPomodoros != pomodoros {
          guard let blocks = editedFocusTaskBlocks(next, pomodoros: pomodoros, at: date),
            let shift = focusCanvasShift(at: date)?.snapshot
          else { return false }
          let key = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
          if focusPlanning.plans[key]?.assignments.contains(where: { $0.taskID == next.id }) == true
          {
            focusPlanning.plans[key]?.assignments.removeAll { $0.taskID == next.id }
            focusPlanning.plans[key]?.assignments.append(
              contentsOf: blocks.map {
                FocusPlanAssignment(
                  blockStartAtMs: $0.startAtMs, kind: .task, taskID: next.id,
                  taskTitle: title, taskIcon: icon)
              })
          }
          if pomodoros > completedFocusBlocks(for: next) { next.completedAt = nil }
        }
        next.title = title
        next.icon = icon
        next.estimatedPomodoros = pomodoros
        if next.isFavorite { next.isFavorite = isFavorite }
        records.upsertFocusTask(next, at: date)
        if changed {
          for key in focusPlanning.plans.keys {
            guard var plan = focusPlanning.plans[key],
              plan.assignments.contains(where: { $0.taskID == next.id })
            else { continue }
            plan.appliedTemplateID = nil
            focusPlanning.autoAppliedDayKeys.insert(key)
            for index in plan.assignments.indices where plan.assignments[index].taskID == next.id {
              plan.assignments[index].taskTitle = title
              plan.assignments[index].taskIcon = icon
            }
            plan.assignments.sort { $0.blockStartAtMs < $1.blockStartAtMs }
            focusPlanning.plans[key] = plan
          }
          refreshFocusTaskSchedule(for: next.id)
          persistFocusPlanning()
        }
        if isFavorite {
          if var favorite = oldFavorite, favorite.id != next.id {
            favorite.title = title
            favorite.icon = icon
            favorite.estimatedPomodoros = pomodoros
            records.upsertFocusTask(favorite, at: date)
          } else if oldFavorite == nil {
            saveFocusFavorite(title: title, pomodoros: pomodoros, icon: icon).synchronousResult
          }
        } else if let favorite = oldFavorite, favorite.id != next.id {
          toggleFocusFavorite(favorite).synchronousResult
        }
        return true
      }
    }
  }

  func clearFocusDay(at date: Date = .now) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        guard plus.isAuthorized, let shift = focusCanvasShift(at: date)?.snapshot else { return }
        let key = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
        let assigned = Set(focusPlanning.plans[key]?.assignments.compactMap(\.taskID) ?? [])
        let tasks = records.state.focusTasks.filter { task in
          task.deletedAt == nil
            && (assigned.contains(task.id)
              || task.plannedForDate.map {
                recordsCalendar.isDate($0, inSameDayAs: shift.startDate)
              } == true)
        }
        if let session = activeFocusSession(),
          recordsCalendar.isDate(session.shiftAnchorDate, inSameDayAs: shift.startDate)
        {
          stopFocus(reason: .stoppedByUser, at: date).synchronousResult
        }
        focusPlanning.plans[key] = FocusDayPlan(
          dayKey: key, shiftStartAtMs: Int64(shift.startAtMs),
          assignments: [], appliedTemplateID: nil)
        focusPlanning.autoAppliedDayKeys.insert(key)
        for var task in tasks {
          if task.isFavorite {
            task.plannedForDate = nil
            task.scheduledStartAt = nil
          } else {
            task.deletedAt = date
          }
          records.upsertFocusTask(task, at: date)
        }
        persistFocusPlanning()
      }
    }
  }

  @discardableResult
  func deleteFocusTask(_ task: FocusTask, at date: Date = .now) -> RecordCommand<Bool> {
    let taskID = task.id
    return records.submitCommand { [self] in
      records.withBatchedWrites {
        guard var next = records.state.focusTasks.first(where: { $0.id == taskID }),
          next.deletedAt == nil,
          activeFocusSession()?.taskID != taskID
        else { return false }
        next.deletedAt = date
        records.upsertFocusTask(next, at: date)
        for key in focusPlanning.plans.keys
        where focusPlanning.plans[key]?.assignments.contains(where: { $0.taskID == taskID }) == true
        {
          focusPlanning.plans[key]?.assignments.removeAll { $0.taskID == taskID }
          focusPlanning.plans[key]?.appliedTemplateID = nil
          focusPlanning.autoAppliedDayKeys.insert(key)
        }
        persistFocusPlanning()
        return true
      }
    }
  }

  func focusOverflow() -> [FocusTask] {
    let remaining = Int64(snapshot(at: .now)?.remainingMs ?? 0)
    return FocusPlanner.remainingPomodoros(
      tasks: focusTasksForToday(),
      remainingWorkMs: remaining,
      completedBlocks: { completedFocusBlocks(for: $0) },
      settings: focusTimerSettings
    ).overflow
  }

  /// Deterministic even before reconciliation completes. CloudKit can
  /// briefly deliver two open rows; selecting by stable keys avoids each
  /// device showing a different timer.
  // Local launch commitments, separate from completed/synced history. Merely
  // opening the app after an unarmed block passed must never invent a session.
  private var scheduledFocusSessions: [FocusSession] {
    get {
      guard let data = defaults.data(forKey: "ios.native.scheduledFocusSessions"),
        let values = try? JSONDecoder().decode([FocusSessionDTO].self, from: data)
      else { return [] }
      return values.compactMap { $0.value(calendar: recordsCalendar) }
    }
    set {
      let values = newValue.map { FocusSessionDTO($0, calendar: recordsCalendar) }
      defaults.set(try? JSONEncoder().encode(values), forKey: "ios.native.scheduledFocusSessions")
    }
  }
  @ObservationIgnored private var scheduledFocusWake: Task<Void, Never>?

  /// Completion copy must not claim that an unassigned or unfinished task
  /// was done. Only committed blocks and the current block count ahead.
  func completesFocusDay(after session: FocusSession, at date: Date) -> Bool {
    let pending = scheduledFocusSessions
    let tasks = focusTasksForToday(at: date)
    return tasks.allSatisfy { task in
      if task.completedAt != nil { return true }
      let committed = pending.filter {
        $0.taskID == task.id && $0.plannedEndAt <= session.plannedEndAt
      }.count
      let current =
        session.endedAt == nil && session.kind == .focus && session.taskID == task.id
          && session.plannedEndReason == .completed
          && !pending.contains(where: { $0.id == session.id }) ? 1 : 0
      let running = records.state.focusSessions.filter { recorded in
        recorded.id != session.id && recorded.taskID == task.id && recorded.kind == .focus
          && recorded.endedAt == nil && recorded.plannedEndReason == .completed
          && recorded.plannedEndAt <= session.plannedEndAt
          && !pending.contains(where: { $0.id == recorded.id })
      }.count
      return completedFocusBlocks(for: task) + committed + current + running
        >= max(1, task.estimatedPomodoros)
    }
  }

  func focusDayComplete(at date: Date = .now) -> Bool {
    guard activeFocusSession() == nil,
      let last = focusSessions(forDayKey: RecordJSON.dayKey(date, calendar: recordsCalendar))
        .filter({ $0.endedAt != nil }).max(by: { $0.startedAt < $1.startedAt })
    else { return false }
    return completesFocusDay(after: last, at: date)
  }

  func scheduledFocusCount(taskID: UUID, before date: Date) -> Int {
    scheduledFocusSessions.filter { $0.taskID == taskID && $0.plannedEndAt <= date }.count
      + records.state.focusSessions.filter {
        $0.taskID == taskID && $0.endedAt == nil && $0.plannedEndAt <= date
      }.count
  }

  @discardableResult
  func stopFocusFromActivity(startAtMs: Int64, at date: Date = .now) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      restoreScheduledFocus(at: date).synchronousResult
      _ = finishElapsedFocusSession(at: date).synchronousResult
      guard let session = activeFocusSession(), session.kind == .focus,
        Int64(session.startedAt.timeIntervalSince1970 * 1_000) == startAtMs
      else { return false }
      stopFocus(reason: .stoppedByUser, at: date).synchronousResult
      return true
    }
  }

  /// Consume only starts that were committed before suspension. Record their
  /// absolute intervals, so waking late cannot restart a 25-minute block.
  func restoreScheduledFocus(at date: Date = .now) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      let queued = scheduledFocusSessions
      scheduledFocusSessions = queued.filter { $0.startedAt > date }
      for session in queued where session.startedAt <= date {
        guard plus.isAuthorized,
          let task = records.state.focusTasks.first(where: { $0.id == session.taskID }),
          task.deletedAt == nil, task.completedAt == nil,
          !records.state.focusSessions.contains(where: { $0.id == session.id }),
          focusDayCanvas(at: session.startedAt).blocks.contains(where: {
            $0.taskID == session.taskID && !$0.isUserBreak
              && $0.startAtMs <= Int64(session.startedAt.timeIntervalSince1970 * 1_000)
              && $0.endAtMs == Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
          })
        else { continue }
        while let running = activeFocusSession(), running.plannedEndAt <= session.startedAt {
          _ = finishElapsedFocusSession(at: session.startedAt).synchronousResult
        }
        // A manually started block already owns this time. Recovery may
        // yield to a task the user explicitly placed in the schedule.
        if let running = activeFocusSession() {
          guard running.kind != .focus else { continue }
          stopFocus(reason: .stoppedAtBoundary, at: session.startedAt).synchronousResult
        }
        records.upsertFocusSession(session, at: session.startedAt)
        focusLastNextAction = .none
        if session.plannedEndAt <= date {
          _ = finishElapsedFocusSession(at: date).synchronousResult
        } else {
          scheduleFocusExpiry(for: session).synchronousResult
          scheduleFocusTimerNotification(for: session)
        }
      }
    }
  }

  /// Assignment is authorization. Prepare today's remaining assigned blocks
  /// while the app can run; ActivityKit receives the same absolute sessions.
  @discardableResult
  func refreshScheduledFocus(at date: Date = .now) -> RecordCommand<[FocusSession]> {
    records.submitCommand { [self] in
      restoreScheduledFocus(at: date).synchronousResult
      let previous = scheduledFocusSessions
      let canvas = focusDayCanvas(at: date)
      let sessions: [FocusSession] =
        plus.isAuthorized
        ? canvas.blocks.compactMap { block in
          guard block.kind == .task, !block.isUserBreak,
            block.endAtMs > Int64(date.timeIntervalSince1970 * 1_000),
            let taskID = block.taskID,
            let task = records.state.focusTasks.first(where: { $0.id == taskID }),
            task.completedAt == nil, task.deletedAt == nil
          else { return nil }
          let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
          let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
          guard
            !records.state.focusSessions.contains(where: {
              $0.kind == .focus && $0.startedAt < end && $0.plannedEndAt > start
            })
          else { return nil }
          if let existing = previous.first(where: {
            $0.taskID == taskID && $0.startedAt == start && $0.plannedEndAt == end
          }) {
            return existing
          }
          let actualStart = max(start, date)
          guard end.timeIntervalSince(actualStart) >= 60 else { return nil }
          return FocusSession(
            id: FocusSessionIdentity.block(
              taskID: taskID, startAtMs: block.startAtMs, endAtMs: block.endAtMs),
            taskID: taskID,
            shiftAnchorDate: recordsCalendar.startOfDay(for: actualStart),
            startedAt: actualStart, plannedEndAt: end,
            endedAt: nil, endReason: nil, editedAt: date,
            editCount: 0, editTieBreaker: UUID(), kind: .focus,
            timeZoneIdentifier: recordsCalendar.timeZone.identifier,
            plannedEndReason: .completed
          )
        } : []
      scheduledFocusSessions = sessions
      restoreScheduledFocus(at: date).synchronousResult
      scheduledFocusWake?.cancel()
      if let next = scheduledFocusSessions.first {
        scheduledFocusWake = Task { @MainActor [weak self] in
          do {
            try await Task.sleep(for: .seconds(max(0, next.startedAt.timeIntervalSinceNow)))
          } catch { return }
          guard let self, !Task.isCancelled else { return }
          self.refreshScheduledFocus()
        }
      }
      return scheduledFocusSessions
    }
  }

  func activeFocusSession() -> FocusSession? {
    records.state.focusSessions.filter { $0.endedAt == nil }.min {
      if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  var focusRejectedNoRoom = false
  private(set) var focusLastNextAction: FocusNextAction = .none
  private(set) var focusNotificationIssue: FocusNotificationIssue?
  @ObservationIgnored private var focusNotificationGeneration: UInt64 = 0
  @ObservationIgnored private var isReconcilingFocusSessions = false

  func isWithinFocusWorkTime(at date: Date = .now) -> Bool {
    guard shouldQuerySnapshot(at: date), let shift = snapshot(at: date) else { return false }
    return FocusPlanner.isInsideWork(
      at: date, segments: shift.segments, overtimeEndAtMs: overtimeEndAtMs)
  }

  /// Same room check `startFocus` uses, so the button can disable before
  /// a tap that would only be rejected.
  func hasFocusRoom(at date: Date = .now) -> Bool {
    guard shouldQuerySnapshot(at: date) else { return false }
    let current = snapshot(at: date)
    guard let current, isFocusWorkday(current, at: date) else { return false }
    let segments = current.segments
    guard
      FocusPlanner.isInsideWork(
        at: date,
        segments: segments,
        overtimeEndAtMs: overtimeEndAtMs
      )
    else { return false }
    if current.remainingMs < 60_000 { return false }
    let planned = FocusPlanner.plannedEnd(
      from: date,
      segments: segments,
      overtimeEndAtMs: overtimeEndAtMs,
      durationMinutes: focusTimerSettings.normalized.focusMinutes
    )
    return planned.timeIntervalSince(date) >= 60
  }

  /// Both current UI and imported legacy tasks may have a planned civil day
  /// without an exact slot. Treat that day as a real start boundary rather
  /// than allowing an unslotted tomorrow task to start today.
  private func focusTaskUnavailableUntil(_ task: FocusTask, at date: Date) -> Date? {
    // An exact slot is stronger than its containing civil day. Checking
    // the day first made a task planned for tomorrow at 09:00 available at
    // 00:00, and the UI exposed that wrong boundary as “During 12:00 AM”.
    if let scheduled = task.scheduledStartAt, scheduled > date { return scheduled }
    let today = recordsCalendar.startOfDay(for: date)
    if let planned = task.plannedForDate {
      let plannedDay = recordsCalendar.startOfDay(for: planned)
      if plannedDay > today { return plannedDay }
    }
    return nil
  }

  func breakDurationMinutes(_ kind: FocusSessionKind) -> Int {
    kind == .shortBreak
      ? focusTimerSettings.normalized.shortBreakMinutes
      : focusTimerSettings.normalized.longBreakMinutes
  }

  /// Uses exactly the same segment and micro-break constraints as an actual
  /// break start. Keeping this separate lets the completed-focus state avoid
  /// advertising a recovery phase that cannot be entered.
  func plannedFocusBreakEnd(kind: FocusSessionKind, at date: Date) -> Date? {
    guard kind == .shortBreak || kind == .longBreak else { return nil }
    guard sources.scheduleEnabled(date) else { return nil }
    let current = snapshot(at: date)
    guard let current, isFocusWorkday(current, at: date) else { return nil }
    guard
      FocusPlanner.isInsideWork(
        at: date,
        segments: current.segments,
        overtimeEndAtMs: overtimeEndAtMs
      )
    else { return nil }
    let planned = FocusPlanner.plannedEnd(
      from: date,
      segments: current.segments,
      overtimeEndAtMs: overtimeEndAtMs,
      durationMinutes: breakDurationMinutes(kind)
    )
    let block = focusWorkBlocks(at: date).first {
      $0.kind == .breakTime && $0.start <= date && date < $0.end
    }
    let end = min(block?.end ?? planned, planned)
    return end.timeIntervalSince(date) >= 60 ? end : nil
  }

  func focusStartAvailability(_ task: FocusTask, at date: Date = .now) -> FocusStartAvailability {
    if task.completedAt != nil || task.deletedAt != nil { return .completed }
    if let unavailableUntil = focusTaskUnavailableUntil(task, at: date) {
      return .notYetAvailable(unavailableUntil)
    }
    if let session = activeFocusSession() {
      return session.taskID == task.id ? .running : .blockedByOther
    }
    return hasFocusRoom(at: date) ? .ready : .noRoom
  }

  /// Returns whether a block actually started. The view fires haptics from
  /// this, not from the tap — a disabled-looking Start that still buzzed
  /// and then did nothing was the previous behaviour.
  @discardableResult
  func startFocus(task: FocusTask) -> RecordCommand<Bool> {
    let taskID = task.id
    return records.submitCommand { [self] in
      guard let task = records.state.focusTasks.first(where: { $0.id == taskID }) else {
        return false
      }
      if plus.isAuthorized {
        return startFocusAuthorized(task).synchronousResult
      }
      return false
    }
  }

  @discardableResult
  func startFocusAuthorized(_ task: FocusTask, at start: Date = .now, blockEnd: Date? = nil)
    -> RecordCommand<Bool>
  {
    let taskID = task.id
    return records.submitCommand { [self] in
      guard let task = records.state.focusTasks.first(where: { $0.id == taskID }) else {
        return false
      }
      guard activeFocusSession() == nil, task.completedAt == nil, task.deletedAt == nil else {
        return false
      }
      guard focusTaskUnavailableUntil(task, at: start) == nil else { return false }
      guard hasFocusRoom(at: start) else {
        focusRejectedNoRoom = true
        return false
      }
      focusRejectedNoRoom = false
      let current = snapshot(at: start)
      let freeEnd = FocusPlanner.plannedEnd(
        from: start,
        segments: current?.segments ?? [],
        overtimeEndAtMs: overtimeEndAtMs,
        durationMinutes: focusTimerSettings.normalized.focusMinutes
      )
      let planned = min(blockEnd ?? freeEnd, freeEnd)
      guard planned.timeIntervalSince(start) >= 60 else { return false }
      focusLastNextAction = .none
      let timeZone = recordsCalendar.timeZone
      let session = FocusSession(
        id: UUID(),
        taskID: task.id,
        shiftAnchorDate: recordsCalendar.startOfDay(for: start),
        startedAt: start,
        plannedEndAt: planned,
        endedAt: nil,
        endReason: nil,
        editedAt: start,
        editCount: 0,
        editTieBreaker: UUID(),
        kind: .focus,
        timeZoneIdentifier: timeZone.identifier,
        anchorDayKey: RecordJSON.dayKey(start, calendar: recordsCalendar),
        actualDurationSeconds: nil,
        plannedEndReason: blockEnd == planned
          ? .completed
          : FocusPlanner.endReason(
            startedAt: start,
            plannedEndAt: planned,
            expectedDurationMinutes: focusTimerSettings.normalized.focusMinutes
          )
      )
      records.upsertFocusSession(session)
      scheduleFocusTimerNotification(for: session)
      scheduleFocusExpiry(for: session).synchronousResult
      return true
    }
  }

  /// A scheduled start consumes the remainder of that exact block.
  @discardableResult
  func startFocus(task: FocusTask, inBlockStartingAt blockStart: Int64, at date: Date = .now)
    -> RecordCommand<Bool>
  {
    let taskID = task.id
    return records.submitCommand { [self] in
      guard let task = records.state.focusTasks.first(where: { $0.id == taskID }) else {
        return false
      }
      guard plus.isAuthorized,
        let block = focusDayCanvas(at: date).blocks.first(where: { $0.startAtMs == blockStart }),
        block.state == .current, block.kind == .task, !block.isUserBreak,
        block.taskID == task.id
      else { return false }
      return startFocusAuthorized(
        task, at: date, blockEnd: Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
      ).synchronousResult
    }
  }

  func nextFocusBreakKind(after session: FocusSession) -> FocusSessionKind {
    let blocks = focusWorkBlocks(at: session.startedAt)
    if let index = blocks.firstIndex(where: {
      $0.kind == .task && $0.start <= session.startedAt && $0.end == session.plannedEndAt
    }), let next = blocks.dropFirst(index + 1).first, let kind = next.breakKind {
      return kind
    }
    let dayKey =
      session.anchorDayKey ?? RecordJSON.dayKey(session.shiftAnchorDate, calendar: recordsCalendar)
    let rounds =
      focusSessions(forDayKey: dayKey).count {
        $0.id != session.id && $0.kind == .focus && $0.endReason == .completed
      } + 1
    return rounds % focusTimerSettings.normalized.longBreakEvery == 0 ? .longBreak : .shortBreak
  }

  func canStartFocusBreak(kind: FocusSessionKind, at date: Date = .now) -> Bool {
    activeFocusSession() == nil && plannedFocusBreakEnd(kind: kind, at: date) != nil
  }

  @discardableResult
  func startBreak(kind: FocusSessionKind, at start: Date = .now, id: UUID? = nil) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      let requiredAction: FocusNextAction = kind == .shortBreak ? .startShortBreak : .startLongBreak
      guard kind == .shortBreak || kind == .longBreak,
        focusLastNextAction == requiredAction,
        activeFocusSession() == nil,
        let planned = plannedFocusBreakEnd(kind: kind, at: start)
      else { return false }
      let duration = breakDurationMinutes(kind)
      focusLastNextAction = .none
      let session = FocusSession(
        id: id ?? UUID(), taskID: nil,
        shiftAnchorDate: recordsCalendar.startOfDay(for: start),
        startedAt: start, plannedEndAt: planned, endedAt: nil, endReason: nil,
        editedAt: start, editCount: 0, editTieBreaker: UUID(), kind: kind,
        timeZoneIdentifier: recordsCalendar.timeZone.identifier,
        anchorDayKey: RecordJSON.dayKey(start, calendar: recordsCalendar),
        actualDurationSeconds: nil,
        plannedEndReason: FocusPlanner.endReason(
          startedAt: start, plannedEndAt: planned, expectedDurationMinutes: duration
        )
      )
      records.upsertFocusSession(session)
      scheduleFocusTimerNotification(for: session)
      scheduleFocusExpiry(for: session).synchronousResult
      return true
    }
  }

  func skipFocusPhase() -> RecordCommand<Void> {
    records.submitCommand { [self] in
      guard let session = activeFocusSession() else { return }
      stopFocus(reason: .stoppedByUser).synchronousResult
      if session.kind == .shortBreak || session.kind == .longBreak {
        focusLastNextAction = .startNextFocus
      }
    }
  }

  /// Skips a proposed recovery phase without manufacturing an immediately
  /// stopped break. This remains useful when a focus block ended at a lunch
  /// or clock-off boundary and there is no valid break interval to start.
  @discardableResult
  func skipSuggestedFocusBreak() -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      guard activeFocusSession() == nil,
        focusLastNextAction == .startShortBreak || focusLastNextAction == .startLongBreak
      else { return false }
      focusLastNextAction = .startNextFocus
      return true
    }
  }

  /// Every alert this phase owes the user, written when it starts.
  ///
  /// A pomodoro is not one event. The block ends, and then the break that
  /// follows it ends, and the phone is asleep for both — it cannot be woken
  /// at the first to compose the second. So the whole phase is described up
  /// front, and each alert names the task and what happens next instead of
  /// the bare "this focus block finished" that told the user nothing they
  /// could act on.
  func focusAlerts(for session: FocusSession) -> [NotificationService.FocusAlert] {
    switch session.kind {
    case .focus:
      var alerts = [focusBlockEndAlert(for: session)]
      if session.plannedEndReason == .completed,
        !completesFocusDay(after: session, at: session.startedAt)
      {
        let kind = nextFocusBreakKind(after: session)
        if let end = plannedFocusBreakEnd(kind: kind, at: session.plannedEndAt) {
          alerts.append(focusBreakEndAlert(endingAt: end))
        }
      }
      return alerts
    case .shortBreak, .longBreak:
      return [focusBreakEndAlert(endingAt: session.plannedEndAt)]
    }
  }

  private func focusBlockEndAlert(for session: FocusSession) -> NotificationService.FocusAlert {
    let task = session.taskID.flatMap { id in records.state.focusTasks.first(where: { $0.id == id })
    }
    var parts: [String] = []
    if let task {
      let index = completedFocusBlocks(for: task) + 1
      let total = max(index, max(1, task.estimatedPomodoros))
      parts.append(
        t(
          "focusActivityPomodoro",
          values: [
            "index": formatCount(index),
            "total": formatCount(total),
          ]))
    }
    if completesFocusDay(after: session, at: session.startedAt) {
      parts.append(t("focusActivityDayDone"))
    } else if session.plannedEndReason == .completed {
      let kind = nextFocusBreakKind(after: session)
      if let end = plannedFocusBreakEnd(kind: kind, at: session.plannedEndAt) {
        let minutes = breakDurationMinutes(kind)
        parts.append(
          t(
            "focusBreakUntil",
            values: [
              "count": formatCount(minutes),
              "time": formatTime(end),
            ]))
      } else {
        parts.append(t("focusEndedNaturally"))
      }
    } else {
      parts.append(t("focusEndedAtBoundary"))
    }
    return .init(
      slot: .end,
      at: session.plannedEndAt,
      title: task?.title ?? t("focusTitle"),
      body: parts.joined(separator: " · ")
    )
  }

  private func focusBreakEndAlert(endingAt end: Date) -> NotificationService.FocusAlert {
    let next = FocusLiveChain.nextPlannedBlock(
      blocks: focusDayCanvas(at: end).blocks,
      fromMs: Int64(end.timeIntervalSince1970 * 1_000)
    )
    let body: String
    if let next, let title = next.taskTitle {
      body = t(
        "focusActivityNextUp",
        values: [
          "task": title,
          "time": formatTime(Date(timeIntervalSince1970: Double(next.startAtMs) / 1_000)),
        ])
    } else {
      let done =
        activeFocusSession().map { completesFocusDay(after: $0, at: end) }
        ?? focusDayComplete(at: end)
      body = t(done ? "focusActivityDayDone" : "focusNextFocusBody")
    }
    return .init(slot: .breakEnd, at: end, title: t("focusBreakOver"), body: body)
  }

  @discardableResult
  private func scheduleFocusTimerNotification(for session: FocusSession) -> Task<Void, Never> {
    guard focusNotificationsEnabled else {
      NotificationService.cancelFocusTimer(id: session.id)
      return Task {}
    }
    focusNotificationGeneration &+= 1
    let generation = focusNotificationGeneration
    return Task { @MainActor [weak self] in
      guard let self else { return }
      do { try await self.records.flush() } catch { return }
      guard generation == self.focusNotificationGeneration,
        let current = self.activeFocusSession(), current.id == session.id,
        current.plannedEndAt == session.plannedEndAt
      else { return }
      let alerts = self.focusAlerts(for: current)
      let result = await NotificationService.scheduleFocusTimers(
        id: session.id,
        alerts: alerts,
        isCurrent: { [weak self] in
          guard let self else { return false }
          return NotificationService.mayMutateFocusNotificationChannel(
            requestGeneration: generation,
            currentGeneration: self.focusNotificationGeneration,
            requestID: session.id,
            activeSessionID: self.activeFocusSession()?.id
          )
        }
      )
      guard
        NotificationService.shouldKeepFocusNotification(
          requestGeneration: generation,
          currentGeneration: self.focusNotificationGeneration,
          requestID: session.id,
          activeSessionID: self.activeFocusSession()?.id
        )
      else {
        return
      }
      _ = await self.applyFocusNotificationResult(result, for: session.id).value
    }
  }

  /// Applies a system scheduling result only while the phase that requested
  /// it still owns the visible timer. Keeping this state transition separate
  /// makes the user-facing denied/failed/recovered states directly testable
  /// without prompting for real notification permission in a unit test.
  func applyFocusNotificationResult(
    _ result: NotificationService.FocusScheduleResult,
    for sessionID: UUID
  ) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      guard focusNotificationsEnabled, activeFocusSession()?.id == sessionID else { return }
      switch result {
      case .scheduled: focusNotificationIssue = nil
      case .permissionDenied: focusNotificationIssue = .permissionDenied
      case .failed: focusNotificationIssue = .schedulingFailed
      case .superseded: break
      }
    }
  }

  /// A visible, actionable retry for a denied/failed focus notification.
  /// It resubmits the current phase instead of merely refreshing OS status.
  func retryFocusNotification() -> RecordCommand<Void> {
    records.submitCommand { [self] in
      guard let session = activeFocusSession() else { return }
      scheduleFocusTimerNotification(for: session)
    }
  }

  /// An intent must finish publishing before iOS suspends its background run.
  func refreshFocusNotifications() async {
    let scheduling = await records.submitCommand { [self] in
      activeFocusSession().map(scheduleFocusTimerNotification)
    }.value
    await scheduling?.value
  }

  func scheduleFocusExpiry(for session: FocusSession) -> RecordCommand<Void> {
    let sessionID = session.id
    return records.submitCommand { [self] in
      guard
        let session = records.state.focusSessions.first(where: {
          $0.id == sessionID && $0.endedAt == nil
        })
      else { return }
      focusExpiryTask?.cancel()
      let end = session.plannedEndAt
      focusExpiryTask = Task { [weak self] in
        let delay = end.timeIntervalSinceNow
        if delay > 0 {
          try? await Task.sleep(for: .seconds(delay))
        }
        guard !Task.isCancelled else { return }
        guard let self else { return }
        _ = self.restoreScheduledFocus()
        _ = self.finishElapsedFocusSession()
      }
    }
  }

  func stopFocus(reason: FocusEndReason, at date: Date = .now, observedAt: Date? = nil)
    -> RecordCommand<Void>
  {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        guard var session = activeFocusSession() else { return }
        focusExpiryTask?.cancel()
        focusExpiryTask = nil
        focusNotificationGeneration &+= 1
        NotificationService.cancelFocusTimer(id: session.id)
        session.endedAt = date
        if let endedAt = session.endedAt {
          session.actualDurationSeconds = max(0, Int(endedAt.timeIntervalSince(session.startedAt)))
        }
        session.endReason = reason
        records.upsertFocusSession(session)
        focusNotificationIssue = nil
        focusLastNextAction = .none
        if session.kind != .focus {
          focusLastNextAction = .startNextFocus
          return
        }
        // A finished block is one completed session, not the whole task.
        // Marking `completedAt` on the first 25 minutes of a 2–12 block
        // estimate made the "1 / 2" row and the Done chip disagree.
        guard reason == .completed, session.kind == .focus, let taskID = session.taskID,
          var task = records.state.focusTasks.first(where: { $0.id == taskID })
        else { return }
        if completedFocusBlocks(for: task) >= max(1, task.estimatedPomodoros) {
          task.completedAt = date
          records.upsertFocusTask(task)
        }
        if completesFocusDay(after: session, at: date) { return }
        let suggestedKind = nextFocusBreakKind(after: session)
        let suggestedAction: FocusNextAction =
          suggestedKind == .longBreak
          ? .startLongBreak : .startShortBreak
        // Do not surface a break CTA that cannot start because this block just
        // reached lunch or clock-off. There is no phase to skip in that case.
        focusLastNextAction =
          plannedFocusBreakEnd(kind: suggestedKind, at: observedAt ?? date) == nil
          ? .none
          : suggestedAction
        autoStartFocusBreak(kind: suggestedKind, after: session, at: observedAt ?? date)
      }
    }
  }

  /// The recovery a finished block earned starts with it.
  ///
  /// Two clocks are in play here and collapsing them into one is what wrote
  /// overlapping records. The break *starts* at the block's own planned end,
  /// because the Lock Screen has already been counting it down from there
  /// and the two must agree. Whether it may start at all is judged against
  /// `date`, the real moment the app came back: returning after the window
  /// has closed backfills nothing.
  private func autoStartFocusBreak(
    kind: FocusSessionKind,
    after session: FocusSession,
    at date: Date
  ) {
    guard let end = plannedFocusBreakEnd(kind: kind, at: session.plannedEndAt),
      end > date
    else { return }
    focusLastNextAction = kind == .longBreak ? .startLongBreak : .startShortBreak
    _ = startBreak(
      kind: kind, at: session.plannedEndAt,
      id: FocusSessionIdentity.recovery(after: session.id, kind: kind)
    ).synchronousResult
  }

  /// Ends a block whose planned end has already passed, with the reason that
  /// actually applies.
  ///
  /// The one place a block ends by itself. A phone spends most of a pomodoro
  /// suspended, so this cannot depend on a view ticking once a second — that
  /// only ran while the Focus page was on screen, and it reported every end
  /// as a boundary cut, so finishing a pomodoro never completed its task.
  /// Called on launch, on foreground, at day change, and by the Focus page
  /// when its countdown reaches zero.
  @discardableResult
  func finishElapsedFocusSession(at date: Date = .now) -> RecordCommand<Bool> {
    records.submitCommand { [self] in
      guard let session = activeFocusSession(), session.plannedEndAt <= date else { return false }
      let reason =
        session.plannedEndReason
        ?? FocusPlanner.endReason(
          startedAt: session.startedAt,
          plannedEndAt: session.plannedEndAt,
          // v1 sessions were always 25-minute focus blocks. Preferences are
          // intentionally local and must not rewrite historical outcomes.
          expectedDurationMinutes: FocusPlanner.pomodoroMinutes
        )
      // The session ended at its boundary; waking later is only an observation.
      stopFocus(reason: reason, at: session.plannedEndAt, observedAt: date).synchronousResult
      return true
    }
  }

  private func restoreFocusNextActionFromHistory(at date: Date) {
    guard activeFocusSession() == nil else { return }
    guard
      let latest = records.state.focusSessions
        .filter({ $0.endedAt != nil })
        .max(by: { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) })
    else {
      focusLastNextAction = .none
      return
    }
    // A prior shift's recovery prompt is history, not today's next action.
    guard let shift = snapshot(at: date),
      RecordJSON.dayKey(latest.shiftAnchorDate, calendar: recordsCalendar)
        == RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
    else {
      focusLastNextAction = .none
      return
    }
    if latest.kind == .shortBreak || latest.kind == .longBreak {
      focusLastNextAction = .startNextFocus
      return
    }
    guard latest.kind == .focus, latest.endReason == .completed else {
      focusLastNextAction = .none
      return
    }
    focusLastNextAction =
      nextFocusBreakKind(after: latest) == .longBreak
      ? .startLongBreak : .startShortBreak
  }

  /// Called after a CloudKit batch/import and on lifecycle restore. Exactly
  /// one open session survives; losing rows remain audit history and sync.
  func reconcileOpenFocusSessions(at date: Date = .now) -> RecordCommand<Void> {
    records.submitCommand { [self] in
      records.withBatchedWrites {
        guard !isReconcilingFocusSessions else { return }
        isReconcilingFocusSessions = true
        defer { isReconcilingFocusSessions = false }
        let open = records.state.focusSessions.filter { $0.endedAt == nil }.sorted {
          if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
          return $0.id.uuidString < $1.id.uuidString
        }
        guard let winner = open.first else {
          focusExpiryTask?.cancel()
          focusExpiryTask = nil
          focusNotificationGeneration &+= 1
          Task { await NotificationService.cancelAllFocusTimers() }
          restoreFocusNextActionFromHistory(at: date)
          return
        }
        for var losing in open.dropFirst() {
          losing.endedAt = date
          losing.endReason = .supersededBySync
          losing.actualDurationSeconds = max(0, Int(date.timeIntervalSince(losing.startedAt)))
          records.upsertFocusSession(losing, at: date)
        }
        if winner.plannedEndAt <= date {
          _ = finishElapsedFocusSession(at: date).synchronousResult
          restoreFocusNextActionFromHistory(at: date)
        } else {
          focusLastNextAction = .none
          scheduleFocusExpiry(for: winner).synchronousResult
          scheduleFocusTimerNotification(for: winner)
        }
      }
    }
  }

  #if DEBUG
    /// Deterministic, DEBUG-only states for the release-blocking Focus visual
    /// matrix. These hooks never ship and avoid pretending that waiting through
    /// four real Pomodoros is meaningful UI verification.
    func activateDebugFocusScenario(_ raw: String, at now: Date) -> RecordCommand<Void> {
      records.submitCommand { [self] in
        guard
          var task = records.state.focusTasks.first(where: { $0.id == DebugRecordSeed.id(800) })
            ?? records.state.focusTasks.first(where: { $0.deletedAt == nil })
        else { return }

        @MainActor
        func seedCompletedSession(kind: FocusSessionKind, index: Int, endedAt: Date) {
          let minutes =
            switch kind {
            case .focus: focusTimerSettings.focusMinutes
            case .shortBreak: focusTimerSettings.shortBreakMinutes
            case .longBreak: focusTimerSettings.longBreakMinutes
            }
          let startedAt = endedAt.addingTimeInterval(-Double(minutes * 60))
          records.upsertFocusSession(
            FocusSession(
              id: DebugRecordSeed.id(820 + index),
              taskID: task.id,
              shiftAnchorDate: recordsCalendar.startOfDay(for: now),
              startedAt: startedAt,
              plannedEndAt: endedAt,
              endedAt: endedAt,
              endReason: .completed,
              editedAt: endedAt,
              editCount: 0,
              editTieBreaker: DebugRecordSeed.id(840 + index),
              kind: kind,
              timeZoneIdentifier: recordsCalendar.timeZone.identifier,
              actualDurationSeconds: minutes * 60,
              plannedEndReason: .completed
            ), at: endedAt)
        }

        switch raw {
        case "templateCapacity":
          let tasks = [
            FocusTemplateTask(
              taskKey: DebugRecordSeed.id(880), legacyIndex: 0,
              title: t("focusDemoWriting"), icon: .writing, pomodoros: 1),
            FocusTemplateTask(
              taskKey: DebugRecordSeed.id(881), legacyIndex: 1,
              title: t("focusDemoLearning"), icon: .study, pomodoros: 99),
            FocusTemplateTask(
              taskKey: DebugRecordSeed.id(882), legacyIndex: 2,
              title: t("focusDemoMessages"), icon: .communication, pomodoros: 1),
          ]
          let template = FocusTemplate(
            id: DebugRecordSeed.id(883), name: t("focusUsualDayDefaultName"),
            slots: FocusTemplate.slots(from: tasks), createdAt: now, updatedAt: now)
          focusPlanning.templates = [template]
          persistFocusPlanning()
        case "dayComplete":
          for var completedTask in focusTasksForToday(at: now) {
            completedTask.completedAt = now
            records.upsertFocusTask(completedTask, at: now)
          }
          seedCompletedSession(kind: .focus, index: 0, endedAt: now.addingTimeInterval(-60))
        case "shortBreakOffer":
          seedCompletedSession(kind: .focus, index: 0, endedAt: now.addingTimeInterval(-60))
          focusLastNextAction = .startShortBreak
        case "longBreakOffer":
          for index in 0..<4 {
            seedCompletedSession(
              kind: .focus,
              index: index,
              endedAt: now.addingTimeInterval(Double((index - 4) * 60))
            )
          }
          focusLastNextAction = .startLongBreak
        case "nextFocus":
          seedCompletedSession(kind: .shortBreak, index: 0, endedAt: now.addingTimeInterval(-60))
          focusLastNextAction = .startNextFocus
        case "future":
          let tomorrow = recordsCalendar.date(byAdding: .day, value: 1, to: now) ?? now
          task.plannedForDate = recordsCalendar.startOfDay(for: tomorrow)
          task.scheduledStartAt = recordsCalendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
          task.editedAt = now
          task.editCount += 1
          task.editTieBreaker = UUID()
          records.upsertFocusTask(task, at: now)
        case "overflow":
          task.estimatedPomodoros = 99
          task.editedAt = now
          task.editCount += 1
          task.editTieBreaker = UUID()
          records.upsertFocusTask(task, at: now)
        case "notificationDenied":
          focusNotificationIssue = .permissionDenied
        case "notificationFailed":
          activateDebugFocusScenario("runningFocus", at: now).synchronousResult
          focusNotificationIssue = .schedulingFailed
        case "runningShortBreak", "runningLongBreak", "runningFocus", "runningFocusEndingSoon":
          let kind: FocusSessionKind =
            switch raw {
            case "runningShortBreak": .shortBreak
            case "runningLongBreak": .longBreak
            default: .focus
            }
          let minutes =
            switch kind {
            case .focus: focusTimerSettings.focusMinutes
            case .shortBreak: focusTimerSettings.shortBreakMinutes
            case .longBreak: focusTimerSettings.longBreakMinutes
            }
          // Exercise the lock-screen boundary without waiting a whole block.
          let startedAt =
            raw == "runningFocusEndingSoon"
            ? now.addingTimeInterval(15 - Double(minutes * 60)) : now
          records.upsertFocusSession(
            FocusSession(
              id: DebugRecordSeed.id(
                raw == "runningShortBreak" ? 810 : raw == "runningLongBreak" ? 811 : 812),
              taskID: task.id,
              shiftAnchorDate: recordsCalendar.startOfDay(for: now),
              startedAt: startedAt,
              plannedEndAt: startedAt.addingTimeInterval(Double(minutes * 60)),
              endedAt: nil,
              endReason: nil,
              editedAt: now,
              editCount: 0,
              editTieBreaker: DebugRecordSeed.id(813),
              kind: kind,
              timeZoneIdentifier: recordsCalendar.timeZone.identifier,
              plannedEndReason: .completed
            ), at: now)
        default:
          break
        }
      }
    }

  #endif
}
