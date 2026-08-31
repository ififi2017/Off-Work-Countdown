import SwiftUI

struct UpcomingTimelineEventRow: View {
    let store: OffWorkStore
    let event: UpcomingTimelineEvent
    let now: Date
    let showsSeparator: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body)
                    .foregroundStyle(OWCDesign.primary)
                Text(event.detail)
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
            }

            Spacer(minLength: 8)

            Group {
                if Calendar.current.isDate(event.date, inSameDayAs: now) {
                    Text(event.date, format: .dateTime.hour().minute().locale(store.locale))
                } else {
                    Text(event.date, format: .dateTime.weekday(.abbreviated).hour().minute().locale(store.locale))
                }
            }
            .font(.body.monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .overlay(alignment: .bottomTrailing) {
            if showsSeparator {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 44)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if let symbolName = event.symbolName { return symbolName }
        return switch event.kind {
        case .shiftStart: "sunrise.fill"
        case .lunchStart: "cup.and.saucer.fill"
        case .lunchEnd: "arrow.right.circle.fill"
        case .health: "figure.walk"
        case .focus: "timer"
        case .focusBreak: "cup.and.saucer.fill"
        case .milestone: "bell.badge.fill"
        case .shiftEnd: "flag.checkered"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .shiftStart: .blue
        case .lunchStart, .lunchEnd: .cyan
        case .health: .green
        case .focus: OWCDesign.accent
        case .focusBreak: .mint
        case .milestone: .indigo
        case .shiftEnd: OWCDesign.accent
        }
    }
}
