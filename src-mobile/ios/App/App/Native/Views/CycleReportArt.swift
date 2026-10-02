import SwiftUI

/// Motion and colour for the report. The report is its own dark stage, like a
/// story: the brand's plum and cream, with the orange doing the work.
enum ReportPalette {
    static let plum = OWCDesign.brandPlum
    static let deep = Color(red: 0.075, green: 0.039, blue: 0.106)
    static let cream = OWCDesign.brandCream
    static let orange = OWCDesign.orange
    static let orangeDeep = OWCDesign.orangeDeep
    /// Overtime: the same orange pushed toward red.
    static let hot = Color(red: 1.0, green: 0.27, blue: 0.22)
    static let moon = Color(red: 0.72, green: 0.68, blue: 0.98)
    static let night = Color(red: 0.16, green: 0.15, blue: 0.40)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.30)

    static let work = Gradient(colors: [cream, orange])
    static let overtime = Gradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.30), hot])
    static let rest = Gradient(colors: [cream, moon])
}

/// Easing for hand-built motion. Everything in a report is a function of the
/// chapter clock, so these are plain maths, not SwiftUI animations; that is what
/// lets a pause, a held finger or a jump land on an exact frame.
nonisolated enum ReportEase {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func inOutCubic(_ x: Double) -> Double {
        let t = clamp(x)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    /// Overshoots a little and settles; the "landing" feel of a spring.
    static func outBack(_ x: Double, _ s: Double = 1.5) -> Double {
        let t = clamp(x) - 1
        return 1 + (s + 1) * t * t * t + s * t * t
    }
    /// Progress of item `index` of `count` when the whole run is at `t`. Items
    /// start one after another and each takes `span` of the run.
    static func staggered(_ t: Double, index: Int, count: Int, span: Double = 0.5) -> Double {
        guard count > 1 else { return clamp(t) }
        let start = Double(index) / Double(count - 1) * (1 - span)
        return clamp((t - start) / span)
    }
    /// The part of `t` between `from` and `to`, as 0 → 1.
    static func window(_ t: Double, _ from: Double, _ to: Double) -> Double {
        clamp((t - from) / max(0.0001, to - from))
    }
}

// MARK: - Backdrop

/// A slow mesh of light behind the chapters. Each chapter has its own mood, and
/// moving between them is a long cross-fade of the mesh, not a cut.
struct ReportBackdrop: View {
    enum Mood {
        case dawn, energy, calm, contrast, gold, finale

        var colors: [Color] {
            switch self {
            case .dawn:
                [ReportPalette.deep, ReportPalette.plum, ReportPalette.deep,
                 ReportPalette.plum, Color(red: 0.42, green: 0.17, blue: 0.22), ReportPalette.plum,
                 ReportPalette.orangeDeep.opacity(0.85), ReportPalette.plum, ReportPalette.deep]
            case .energy:
                [ReportPalette.deep, Color(red: 0.30, green: 0.10, blue: 0.18), ReportPalette.deep,
                 Color(red: 0.36, green: 0.12, blue: 0.16), Color(red: 0.78, green: 0.28, blue: 0.14), Color(red: 0.30, green: 0.09, blue: 0.17),
                 ReportPalette.orange.opacity(0.9), Color(red: 0.62, green: 0.18, blue: 0.14), ReportPalette.plum]
            case .calm:
                [ReportPalette.deep, ReportPalette.night.opacity(0.9), ReportPalette.deep,
                 ReportPalette.night, Color(red: 0.34, green: 0.28, blue: 0.62), ReportPalette.night,
                 Color(red: 0.20, green: 0.17, blue: 0.46), ReportPalette.plum, ReportPalette.deep]
            case .contrast:
                [ReportPalette.deep, ReportPalette.plum, ReportPalette.deep,
                 ReportPalette.plum, Color(red: 0.34, green: 0.17, blue: 0.30), ReportPalette.plum,
                 Color(red: 0.55, green: 0.22, blue: 0.20), ReportPalette.plum, ReportPalette.deep]
            case .gold:
                [ReportPalette.deep, Color(red: 0.24, green: 0.14, blue: 0.10), ReportPalette.deep,
                 Color(red: 0.30, green: 0.17, blue: 0.10), Color(red: 0.70, green: 0.42, blue: 0.12), Color(red: 0.28, green: 0.14, blue: 0.10),
                 ReportPalette.gold.opacity(0.85), Color(red: 0.50, green: 0.26, blue: 0.10), ReportPalette.plum]
            case .finale:
                [ReportPalette.plum, ReportPalette.deep, ReportPalette.plum,
                 Color(red: 0.40, green: 0.16, blue: 0.20), Color(red: 0.20, green: 0.09, blue: 0.20), Color(red: 0.34, green: 0.12, blue: 0.20),
                 ReportPalette.orange.opacity(0.9), ReportPalette.orangeDeep.opacity(0.7), ReportPalette.plum]
            }
        }
    }

    let mood: Mood
    let time: Double

    var body: some View {
        // The interior points drift on slow sines so the light is never still.
        let drift = { (phase: Double, amount: Double) in sin(time * 0.35 + phase) * amount }
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.5 + drift(1.0, 0.08))],
                [Float(0.5 + drift(2.0, 0.10)), Float(0.5 + drift(3.0, 0.10))],
                [1, Float(0.5 + drift(5.0, 0.08))],
                [0, 1], [Float(0.5 + drift(6.0, 0.08)), 1], [1, 1],
            ],
            colors: mood.colors,
            smoothsColors: true
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.4), value: moodIndex)
    }

    private var moodIndex: Int {
        switch mood {
        case .dawn: 0
        case .energy: 1
        case .calm: 2
        case .contrast: 3
        case .gold: 4
        case .finale: 5
        }
    }
}

// MARK: - The days

/// Where each day of a period sits. A day is a pill in one of two places: a
/// calendar slot, and a bar on a common baseline. Chapters move days between
/// the two, which is what makes the statistics look made of the calendar.
struct ReportStripGeometry {
    let kind: CycleReportKind
    let count: Int
    let leadingBlanks: Int
    let size: CGSize

    private var columns: CGFloat { 7 }
    var rows: Int { max(1, Int(ceil(Double(leadingBlanks + count) / 7))) }

    /// Space under the shapes for weekday and date labels (weeks only).
    var labelBand: CGFloat { kind == .week ? 44 : 0 }
    var baseline: CGFloat { size.height - labelBand - (kind == .month ? 4 : 0) }

    func calendarRect(_ i: Int) -> CGRect {
        switch kind {
        case .week:
            let slot = size.width / CGFloat(max(1, count))
            let width = min(slot * 0.66, 46)
            let height = min(baseline, max(168, baseline * 0.74))
            return CGRect(x: slot * (CGFloat(i) + 0.5) - width / 2, y: baseline - height, width: width, height: height)
        case .month:
            let cell = size.width / columns
            let diameter = min(cell * 0.78, 42)
            let slot = leadingBlanks + i
            let gridHeight = CGFloat(rows) * cell
            let top = max(0, (size.height - gridHeight) / 2)
            return CGRect(
                x: CGFloat(slot % 7) * cell + (cell - diameter) / 2,
                y: top + CGFloat(slot / 7) * cell + (cell - diameter) / 2,
                width: diameter, height: diameter
            )
        }
    }

    func barRect(_ i: Int, fraction: Double) -> CGRect {
        let slot = size.width / CGFloat(max(1, count))
        let width = kind == .week ? min(slot * 0.66, 46) : max(4, slot * 0.58)
        let maxHeight = baseline - (kind == .week ? 30 : 8)
        let height = max(width, CGFloat(fraction) * maxHeight)
        return CGRect(x: slot * (CGFloat(i) + 0.5) - width / 2, y: baseline - height, width: width, height: height)
    }
}

/// Draws a period's days. All state comes in as numbers, one per day, so a
/// frame is fully determined by the chapter clock.
struct ReportStripArt: View {
    let snapshot: CycleReportSnapshot
    let weekdaySymbols: [String]
    let leadingBlanks: Int
    let dayNumbers: [Int]
    /// 0 → 1 per day: the day arriving.
    var reveals: [Double]
    /// 0 = calendar slot, 1 = bar.
    var morphs: [Double]
    /// 0 → 1 per day: a rest day lit up.
    var lights: [Double]
    /// 0 → 1: work days sinking into the dark behind the rest.
    var dim: Double = 0
    /// 0 → 1: hours written above each bar (weeks only; a month's bars are too thin).
    var valueLabels: Double = 0
    /// The longest rest stretch, and how much of its underline is drawn.
    var run: Range<Int>?
    var runProgress: Double = 0
    var time: Double = 0

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        // The labels sit in a fixed band; let them grow only so far.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let days = snapshot.days
        let geometry = ReportStripGeometry(kind: snapshot.period.kind, count: days.count, leadingBlanks: leadingBlanks, size: size)
        let peak = Double(max(1, days.map { $0.workMs + $0.overtimeMs }.max() ?? 1))

        // Rest glow underneath, so lit days seem to give off light.
        for (i, day) in days.enumerated() where day.kind == .rest && lights[i] > 0.01 {
            let rect = frame(for: i, day: day, geometry: geometry, peak: peak)
            let pulse = 1 + 0.06 * sin(time * 2.2 + Double(i))
            let glow = rect.insetBy(dx: -rect.width * 0.35 * pulse, dy: -rect.width * 0.35 * pulse)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 16))
                layer.fill(Path(roundedRect: glow, cornerRadius: glow.width / 2),
                           with: .color(ReportPalette.moon.opacity(0.55 * lights[i])))
            }
        }

        for (i, day) in days.enumerated() where reveals[i] > 0.001 {
            let rect = frame(for: i, day: day, geometry: geometry, peak: peak)
            guard rect.width > 0.5, rect.height > 0.5 else { continue }
            let path = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
            let arrive = min(1, reveals[i] * 1.8)
            var alpha = arrive
            switch day.kind {
            case .work:
                alpha *= 1 - 0.8 * dim
                context.drawLayer { layer in
                    layer.opacity = alpha
                    layer.clip(to: path)
                    let overtimeShare = day.overtimeMs > 0
                        ? Double(day.overtimeMs) / Double(day.workMs + day.overtimeMs) : 0
                    let split = rect.maxY - rect.height * (1 - overtimeShare)
                    layer.fill(
                        Path(CGRect(x: rect.minX, y: split, width: rect.width, height: rect.maxY - split + 1)),
                        with: .linearGradient(ReportPalette.work, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY))
                    )
                    if overtimeShare > 0 {
                        layer.fill(
                            Path(CGRect(x: rect.minX, y: rect.minY - 1, width: rect.width, height: split - rect.minY + 1)),
                            with: .linearGradient(ReportPalette.overtime, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: split))
                        )
                    }
                }
            case .rest:
                let lit = lights[i]
                context.drawLayer { layer in
                    layer.opacity = alpha
                    layer.fill(path, with: .color(.white.opacity(0.07)))
                    if lit > 0.01 {
                        layer.opacity = alpha * lit
                        layer.fill(path, with: .linearGradient(ReportPalette.rest, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                    }
                }
                context.stroke(path, with: .color(.white.opacity(0.30 * alpha * (1 - lit))), lineWidth: 1.5)
            case .upcoming:
                context.stroke(path, with: .color(.white.opacity(0.28 * alpha)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            drawLabel(&context, i: i, day: day, geometry: geometry, rect: rect, alpha: alpha)
            if valueLabels > 0.01, geometry.kind == .week, day.kind == .work, morphs[i] > 0.95 {
                let hours = Double(day.workMs + day.overtimeMs) / 3_600_000
                context.draw(
                    Text(hours.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9 * valueLabels * alpha)),
                    at: CGPoint(x: rect.midX, y: rect.minY - 12 + 6 * (1 - valueLabels)), anchor: .center
                )
            }
        }

        if let run, runProgress > 0, let first = run.first, let last = run.last {
            let a = geometry.calendarRect(first), b = geometry.calendarRect(last)
            let y = a.maxY + (snapshot.period.kind == .week ? 12 : 10)
            let start = a.minX + 2, end = b.maxX - 2
            var line = Path()
            line.move(to: CGPoint(x: start, y: y))
            line.addLine(to: CGPoint(x: ReportEase.lerp(start, end, runProgress), y: y))
            context.stroke(line, with: .linearGradient(Gradient(colors: [ReportPalette.cream, ReportPalette.moon]),
                                                        startPoint: CGPoint(x: start, y: y), endPoint: CGPoint(x: end, y: y)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }

    private func frame(for i: Int, day: CycleReportDay, geometry: ReportStripGeometry, peak: Double) -> CGRect {
        let calendar = geometry.calendarRect(i)
        let fraction = day.kind == .work ? Double(day.workMs + day.overtimeMs) / peak : 0
        let bar = geometry.barRect(i, fraction: fraction)
        let m = morphs[i]
        var rect = CGRect(
            x: ReportEase.lerp(calendar.minX, bar.minX, m),
            y: ReportEase.lerp(calendar.minY, bar.minY, m),
            width: ReportEase.lerp(calendar.width, bar.width, m),
            height: ReportEase.lerp(calendar.height, bar.height, m)
        )
        // Arrival: rise from a little below and settle with a small overshoot.
        let r = reveals[i]
        let land = ReportEase.outBack(r)
        let scale = 0.55 + 0.45 * land
        let centre = CGPoint(x: rect.midX, y: rect.midY + (1 - land) * 26)
        rect = CGRect(x: centre.x - rect.width * scale / 2, y: centre.y - rect.height * scale / 2,
                      width: rect.width * scale, height: rect.height * scale)
        return rect
    }

    private func drawLabel(_ context: inout GraphicsContext, i: Int, day: CycleReportDay,
                           geometry: ReportStripGeometry, rect: CGRect, alpha: Double) {
        switch geometry.kind {
        case .week:
            let base = geometry.calendarRect(i)
            let symbol = weekdaySymbols.indices.contains(i % 7) ? weekdaySymbols[i % 7] : ""
            context.draw(
                Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55 * alpha)),
                at: CGPoint(x: base.midX, y: geometry.baseline + 16), anchor: .center
            )
            context.draw(
                Text("\(dayNumbers[i])").font(.footnote.weight(.bold).monospacedDigit()).foregroundStyle(.white.opacity(0.9 * alpha)),
                at: CGPoint(x: base.midX, y: geometry.baseline + 34), anchor: .center
            )
        case .month:
            let m = morphs[i]
            guard m < 0.4 else { return }
            context.draw(
                Text("\(dayNumbers[i])")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle((day.kind == .work ? ReportPalette.deep : Color.white).opacity(alpha * (1 - m * 2.5) * (day.kind == .rest ? 0.7 : 1))),
                at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
            )
        }
    }
}

// MARK: - The ring

/// The period as a clock face: every day a spoke, as long as the time worked.
/// It closes the report with a picture of the whole, and echoes the brand's own
/// open ring.
struct ReportRingArt: View {
    let snapshot: CycleReportSnapshot
    /// 0 → 1 over the build.
    var build: Double
    var time: Double

    var body: some View {
        Canvas { context, size in
            let days = snapshot.days
            let count = max(1, days.count)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let inner = outer * 0.52
            let peak = Double(max(1, days.map { $0.workMs + $0.overtimeMs }.max() ?? 1))
            let spoke = max(3, min(count <= 8 ? 30 : 14, 2 * .pi * inner / CGFloat(count) * 0.56))
            // Spokes are round-capped: leave the cap's radius inside the canvas.
            let reach = outer - inner - 4 - spoke / 2 - 2

            // The faint track the spokes grow from.
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - inner + 2, y: centre.y - inner + 2, width: (inner - 2) * 2, height: (inner - 2) * 2)),
                           with: .color(.white.opacity(0.10)), lineWidth: 1)

            for (i, day) in days.enumerated() {
                let t = ReportEase.outBack(ReportEase.staggered(build, index: i, count: count, span: 0.45), 1.2)
                guard t > 0.001 else { continue }
                let angle = -Double.pi / 2 + (Double(i) + 0.5) / Double(count) * 2 * .pi
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                func point(_ radius: CGFloat) -> CGPoint {
                    CGPoint(x: centre.x + direction.x * radius, y: centre.y + direction.y * radius)
                }
                var slot = Path(); slot.move(to: point(inner + 4)); slot.addLine(to: point(inner + 4 + reach))
                context.stroke(slot, with: .color(.white.opacity(0.06 * t)), style: StrokeStyle(lineWidth: spoke, lineCap: .round))
                switch day.kind {
                case .work:
                    let total = Double(day.workMs + day.overtimeMs)
                    let length = max(spoke, CGFloat(total / peak) * reach) * CGFloat(t)
                    let regular = CGFloat(Double(day.workMs) / max(1, total)) * length
                    var base = Path(); base.move(to: point(inner + 4)); base.addLine(to: point(inner + 4 + regular))
                    context.stroke(base, with: .linearGradient(ReportPalette.work, startPoint: point(inner), endPoint: point(inner + length)),
                                   style: StrokeStyle(lineWidth: spoke, lineCap: .round))
                    if day.overtimeMs > 0 {
                        var top = Path(); top.move(to: point(inner + 4 + regular)); top.addLine(to: point(inner + 4 + length))
                        context.stroke(top, with: .linearGradient(ReportPalette.overtime, startPoint: point(inner + regular), endPoint: point(inner + length)),
                                       style: StrokeStyle(lineWidth: spoke, lineCap: .round))
                    }
                case .rest:
                    let dot = Path(ellipseIn: CGRect(x: point(inner + 8).x - spoke / 2, y: point(inner + 8).y - spoke / 2, width: spoke, height: spoke))
                    context.fill(dot, with: .color(ReportPalette.moon.opacity(0.75 * t)))
                case .upcoming:
                    let dot = Path(ellipseIn: CGRect(x: point(inner + 8).x - spoke / 2, y: point(inner + 8).y - spoke / 2, width: spoke, height: spoke))
                    context.stroke(dot, with: .color(.white.opacity(0.3 * t)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
