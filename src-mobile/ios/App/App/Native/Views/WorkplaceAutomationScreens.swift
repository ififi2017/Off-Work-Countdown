import CoreLocation
import SwiftUI
import UIKit

// Plan 021 U1: connects the reviewed designs in `WorkplaceAutomationViews`
// to `WorkplaceAutomationCoordinator`, records and location permission.
// Every write still goes through the coordinator.

/// Turns automation state into the rows the review screens show.
@MainActor
struct WorkplaceAutomationPresenter {
    let text: AppText
    let timeZone: TimeZone
    let locale: Locale

    /// How long an adopted time can still be undone from the review page.
    static let recentWindow: TimeInterval = 7 * 86_400
    static let recentLimit = 5

    func reviewItems(_ state: WorkplaceAutomationState) -> [AutomationReviewItem] {
        state.pendingProposals
            .sorted {
                $0.shift.plannedStart != $1.shift.plannedStart
                    ? $0.shift.plannedStart > $1.shift.plannedStart
                    : ($0.boundary == .start && $1.boundary == .end)
            }
            .map { proposal in
                AutomationReviewItem(
                    id: proposal.id,
                    dayTitle: dayTitle(proposal.shift.anchorDayKey),
                    boundary: proposal.boundary,
                    time: time(proposal.proposedTime),
                    planned: time(proposal.boundary == .start ? proposal.shift.plannedStart : proposal.shift.plannedEnd),
                    note: Self.noteKey(for: proposal.reasons).map { text.t($0) },
                    source: source(of: proposal, in: state)
                )
            }
    }

    func recentItems(_ state: WorkplaceAutomationState, now: Date) -> [AutomationRecentItem] {
        state.receipts
            .filter { $0.writtenEditCount != nil && $0.undoneAt == nil
                && now.timeIntervalSince($0.completedAt) < Self.recentWindow }
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(Self.recentLimit)
            .compactMap { receipt in
                guard let proposal = state.proposals.first(where: {
                    $0.isAdopted && ($0.id == receipt.commandID || $0.sourceEventIDs.contains(receipt.commandID))
                }) else { return nil }
                let boundary = text.t(proposal.boundary == .start ? "automationUIStartAt" : "automationUIEndAt",
                                      values: ["time": time(proposal.proposedTime)])
                return AutomationRecentItem(
                    id: receipt.commandID,
                    dayTitle: dayTitle(proposal.shift.anchorDayKey),
                    summary: boundary + " · " + sourceLabel(source(of: proposal, in: state))
                )
            }
    }

    func changes(
        _ preview: [(shift: AutomationShift, segments: [NativeShiftSegment])],
        current: (String) -> [NativeShiftSegment]?
    ) -> [AutomationReviewChange] {
        preview.map { item in
            let before = current(item.shift.anchorDayKey) ?? item.shift.segments
            return AutomationReviewChange(
                id: item.shift.shiftKey,
                dayTitle: dayTitle(item.shift.anchorDayKey),
                before: range(before),
                after: range(item.segments)
            )
        }
    }

    /// The one reason worth showing beside a suggestion, if any.
    static func noteKey(for reasons: [AutomationReviewReason]) -> String? {
        let priority: [(AutomationReviewReason, String)] = [
            (.recordsUnavailable, "automationUINoteRecordsUnavailable"),
            (.recordChangedByPerson, "automationUINoteChangedByYou"),
            (.earlyStartNeedsConfirmation, "automationUINoteEarlyStart"),
            (.leftBeforePlannedEnd, "automationUINoteLeftEarly"),
            (.staleEvent, "automationUINoteLateDetection"),
            (.unknownObservationTime, "automationUINoteLateDetection"),
            (.arrivalTimeUncertain, "automationUINoteArrivalUncertain"),
            (.beyondAutomaticWindow, "automationUINoteFarFromPlan"),
        ]
        return priority.first { reasons.contains($0.0) }?.1
    }

    func sourceLabel(_ source: AutomationEventSource) -> String {
        text.t(source == .nativeGeofence ? "automationUISourceLocation" : "automationUISourceShortcuts")
    }

    private func source(of proposal: WorkTimeProposal, in state: WorkplaceAutomationState) -> AutomationEventSource {
        let ids = Set(proposal.sourceEventIDs)
        return state.events.last { ids.contains($0.id) }?.source ?? .nativeGeofence
    }

    func dayTitle(_ dayKey: String) -> String {
        guard let parts = ExtendedScheduleResolver.parse(dayKey: dayKey) else { return dayKey }
        return text.formatCivilDate(year: parts.year, month: parts.month, day: parts.day, template: "MMMdEEE")
    }

    func time(_ date: Date) -> String {
        RecordsDateFormatters.shared.formatter(template: "jm", locale: locale, timeZone: timeZone).string(from: date)
    }

    private func range(_ segments: [NativeShiftSegment]) -> String {
        guard let first = segments.first, let last = segments.last else { return "–" }
        return time(Date(timeIntervalSince1970: first.startAtMs / 1_000)) + "–"
            + time(Date(timeIntervalSince1970: last.endAtMs / 1_000))
    }
}

// MARK: - Settings

struct WorkplaceAutomationSettingsView: View {
    @Environment(SceneState.self) private var scene
    @Environment(\.openURL) private var openURL
    let runtime: AppRuntime
    @State private var editing: EditorTarget?
    @State private var addsContext = false
    /// Set when the toggle opened the paywall, so a purchase turns it on.
    @State private var enableAfterPurchase = false

    private var automation: WorkplaceAutomationCoordinator { runtime.workplaceAutomation }
    private var location: WorkplaceLocationService { runtime.workplaceLocation }
    private var plus: PlusEntitlement { runtime.plus }

    enum EditorTarget: Identifiable {
        case new
        case existing(SavedWorkplace)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let workplace): workplace.id.uuidString
            }
        }
    }

    var body: some View {
        WorkplaceAutomationSettingsContent(
            text: runtime.text,
            isPlus: plus.canCollectAutomation,
            access: location.access,
            settings: automation.state.settings,
            workplaces: automation.state.workplaces,
            pendingCount: automation.state.pendingProposals.count,
            onToggleMonitoring: setMonitoring,
            onToggleAutoApply: { on in automation.update { $0.settings.appliesDetectedTimesAutomatically = on } },
            onPromptDelay: { delay in automation.update { $0.settings.visitPromptDelay = delay } },
            onRequestAccess: location.requestAccess,
            onOpenSystemSettings: { openURL(URL(string: UIApplication.openSettingsURLString)!) },
            onAddWorkplace: { editing = .new },
            onOpenWorkplace: { editing = .existing($0) },
            contexts: contextItems,
            onAddContext: { addsContext = true },
            onDeleteContext: { id in automation.update { $0.removeContext(id) } },
            monitorNote: monitorNote,
            onToggleNotify: { on in automation.update { $0.settings.notifiesArrivalsAndDepartures = on } },
            pausedShifts: pausedShifts,
            onResume: { automation.resumeAutomation(shiftKey: $0) },
            hasDeviceData: automation.state.hasDeviceData,
            onDeleteData: { automation.eraseDeviceData() }
        )
        .sheet(isPresented: $addsContext) {
            WorkContextEditorSheet(text: runtime.text, calendar: runtime.preferences.recordsCalendar) { context, first, last in
                automation.update { $0.setContext(context, from: first, through: last) }
            }
        }
        .sensoryFeedback(.selection, trigger: automation.state.settings)
        .sheet(item: $editing) { target in
            WorkplaceEditorSheet(runtime: runtime, target: target)
        }
        .onChange(of: plus.canCollectAutomation) { _, allowed in
            if allowed, enableAfterPurchase { setMonitoring(true) }
            enableAfterPurchase = false
        }
        .onAppear {
            location.refresh()
            automation.surfaceUnreturnedExits()
        }
    }

    /// Four separate facts (§I2): access is shown above; this says whether
    /// the circles are registered and when a crossing last arrived.
    private var monitorNote: AutomationMonitorNote? {
        let status = runtime.workplaceMonitor.status
        let text = runtime.text
        if status.problems.contains(.locationOff) {
            return AutomationMonitorNote(text: text.t("automationUIMonitorLocationOff"), isProblem: true)
        }
        if status.problems.contains(.needsPreciseLocation) {
            return AutomationMonitorNote(text: text.t("automationUIAccessPreciseNote"), isProblem: true)
        }
        if status.problems.contains(.needsAlways) {
            return AutomationMonitorNote(text: text.t("automationUIAccessWhileUsingNote"), isProblem: true)
        }
        if !status.problems.isEmpty {
            return AutomationMonitorNote(text: text.t("automationUIMonitorProblem"), isProblem: true)
        }
        guard status.wantedCount > 0 else { return nil }
        guard status.isRegistered else { return AutomationMonitorNote(text: text.t("automationUIMonitorStarting")) }
        let watching = text.t("automationUIMonitorWatching")
        guard let last = status.lastEventAt else {
            return AutomationMonitorNote(text: watching + " " + text.t("automationUIAccessReadyNote"))
        }
        return AutomationMonitorNote(text: watching + "\n" + text.t("automationUIMonitorLastEvent", values: [
            "time": runtime.queries.formatRecordsMonthDay(last) + " " + runtime.queries.formatRecordsTime(last),
        ]))
    }

    private var pausedShifts: [AutomationPausedItem] {
        let now = Date.now
        let presenter = WorkplaceAutomationPresenter(
            text: runtime.text, timeZone: runtime.preferences.recordsTimeZone, locale: runtime.preferences.locale
        )
        return WorkplaceAutomationRules.resumableShifts(
            state: automation.state, shifts: runtime.queries.automationShifts(around: now), now: now
        ).map { shift in
            AutomationPausedItem(
                id: shift.shiftKey,
                title: presenter.dayTitle(shift.anchorDayKey) + " " + presenter.time(shift.plannedStart)
                    + "–" + presenter.time(shift.plannedEnd)
            )
        }
    }

    /// Ranges that have not ended yet, soonest first.
    private var contextItems: [AutomationContextItem] {
        let today = RecordJSON.dayKey(.now, calendar: runtime.preferences.recordsCalendar)
        return automation.state.contexts
            .filter { $0.lastDayKey >= today }
            .sorted { $0.firstDayKey < $1.firstDayKey }
            .map { range in
                AutomationContextItem(id: range.id, context: range.context, range: format(range))
            }
    }

    private func format(_ range: WorkContextRange) -> String {
        func day(_ key: String) -> String {
            guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { return key }
            return runtime.text.formatCivilDate(year: parts.year, month: parts.month, day: parts.day, template: "MMMdEEE")
        }
        return range.firstDayKey == range.lastDayKey ? day(range.firstDayKey) : day(range.firstDayKey) + " – " + day(range.lastDayKey)
    }

    private func setMonitoring(_ on: Bool) {
        guard !on || plus.canCollectAutomation else {
            enableAfterPurchase = true
            scene.paywallSheet = .workplaceAutomation
            return
        }
        automation.update { $0.settings.isMonitoringEnabled = on }
        if on, location.access == .notRequested { location.requestAccess() }
    }
}

// MARK: - Editor

struct WorkplaceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let runtime: AppRuntime
    let target: WorkplaceAutomationSettingsView.EditorTarget

    @State private var name: String
    @State private var innerRadius: Double
    @State private var isEnabled: Bool
    @State private var center: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationFailed = false
    @State private var confirmsDelete = false

    init(runtime: AppRuntime, target: WorkplaceAutomationSettingsView.EditorTarget) {
        self.runtime = runtime
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: runtime.text.t("automationUIWorkplaceNamePlaceholder"))
            _innerRadius = State(initialValue: WorkplaceAutomation.defaultInnerRadius)
            _isEnabled = State(initialValue: true)
            _center = State(initialValue: nil)
        case .existing(let workplace):
            _name = State(initialValue: workplace.name)
            _innerRadius = State(initialValue: workplace.innerRadius)
            _isEnabled = State(initialValue: workplace.isEnabled)
            _center = State(initialValue: CLLocationCoordinate2D(latitude: workplace.latitude, longitude: workplace.longitude))
        }
    }

    private var text: AppText { runtime.text }

    var body: some View {
        NavigationStack {
            WorkplaceEditorContent(
                text: text,
                isNew: isNew,
                name: $name,
                innerRadius: $innerRadius,
                isEnabled: $isEnabled,
                center: center,
                isLocating: isLocating,
                onUseCurrentLocation: locate,
                onSave: save,
                onDelete: { confirmsDelete = true },
                onCancel: { dismiss() }
            )
            .confirmationDialog(text.t("automationUIDeleteWorkplace"), isPresented: $confirmsDelete,
                                titleVisibility: .visible) {
                Button(text.t("automationUIDeleteWorkplace"), role: .destructive, action: delete)
            } message: {
                Text(text.t("automationUIDeleteWorkplaceNote"))
            }
            .alert(text.t("automationUILocationFailed"), isPresented: $locationFailed) {
                Button(text.t("done"), role: .cancel) {}
            }
        }
        .sensoryFeedback(.success, trigger: center?.latitude)
    }

    private var isNew: Bool {
        if case .new = target { true } else { false }
    }

    private func locate() {
        isLocating = true
        Task {
            let found = await runtime.workplaceLocation.currentLocation()
            isLocating = false
            if let found { center = found } else { locationFailed = true }
            runtime.workplaceLocation.refresh()
        }
    }

    private func save() {
        guard let center else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = (try? runtime.workplaceAutomation.update { state in
            switch target {
            case .new:
                try state.addWorkplace(name: trimmed, latitude: center.latitude, longitude: center.longitude,
                                       innerRadius: innerRadius)
            case .existing(let workplace):
                try state.updateWorkplace(
                    workplace.id, name: trimmed, latitude: center.latitude, longitude: center.longitude,
                    innerRadius: innerRadius, outerRadius: innerRadius + WorkplaceAutomation.defaultOuterRadiusMargin,
                    isEnabled: isEnabled
                )
            }
        }) ?? false
        if saved { dismiss() }
    }

    private func delete() {
        guard case .existing(let workplace) = target else { return }
        runtime.workplaceAutomation.update { $0.removeWorkplace(workplace.id) }
        dismiss()
    }
}

// MARK: - Review

struct WorkplaceAutomationReviewView: View {
    let runtime: AppRuntime
    @State private var undoConflict = false
    @State private var feedback = 0

    private var automation: WorkplaceAutomationCoordinator { runtime.workplaceAutomation }

    private var presenter: WorkplaceAutomationPresenter {
        WorkplaceAutomationPresenter(
            text: runtime.text,
            timeZone: runtime.preferences.recordsTimeZone,
            locale: runtime.preferences.locale
        )
    }

    var body: some View {
        let presenter = presenter
        AutomationReviewContent(
            text: runtime.text,
            items: presenter.reviewItems(automation.state),
            recent: presenter.recentItems(automation.state, now: .now),
            preview: { ids in
                presenter.changes(automation.previewSegments(for: ids), current: currentSegments)
            },
            onApply: { ids in
                Task {
                    _ = await automation.applyReviewed(ids)
                    feedback += 1
                }
            },
            onDismiss: { automation.dismiss($0) },
            onUndo: { id in
                Task {
                    let outcome = await automation.undo(commandID: id)
                    if outcome == .needsReview { undoConflict = true } else { feedback += 1 }
                }
            }
        )
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear { automation.surfaceUnreturnedExits() }
        .alert(runtime.text.t("automationUIUndoConflict"), isPresented: $undoConflict) {
            Button(runtime.text.t("done"), role: .cancel) {}
        }
    }

    /// What the day holds now: a hand or automation edit, else the plan.
    private func currentSegments(_ dayKey: String) -> [NativeShiftSegment]? {
        guard let day = runtime.records.state.overrides.first(where: { $0.dayKey == dayKey }),
              !day.segments.isEmpty else { return nil }
        return day.segments
    }
}
