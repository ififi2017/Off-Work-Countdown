import SwiftUI

struct RecordDayDetailHost: View {
    let store: OffWorkStore
    let dayKey: String

    var body: some View {
        if let resolution = store.resolvedDay(dayKey: dayKey) {
            RecordResolvedDayView(store: store, resolution: resolution)
        } else {
            Text(store.t("recordsSourceNone"))
                .foregroundStyle(OWCDesign.secondary)
        }
    }
}

struct RecordResolvedDayView: View {
    let store: OffWorkStore
    let resolution: DayResolution

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sourceLabel)
                            .font(.body.weight(.medium))
                        if !resolution.segments.isEmpty {
                            Text(hoursLabel)
                                .font(.title3.monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("recordsObservations"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        let items = store.observations(on: resolution.shiftAnchorDate)
                        if items.isEmpty {
                            Text(store.t("recordsNoObservations"))
                                .font(.body)
                                .foregroundStyle(OWCDesign.secondary)
                        } else {
                            ForEach(items) { item in
                                Text(observationLabel(item))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                if let conflict = store.records.state.sync.conflicts.first(where: { $0.logicalKey == resolution.dayKey }) {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("recordsConflictCopy"))
                                .font(.body.weight(.medium))
                            Button(store.t("recordsRestoreConflict")) {
                                store.restoreConflict(conflict)
                            }
                        }
                        .padding(16)
                    }
                }

                OWCGroupCard {
                    Button(store.t("recordsEditDay")) {
                        store.openDayEditor(dayKey: resolution.dayKey)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(resolution.shiftAnchorDate.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceLabel: String {
        switch resolution.layer {
        case .schedule: store.t("recordsSourceSchedule")
        case .calendarException: store.t("recordsSourceException")
        case .override: store.t("recordsSourceOverride")
        case .none: store.t("recordsSourceNone")
        }
    }

    private var hoursLabel: String {
        let ms = resolution.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return RelativeDurationFormatter.string(milliseconds: ms, languageCode: store.languageCode)
    }

    private func observationLabel(_ item: WorkObservation) -> String {
        let time = item.occurredAt.formatted(date: .omitted, time: .shortened)
        let kind: String
        switch item.kind {
        case .timerSurfaceFirstSeen: kind = store.t("recordsObservedFirstSeen")
        case .countdownStarted: kind = store.t("recordsObservedStarted")
        case .countdownStopped: kind = store.t("recordsObservedStopped")
        case .overtimeDeclared: kind = store.t("recordsObservedOvertime")
        }
        return "\(time) · \(kind)"
    }
}

struct RecordDayEditView: View {
    let store: OffWorkStore
    let dayKey: String
    @State private var startMinutes = 9 * 60
    @State private var endMinutes = 18 * 60

    var body: some View {
        List {
            DatePicker(
                store.t("startTime"),
                selection: startBinding,
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                store.t("endTime"),
                selection: endBinding,
                displayedComponents: .hourAndMinute
            )
            Button(store.t("lifeSave")) {
                store.saveCustomHours(dayKey: dayKey, startMinutes: startMinutes, endMinutes: endMinutes)
            }
            Button(store.t("recordsConfirmScheduled")) {
                store.confirmDayAsScheduled(dayKey: dayKey)
            }
            Button(store.t("recordsMarkLeave")) {
                store.markDayNotWorking(dayKey: dayKey)
            }
            Button(store.t("recordsClearDay")) {
                store.clearDayOverride(dayKey: dayKey)
            }
            Button(store.t("recordsMarkRest")) {
                store.markCalendarException(dayKey: dayKey, effect: .rest)
            }
            Button(store.t("recordsMarkMakeup")) {
                store.markCalendarException(dayKey: dayKey, effect: .work)
            }
        }
        .navigationTitle(store.t("recordsEditDay"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadHours)
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: startMinutes) },
            set: { startMinutes = minutes(from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: endMinutes) },
            set: { endMinutes = minutes(from: $0) }
        )
    }

    private func loadHours() {
        guard let resolution = store.resolvedDay(dayKey: dayKey),
              let first = resolution.segments.first,
              let last = resolution.segments.last
        else { return }
        startMinutes = minutes(from: Date(timeIntervalSince1970: first.startAtMs / 1_000))
        endMinutes = minutes(from: Date(timeIntervalSince1970: last.endAtMs / 1_000))
    }

    private func date(fromMinutes value: Int) -> Date {
        store.recordsCalendar.date(
            bySettingHour: value / 60,
            minute: value % 60,
            second: 0,
            of: store.recordsCalendar.startOfDay(for: .now)
        ) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let parts = store.recordsCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
