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
    let store: OffWorkStore
    let onSelect: (AppRoute) -> Void
    let onEditTime: (SetupTimeField) -> Void

    var body: some View {
        // A minute is plenty for a preview — the running screen is the one that
        // needs a second-by-second clock, and rebuilding a snapshot that often
        // means re-entering CountdownRules for nothing.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(at: timeline.date)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let preview = store.snapshot(at: now).map { store.shiftPreview(for: $0, at: now) }

        VStack(alignment: .leading, spacing: OWCDesign.sectionGap) {
            if let upcoming = preview?.upcoming, !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    OWCSectionHeader(title: store.t("comingUp"))
                    OWCGroupCard {
                        ForEach(upcoming) { entry in
                            row(entry, now: now, isLast: entry.id == upcoming.last?.id)
                        }
                    }
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

    @ViewBuilder
    private func row(_ entry: ShiftPreviewEntry, now: Date, isLast: Bool) -> some View {
        let label = ShiftPreviewRow(
            store: store,
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
