import SwiftUI

/// 3.3.0 What's New: one workday told in nine seconds. The person walks
/// into the workplace circle, the clock-in is recorded on its own, the day
/// runs, they leave and the clock-out (with overtime) is recorded too. Driven
/// by elapsed time rather than state, so it loops, previews in Canvas and
/// holds a single finished frame under Reduce Motion.
struct WhatsNewAutomationHero: View {
    let text: AppText
    /// Pinned to one moment for previews and screenshots.
    var frozenAt: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static let loop: Double = 9

    var body: some View {
        Group {
            if let frozenAt {
                stage(t: frozenAt)
            } else if reduceMotion {
                stage(t: 7.2)
            } else {
                TimelineView(.animation) { context in
                    stage(t: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop))
                }
            }
        }
        .aspectRatio(1.18, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.t("whatsNewAutomationHeroLabel"))
    }

    // MARK: Story

    /// Where the person is, in unit coordinates of the map.
    private func person(at t: Double) -> CGPoint {
        // Stops beside the building, not on it, so both stay visible.
        let home = CGPoint(x: 0.1, y: 0.86), office = CGPoint(x: 0.6, y: 0.56), out = CGPoint(x: 0.9, y: 0.9)
        if t < 0.4 { return home }
        if t < 1.9 { return lerp(home, office, ease((t - 0.4) / 1.5)) }
        if t < 5.0 { return office }
        if t < 6.5 { return lerp(office, out, ease((t - 5.0) / 1.5)) }
        return out
    }

    private func isInside(_ t: Double) -> Bool { t >= 1.6 && t < 5.5 }

    /// 09:02 → 19:15 while the day runs.
    private func clockMinutes(at t: Double) -> Double {
        let start = 9 * 60 + 2.0, end = 19 * 60 + 15.0
        if t < 2.2 { return start }
        if t > 5.4 { return end }
        return start + (end - start) * ease((t - 2.2) / 3.2)
    }

    /// Share of the day bar drawn: work up to the planned 19:00, then overtime.
    private func dayFill(at t: Double) -> (work: Double, overtime: Double) {
        let minutes = clockMinutes(at: t)
        let start = 9 * 60 + 2.0, planned = 19 * 60.0, end = 19 * 60 + 15.0
        let work = min(1, max(0, (minutes - start) / (planned - start)))
        let overtime = min(1, max(0, (minutes - planned) / (end - planned)))
        return (work, overtime)
    }

    /// The whole frame fades at the loop seam so the reset never jumps.
    private func seamOpacity(_ t: Double) -> Double {
        if t < 0.35 { return t / 0.35 }
        if t > Self.loop - 0.45 { return max(0, (Self.loop - t) / 0.45) }
        return 1
    }

    // MARK: Stage

    private func stage(t: Double) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let mapHeight = size.height * 0.74
            ZStack(alignment: .top) {
                map(t: t, size: CGSize(width: size.width, height: mapHeight))
                VStack(spacing: 0) {
                    banners(t: t)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                    footer(t: t)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
            .opacity(seamOpacity(t))
        }
        .background(stageColor, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    private var stageColor: Color { colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.955) }

    private func map(t: Double, size: CGSize) -> some View {
        let office = CGPoint(x: size.width * 0.5, y: size.height * 0.46)
        let outer = min(size.width, size.height) * 0.36
        let inner = outer * 0.6
        let point = person(at: t)
        let dot = CGPoint(x: point.x * size.width, y: point.y * size.height)
        let entered = t >= 1.6 && t < 2.6 ? (t - 1.6) : nil
        return ZStack {
            // A few quiet streets, enough to read as a map.
            Canvas { context, canvasSize in
                var streets = Path()
                streets.move(to: CGPoint(x: 0, y: canvasSize.height * 0.66))
                streets.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.52))
                streets.move(to: CGPoint(x: canvasSize.width * 0.3, y: 0))
                streets.addLine(to: CGPoint(x: canvasSize.width * 0.24, y: canvasSize.height))
                streets.move(to: CGPoint(x: canvasSize.width * 0.74, y: 0))
                streets.addLine(to: CGPoint(x: canvasSize.width * 0.8, y: canvasSize.height))
                context.stroke(streets, with: .color(.primary.opacity(0.07)), lineWidth: 10)
            }
            Circle()
                .fill(OWCDesign.accent.opacity(isInside(t) ? 0.09 : 0.05))
                .frame(width: outer * 2, height: outer * 2)
                .position(office)
            Circle()
                .strokeBorder(OWCDesign.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .frame(width: outer * 2, height: outer * 2)
                .position(office)
            Circle()
                .fill(OWCDesign.accent.opacity(isInside(t) ? 0.16 : 0.08))
                .frame(width: inner * 2, height: inner * 2)
                .position(office)
            // The moment of arrival: one ring, not a fireworks display.
            if let entered {
                Circle()
                    .stroke(OWCDesign.accent.opacity(0.5 * (1 - entered)), lineWidth: 2)
                    .frame(width: inner * 2 * (1 + entered * 0.5), height: inner * 2 * (1 + entered * 0.5))
                    .position(office)
            }
            Image(systemName: "building.2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(OWCDesign.accent, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .position(office)
            // The familiar "you are here" dot.
            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .position(dot)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Banners

    @ViewBuilder private func banners(t: Double) -> some View {
        ZStack(alignment: .top) {
            banner(
                symbol: "figure.walk.arrival",
                body: text.t("whatsNewAutomationArriveBanner", values: ["time": time(9 * 60 + 2)]),
                visible: t >= 1.8 && t < 4.4
            )
            banner(
                symbol: "figure.walk.departure",
                body: text.t("whatsNewAutomationLeaveBanner", values: [
                    "time": time(19 * 60 + 15),
                    "duration": text.formatRelativeDuration(15 * 60_000),
                ]),
                visible: t >= 5.7 && t < Self.loop - 0.5
            )
        }
        .animation(reduceMotion || frozenAt != nil ? nil : .spring(duration: 0.45, bounce: 0.18), value: t >= 1.8 && t < 4.4)
        .animation(reduceMotion || frozenAt != nil ? nil : .spring(duration: 0.45, bounce: 0.18), value: t >= 5.7)
    }

    @ViewBuilder private func banner(symbol: String, body: String, visible: Bool) -> some View {
        if visible {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(OWCDesign.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: OWCBrand.shortName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    Text(body)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OWCDesign.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Footer

    private func footer(t: Double) -> some View {
        let fill = dayFill(at: t)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: time(clockMinutes(at: t)))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                Label(text.t("whatsNewAutomationLowPower"), systemImage: "leaf.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
            // The day as Records will show it: work, then overtime.
            GeometryReader { bar in
                let overtimeShare = 0.12
                let workWidth = bar.size.width * (1 - overtimeShare)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    HStack(spacing: 2) {
                        Capsule().fill(OWCDesign.recordsWork)
                            .frame(width: max(0, workWidth * fill.work))
                        if fill.overtime > 0 {
                            Capsule().fill(OWCDesign.recordsOvertime)
                                .frame(width: max(0, (bar.size.width * overtimeShare - 2) * fill.overtime))
                        }
                    }
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: Helpers

    private func time(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded(.down))
        var components = DateComponents()
        components.hour = whole / 60
        components.minute = whole % 60
        let date = Calendar.current.date(from: components) ?? .now
        return text.formatTime(date)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }
}
