import SwiftUI

// The cards under the Records calendar (3.2.2): a conclusion first, then the
// numbers behind it. Card titles are 15 pt bold; headline numbers use the
// rounded face so they read as values rather than labels.

private enum RecordsCardStyle {
    static let title = Font.subheadline.weight(.bold)
    static let hero = Font.system(.title2, design: .rounded).weight(.bold)
    static let amount = Font.system(.largeTitle, design: .rounded).weight(.bold)
}

struct RecordsInsightChip: Identifiable {
    enum Mark { case work, overtime, planned }
    var id: String { title }
    let mark: Mark
    let title: String
}

struct RecordsInsight {
    var eyebrow: String
    var hero: String
    /// When set, only this part of `hero` is tinted; the rest stays primary.
    var heroEmphasis: String? = nil
    var body: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var chips: [RecordsInsightChip] = []

    /// Sentences carry their own full stop. Latin scripts need a space
    /// between them; a CJK full stop already separates.
    static func joinSentences(_ sentences: [String]) -> String {
        var result = ""
        for sentence in sentences where !sentence.isEmpty {
            if let last = result.last, !"。！？".contains(last) { result += " " }
            result += sentence
        }
        return result
    }
}

extension Array where Element == String {
    var joinedSentences: String { RecordsInsight.joinSentences(self) }
}

/// Eyebrow, one tinted headline, a sentence and an optional next step.
struct RecordsInsightCard: View {
    let insight: RecordsInsight

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(insight.eyebrow)
                    .font(RecordsCardStyle.title)
                    .foregroundStyle(OWCDesign.primary)
                    .padding(.bottom, 4)
                Text(heroText)
                    .font(RecordsCardStyle.hero)
                    .fixedSize(horizontal: false, vertical: true)
                if insight.body != nil || insight.actionTitle != nil {
                    bodyText
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                if !insight.chips.isEmpty {
                    OWCFlowLayout(spacing: 6) {
                        ForEach(insight.chips) { chip in
                            RecordsChipView(chip: chip)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(insight.actionTitle ?? "")) { insight.action?() }
    }

    private var heroText: AttributedString {
        var value = AttributedString(insight.hero)
        value.foregroundColor = insight.heroEmphasis == nil ? OWCDesign.recordsWork : OWCDesign.primary
        if let emphasis = insight.heroEmphasis, let range = value.range(of: emphasis) {
            value[range].foregroundColor = OWCDesign.recordsWork
        }
        return value
    }

    /// The sentence, then its next step in medium accent with a chevron.
    private func bodyWithAction(_ actionTitle: String) -> AttributedString {
        var value = AttributedString(insight.body.map { $0 + " " } ?? "")
        var action = AttributedString(actionTitle + " ›")
        action.foregroundColor = OWCDesign.accent
        action.font = .subheadline.weight(.medium)
        value.append(action)
        return value
    }

    @ViewBuilder
    private var bodyText: some View {
        if let actionTitle = insight.actionTitle, insight.action != nil {
            Button { insight.action?() } label: {
                Text(bodyWithAction(actionTitle))
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        } else if let body = insight.body {
            Text(body)
        }
    }
}

private struct RecordsChipView: View {
    let chip: RecordsInsightChip

    var body: some View {
        HStack(spacing: 5) {
            switch chip.mark {
            case .work: Circle().fill(OWCDesign.recordsWork).frame(width: 7, height: 7)
            case .overtime: Circle().fill(OWCDesign.recordsOvertime).frame(width: 7, height: 7)
            case .planned:
                Circle().strokeBorder(OWCDesign.recordsWork, lineWidth: 1.25).opacity(0.75).frame(width: 7, height: 7)
            }
            Text(chip.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(OWCDesign.control, in: Capsule())
    }
}

/// Wraps chips onto as many lines as they need.
struct OWCFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Five kinds of time, all listed with their numbers, beside one stacked
/// column that fills from the bottom: work, breaks, overtime, own time, sleep.
struct RecordsAllocationCard: View {
    enum Unit { case hours, years }

    let text: AppText
    let title: String
    let share: TimeAllocationShare
    var unit: Unit = .hours
    var footnote: String?

    var body: some View {
        let rows = rows
        let total = max(1, Double(share.dayLengthMs))
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(RecordsCardStyle.title)
                        .foregroundStyle(OWCDesign.primary)
                    Spacer(minLength: 8)
                    Text(totalLabel)
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                }
                HStack(alignment: .top, spacing: 18) {
                    column(rows: rows, total: total)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.reversed()) { row in
                            listRow(row, total: total)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 230)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private struct Row: Identifiable {
        var id: TimeAllocationKind { kind }
        let kind: TimeAllocationKind
        let ms: Int64
    }

    /// Bottom-up: the work family first, then your own time, then sleep.
    private var rows: [Row] {
        let order: [(TimeAllocationKind, Int64)] = [
            (.work, share.workMs), (.workBreak, share.breakMs), (.overtime, share.overtimeMs),
            (.unclassified, share.unclassifiedMs), (.free, share.freeMs), (.sleep, share.sleepMs),
        ]
        let minimum: Int64 = unit == .years ? Int64(0.05 * 365.2425 * 86_400_000) : 0
        return order.filter { $0.1 > minimum || ($0.0 != .unclassified && unit == .hours && $0.0 != .overtime) }
            .map { Row(kind: $0.0, ms: $0.1) }
    }

    private func column(rows: [Row], total: Double) -> some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(0, rows.count - 1)) * 2
            VStack(spacing: 2) {
                ForEach(rows.reversed()) { row in
                    Rectangle()
                        .fill(row.kind.owcColor)
                        .frame(height: max(row.ms > 0 ? 3 : 0, (proxy.size.height - gaps) * CGFloat(Double(row.ms) / total)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 86)
        .background(OWCDesign.control)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous)
                .strokeBorder(OWCDesign.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func listRow(_ row: Row, total: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(row.kind.owcColor).frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text.t(row.kind.titleKey))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value(row.ms))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(text.formatPercent(Double(row.ms) / total * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var totalLabel: String {
        unit == .years
            ? text.t("lifeApproxYearsShort", values: ["years": years(share.dayLengthMs)])
            : text.t("recordsAllocationTotal", values: ["duration": text.formatHours((Double(share.dayLengthMs) / 3_600_000).rounded())])
    }

    private func value(_ ms: Int64) -> String {
        switch unit {
        case .hours: text.formatHours((Double(ms) / 3_600_000).rounded())
        case .years: text.t("lifeApproxYearsShort", values: ["years": years(ms)])
        }
    }

    private func years(_ ms: Int64) -> String {
        text.formatDecimal(Double(ms) / (365.2425 * 86_400_000), fractionDigits: 0...1)
    }
}

/// A forecast amount on its own line, how much of it is already earned, and
/// the eye that hides every amount in the app.
struct RecordsPayCard: View {
    let text: AppText
    let preferences: PreferencesStore
    let title: String
    let total: Double
    let earned: Double?

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(RecordsCardStyle.title)
                        .foregroundStyle(OWCDesign.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OWCEarningsVisibilityButton(preferences: preferences, text: text)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(width: 44, height: 32)
                        .padding(.trailing, -10)
                }
                Text(text.moneyWholeText(total))
                    .font(RecordsCardStyle.amount)
                    .monospacedDigit()
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let earned, total > 0 {
                    let fraction = min(1, max(0, earned / total))
                    OWCProgressCapsule(fraction: fraction, color: OWCDesign.accent)
                        .padding(.top, 8)
                    Text(text.t("recordsIncomeProgress", values: [
                        "amount": text.moneyWholeText(earned),
                        "percent": text.formatPercent(fraction * 100),
                    ]))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
        }
    }
}

struct OWCProgressCapsule: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(OWCDesign.control)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
                }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Life: how much of a whole life is your own, then where the rest goes.
struct RecordsLifeOwnTimeCard: View {
    let text: AppText
    let share: TimeAllocationShare

    var body: some View {
        let ownYears = years(share.freeMs + share.breakMs)
        let hero = text.t("lifeOwnYears", values: ["years": ownYears])
        let emphasis = text.t("lifeApproxYearsBare", values: ["years": ownYears])
        RecordsInsightCard(insight: RecordsInsight(
            eyebrow: text.t("lifeAboutYears", values: ["years": years(share.dayLengthMs, digits: 0...0)]),
            hero: hero,
            heroEmphasis: hero.contains(emphasis) ? emphasis : nil,
            body: text.t("lifeOwnBody", values: [
                "work": years(share.workMs + share.overtimeMs),
                "sleep": years(share.sleepMs),
            ])
        ))
    }

    private func years(_ ms: Int64, digits: ClosedRange<Int> = 0...1) -> String {
        text.formatDecimal(Double(ms) / (365.2425 * 86_400_000), fractionDigits: digits)
    }
}

struct RecordsLifetimeIncomeCard: View {
    let text: AppText
    let preferences: PreferencesStore
    let income: NativeLifetimeIncomeSummary
    let method: String

    var body: some View {
        let total = max(1, income.historicalGross + income.projectedGross)
        let past = income.historicalGross / total
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(text.t("lifeIncomeTitle"))
                        .font(RecordsCardStyle.title)
                        .foregroundStyle(OWCDesign.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OWCEarningsVisibilityButton(preferences: preferences, text: text)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(width: 44, height: 32)
                        .padding(.trailing, -10)
                }
                Text(text.moneyWholeText(income.totalGross))
                    .font(RecordsCardStyle.amount)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Capsule().fill(OWCDesign.accent)
                            .frame(width: max(income.historicalGross > 0 ? 8 : 0, (proxy.size.width - 2) * past))
                        Capsule().fill(OWCDesign.accent.opacity(0.2))
                    }
                }
                .frame(height: 8)
                .padding(.top, 10)
                HStack(alignment: .firstTextBaseline) {
                    Text(text.t("lifeIncomeBeforeToday", values: ["amount": text.moneyWholeText(income.historicalGross)]))
                    Spacer(minLength: 8)
                    Text(text.t("lifeIncomeUntilRetirement", values: ["amount": text.moneyWholeText(income.projectedGross)]))
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
                .padding(.top, 6)
                Text(method)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
        }
    }
}
