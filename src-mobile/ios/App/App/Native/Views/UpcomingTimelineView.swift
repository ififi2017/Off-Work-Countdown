import SwiftUI

/// How the timer pages tell `UpcomingTimelineView` how much room it has.
///
/// The list cannot see the countdown, the meter and the summary card stacked
/// above it, but it does not need their heights — only where it starts, which is
/// the same number. Each page names its scroll content with this space and the
/// list reports its own `minY` inside it. That value does not depend on how many
/// rows the list ends up drawing, so measuring it cannot feed back into itself.
/// `nonisolated` because the values are read from `onGeometryChange`'s
/// measurement closure, which is `@Sendable`. The project defaults declarations
/// to the main actor, and immutable constants have nothing to protect.
nonisolated enum TimerContentSpace {
    static let name = "owc.timer.content"

    /// The `Spacer(minLength:)` every timer page keeps under the list, held back
    /// so the last row never sits flush against the action bar.
    static let bottomSlack: CGFloat = 22
}

/// The eye that blanks and restores the earnings figure.
///
/// Extracted so the iPad uses the same rule as the phone rather than a second
/// copy of it. The rule is the asymmetry: hiding is free, revealing is not —
/// anyone handed the device can blank the figure, only its owner can bring it
/// back. A second implementation of that is a second chance to get it backwards.
struct OWCEarningsVisibilityButton: View {
    let store: OffWorkStore

    var body: some View {
        Button {
            guard store.hideEarnings else {
                store.hideEarnings = true
                return
            }
            Task {
                if await BiometricGate.confirmOwner(reason: store.t("unlockSalaryReason")) {
                    store.hideEarnings = false
                }
            }
        } label: {
            Image(systemName: store.hideEarnings ? "eye" : "eye.slash")
                .font(.body)
                .foregroundStyle(OWCDesign.tertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.t(store.hideEarnings ? "unlockSalary" : "salaryLocked"))
        .sensoryFeedback(.selection, trigger: store.hideEarnings)
    }
}

extension OffWorkStore {
    /// `timelineExpanded` as a `Binding`, so the timer views can hand it to the
    /// list without each of them holding a copy that can drift out of step.
    var timelineExpandedBinding: Binding<Bool> {
        Binding(get: { self.timelineExpanded }, set: { self.timelineExpanded = $0 })
    }
}

struct UpcomingTimelineView: View {
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var isExpanded: Bool

    /// Free height between whatever sits above this list and the action bar,
    /// **in the collapsed layout**. Zero means "not measured yet".
    ///
    /// Collapsed specifically: expanding hides the summary card above, which
    /// moves this list up and would report a much larger figure. Sizing off that
    /// figure made the list look big enough to hold everything, and the
    /// "collapse" button — which only appears when it is not — disappeared with
    /// it, stranding the user in the expanded state. The callers freeze the
    /// measurement while expanded for that reason.
    ///
    /// The list used to take `height < 560 ? 1 : 2`, which asked about the whole
    /// screen instead of about the gap that is actually free. Two things make
    /// that gap vary a lot — the phone (a Pro Max is 82pt taller than a Pro) and
    /// whether the salary row is switched on, which is a whole row of the card
    /// above. With salary off on a Pro Max there was room for five rows and the
    /// list still stopped at two, leaving a band of empty page over the buttons.
    let availableHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `UpcomingTimelineEventRow` pins itself to `minHeight: 58`, which is what
    /// its title-and-detail pair measures at the default text size.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 58
    /// `OWCSectionHeader`: one footnote line plus its 6pt bottom padding.
    @ScaledMetric(relativeTo: .footnote) private var headerHeight: CGFloat = 24
    /// The expand button's own `minHeight`.
    @ScaledMetric(relativeTo: .footnote) private var expandButtonHeight: CGFloat = 44

    /// Used until the caller has measured. Matches the old fixed limit, so the
    /// first frame looks like it always did rather than briefly overflowing.
    private static let unmeasuredLimit = 2

    /// How many rows the free space takes.
    ///
    /// Rounds to the nearest row rather than down. Coming up half a row short is
    /// not a failure — the page already lives in a `ScrollView` and absorbs it —
    /// while dropping that row leaves a visible band of empty page above the
    /// buttons, which is the thing this is here to prevent. Flooring cost a row
    /// on a 17 Pro, where two rows and the button miss the available height by
    /// about ten points.
    private func collapsedLimit(eventCount: Int) -> Int {
        guard availableHeight > 0, rowHeight > 0 else { return Self.unmeasuredLimit }

        let forRows = availableHeight - headerHeight
        guard forRows >= rowHeight else { return 1 }

        if Int((forRows / rowHeight).rounded()) >= eventCount { return eventCount }

        // Something stays hidden, so the expand button needs its own room —
        // pushed under the action bar it is an affordance nobody finds.
        return max(1, Int(((forRows - expandButtonHeight) / rowHeight).rounded()))
    }

    var body: some View {
        let events = store.upcomingTimelineEvents(for: snapshot, at: now)
        let collapsedEventLimit = collapsedLimit(eventCount: events.count)
        let visibleEvents = isExpanded ? events : Array(events.prefix(collapsedEventLimit))
        let hiddenCount = max(0, events.count - collapsedEventLimit)

        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("comingUp"))
                OWCGroupCard {
                    ForEach(visibleEvents) { event in
                        UpcomingTimelineEventRow(
                            store: store,
                            event: event,
                            now: now,
                            showsSeparator: event.id != visibleEvents.last?.id || events.count > collapsedEventLimit
                        )
                        .transition(eventTransition)
                    }

                    if events.count > collapsedEventLimit {
                        Button(action: toggleExpansion) {
                            HStack(spacing: 8) {
                                Text(isExpanded
                                     ? store.t("timelineCollapse")
                                     : store.t("timelineExpand", values: ["count": "\(hiddenCount)"]))
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .accessibilityHidden(true)
                            }
                            .font(.footnote.bold())
                            .foregroundStyle(OWCDesign.accent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: isExpanded)
            .onChange(of: events.count) { _, count in
                guard count <= collapsedEventLimit, isExpanded else { return }
                withAnimation(expansionAnimation) { isExpanded = false }
            }
        }
    }

    private func toggleExpansion() {
        withAnimation(expansionAnimation) { isExpanded.toggle() }
    }

    private var expansionAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.selection
    }

    private var eventTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}
