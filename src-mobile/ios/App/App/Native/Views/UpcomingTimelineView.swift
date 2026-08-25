import SwiftUI

struct UpcomingTimelineView: View {
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var isExpanded: Bool
    let collapsedEventLimit: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        store: OffWorkStore,
        snapshot: NativeShiftSnapshot,
        now: Date,
        isExpanded: Binding<Bool>,
        collapsedEventLimit: Int = 2
    ) {
        self.store = store
        self.snapshot = snapshot
        self.now = now
        _isExpanded = isExpanded
        self.collapsedEventLimit = max(1, collapsedEventLimit)
    }

    var body: some View {
        let events = store.upcomingTimelineEvents(for: snapshot, at: now)
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
