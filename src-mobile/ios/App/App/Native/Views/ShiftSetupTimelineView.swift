import SwiftUI

/// What today's shift will do, before it starts.
///
/// Two cards, deliberately separated. The first is a timeline: everything that
/// is switched on, in the order it will happen, one row per kind of event rather
/// than one per firing. The second holds whatever is switched off — those have
/// no time, so putting them in a list headed "coming up" would be a lie, but
/// dropping them entirely hides features a new user has never seen. When
/// nothing is switched off, the second card does not appear at all.
struct ShiftSetupTimelineView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let onSelect: (AppRoute) -> Void
    let onEditTime: (SetupTimeField) -> Void

    var body: some View {
        // Touch every setting the preview displays so a change invalidates
        // this view. TimelineView only ticks once a minute; putting those
        // same fields on `.id` rebuilt the whole tree on every wheel tick.
        let _ = scene.displayedStartMinutes(using: shifts.preferences)
        let _ = scene.displayedEndMinutes(using: shifts.preferences)
        let _ = shifts.preferences.lunchEnabled
        let _ = shifts.preferences.lunchStartMinutes
        let _ = shifts.preferences.lunchDurationMinutes
        let _ = shifts.preferences.microBreakEnabled
        let _ = shifts.preferences.microBreakIntervalMinutes
        let _ = shifts.preferences.liveActivityEnabled
        let _ = shifts.preferences.liveActivityLeadMinutes
        let _ = shifts.preferences.notificationMode
        let _ = shifts.preferences.scheduleMode
        let _ = shifts.preferences.workdays
        let _ = shifts.preferences.alternatingWeekType
        let _ = shifts.preferences.alternatingWeekendWorkday
        let _ = shifts.preferences.alternatingReferenceWeekStartMs
        let _ = shifts.preferences.rotationWorkDays
        let _ = shifts.preferences.rotationRestDays
        let _ = shifts.preferences.rotationAnchorMs

        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(at: timeline.date)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let preview = scene.setupSnapshot(at: now, using: shifts).map { shifts.shiftPreview(for: $0, at: now) }

        VStack(alignment: .leading, spacing: OWCDesign.sectionGap) {
            if let upcoming = preview?.upcoming, !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    OWCSectionHeader(title: shifts.text.t("comingUp"))
                    OWCGroupCard {
                        ForEach(upcoming) { entry in
                            row(entry, now: now, isLast: entry.id == upcoming.last?.id)
                        }
                    }
                    HolidayCoverageNoticeView(
                        regionIdentifier: holidayRegionIdentifier,
                        dates: upcoming.compactMap(\.date),
                        timeZone: shifts.preferences.recordsTimeZone,
                        text: shifts.text
                    )
                    .padding(.top, 6)
                }
            }

            if let disabled = preview?.disabled, !disabled.isEmpty {
                OWCGroupCard {
                    ForEach(disabled) { entry in
                        row(entry, now: now, isLast: entry.id == disabled.last?.id)
                    }
                }
            }
        }
    }

    private var holidayRegionIdentifier: String? {
        guard shifts.preferences.isExtendedScheduleEnabled else { return nil }
        return shifts.preferences.extendedScheduleContent?.holidayRegionIdentifier
    }

    @ViewBuilder
    private func row(_ entry: ShiftPreviewEntry, now: Date, isLast: Bool) -> some View {
        let label = ShiftPreviewRow(
            locale: shifts.preferences.locale,
            entry: entry,
            now: now,
            showsSeparator: !isLast,
            showsChevron: entry.route != nil || editField(for: entry.kind) != nil
        )

        if let field = editField(for: entry.kind) {
            Button { onEditTime(field) } label: { label }
                .buttonStyle(OWCRowButtonStyle())
        } else if let route = entry.route {
            Button { onSelect(route) } label: { label }
                .buttonStyle(OWCRowButtonStyle())
        } else {
            label
        }
    }

    /// The shift's own boundaries open the time picker rather than navigating,
    /// so they are actionable without having an `AppRoute`.
    private func editField(for kind: ShiftPreviewEntry.Kind) -> SetupTimeField? {
        switch kind {
        case .shiftStart: .start
        case .shiftEnd: .end
        default: nil
        }
    }
}
