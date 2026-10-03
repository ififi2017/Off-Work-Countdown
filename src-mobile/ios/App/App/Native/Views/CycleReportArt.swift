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
    static let restRun = Gradient(colors: [cream, Color(red: 0.96, green: 0.83, blue: 0.61)])
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
    var previousMood: Mood? = nil
    var blend: Double = 1

    var body: some View {
        // The interior points drift on slow sines so the light is never still.
        let drift = { (phase: Double, amount: Double) in sin(time * 0.35 + phase) * amount }
        let points: [SIMD2<Float>] = [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.5 + drift(1.0, 0.08))],
                [Float(0.5 + drift(2.0, 0.10)), Float(0.5 + drift(3.0, 0.10))],
                [1, Float(0.5 + drift(5.0, 0.08))],
                [0, 1], [Float(0.5 + drift(6.0, 0.08)), 1], [1, 1],
            ]
        ZStack {
            MeshGradient(width: 3, height: 3, points: points, colors: mood.colors, smoothsColors: true)
            if let previousMood, blend < 1 {
                MeshGradient(width: 3, height: 3, points: points, colors: previousMood.colors, smoothsColors: true)
                    .opacity(1 - blend)
            }
        }
        .ignoresSafeArea()
    }
}

/// Draws into a larger surface while retaining the chart's original layout.
/// Blur tails need pixels beyond the plotted bounds, not outer SwiftUI padding.
private struct ReportCanvas: View {
    private let bleed: CGFloat = 40
    var renderer: (inout GraphicsContext, CGSize) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                context.translateBy(x: bleed, y: bleed)
                renderer(&context, geometry.size)
            }
            .frame(width: geometry.size.width + bleed * 2, height: geometry.size.height + bleed * 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
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
    let peak: Double
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
    /// The longest rest stretch, and how much its dates are emphasized.
    var run: Range<Int>?
    var runProgress: Double = 0
    var time: Double = 0

    var body: some View {
        ReportCanvas { context, size in
            draw(&context, size: size)
        }
        // The labels sit in a fixed band; let them grow only so far.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let days = snapshot.days
        let geometry = ReportStripGeometry(kind: snapshot.period.kind, count: days.count, leadingBlanks: leadingBlanks, size: size)
        // Rest glow underneath, so lit days seem to give off light.
        for (i, day) in days.enumerated() where day.kind == .rest && lights[i] > 0.01 {
            let rect = frame(for: i, day: day, geometry: geometry, peak: peak)
            let pulse = 1 + 0.06 * sin(time * 2.2 + Double(i))
            let glow = rect.insetBy(dx: -rect.width * 0.35 * pulse, dy: -rect.width * 0.35 * pulse)
            let emphasis = restEmphasis(for: i)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 10))
                layer.fill(Path(roundedRect: glow, cornerRadius: glow.width / 2),
                           with: .color(ReportPalette.moon.opacity(0.24 * lights[i])))
                if emphasis > 0 {
                    layer.fill(Path(roundedRect: glow, cornerRadius: glow.width / 2),
                               with: .color(ReportPalette.cream.opacity(0.20 * emphasis)))
                }
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
                        layer.opacity *= restEmphasis(for: i)
                        layer.fill(path, with: .linearGradient(ReportPalette.restRun, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
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
    }

    private func restEmphasis(for index: Int) -> Double {
        guard let run, run.count > 1, run.contains(index) else { return 0 }
        return ReportEase.staggered(runProgress, index: index - run.lowerBound, count: run.count, span: 0.8)
    }

    private func frame(for i: Int, day: CycleReportDay, geometry: ReportStripGeometry, peak: Double) -> CGRect {
        let calendar = geometry.calendarRect(i)
        let fraction = day.kind == .work ? Double(day.workMs + day.overtimeMs) / peak : 0
        let bar = geometry.barRect(i, fraction: fraction)
        let m = morphs[i]
        func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
            CGRect(x: ReportEase.lerp(a.minX, b.minX, t), y: ReportEase.lerp(a.minY, b.minY, t),
                   width: ReportEase.lerp(a.width, b.width, t), height: ReportEase.lerp(a.height, b.height, t))
        }
        var rect: CGRect
        if geometry.kind == .month {
            let diameter = bar.width
            let dot = CGRect(x: calendar.midX - diameter / 2, y: calendar.midY - diameter / 2,
                             width: diameter, height: diameter)
            let landing = geometry.barRect(i, fraction: 0)
            // Long columns grow only after every date has reached the baseline.
            // Keeping travelling dates small avoids columns crossing the grid.
            if m < 0.2 {
                rect = interpolate(calendar, dot, OWCMotion.reportMorphCurve.value(at: ReportEase.window(m, 0, 0.2)))
            } else if m < 0.64 {
                rect = interpolate(dot, landing, OWCMotion.reportMorphCurve.value(at: ReportEase.window(m, 0.2, 0.64)))
            } else {
                let growth = ReportEase.staggered(ReportEase.window(m, 0.64, 1), index: i, count: snapshot.days.count, span: 0.85)
                rect = interpolate(landing, bar, ReportEase.outCubic(growth))
            }
        } else {
            rect = interpolate(calendar, bar, m)
        }
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
            guard m < 0.12 else { return }
            let ink = day.kind == .work ? ReportPalette.deep
                : Color.white.mix(with: ReportPalette.deep, by: lights[i])
            context.draw(
                Text("\(dayNumbers[i])")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(ink.opacity(alpha * (1 - ReportEase.window(m, 0, 0.12)))),
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
    let peak: Double

    var body: some View {
        ReportCanvas { context, size in
            let days = snapshot.days
            let count = max(1, days.count)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let inner = outer * 0.58
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

// MARK: - Finish times

/// Each recorded day as a dot against the line of its planned end: on the line
/// when it ended as planned, below it with a trail when overtime pushed it
/// later, above it when the person clocked off early.
struct ReportFinishArt: View {
    let finish: CycleReportFinish
    /// Weekday symbols for a week; a month's dots are too small to label.
    let labels: [String]
    var build: Double

    private static let lateReach: Double = 3 * 3_600_000

    var body: some View {
        ReportCanvas { context, size in
            let days = finish.days
            guard !days.isEmpty else { return }
            let slot = size.width / CGFloat(days.count)
            let dot = max(10, min(30, slot * 0.5))
            let lineY = size.height * 0.42
            let drop = size.height * 0.46 - dot / 2
            let rise = size.height * 0.30 - dot / 2

            // The planned end: a quiet line the dots measure themselves against.
            var line = Path(); line.move(to: CGPoint(x: 0, y: lineY)); line.addLine(to: CGPoint(x: size.width, y: lineY))
            context.stroke(line, with: .color(.white.opacity(0.28 * ReportEase.window(build, 0, 0.2))),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))

            for (i, day) in days.enumerated() {
                let t = ReportEase.staggered(ReportEase.window(build, 0.1, 1), index: i, count: days.count, span: 0.45)
                guard t > 0 else { continue }
                let x = slot * (CGFloat(i) + 0.5)
                let land = ReportEase.outBack(t, 1.3)
                var y = lineY
                var trailColor: Gradient?
                switch day.kind {
                case .onPlan: break
                case .late(let ms):
                    y = lineY + CGFloat(min(1, Double(ms) / Self.lateReach)) * drop * CGFloat(ReportEase.outCubic(t)) + dot * 0.7
                    trailColor = ReportPalette.overtime
                case .early(let ms):
                    y = lineY - CGFloat(min(1, Double(ms) / Self.lateReach)) * rise * CGFloat(ReportEase.outCubic(t)) - dot * 0.7
                    trailColor = Gradient(colors: [ReportPalette.moon, ReportPalette.cream])
                }
                if let trailColor, abs(y - lineY) > 1 {
                    var trail = Path(); trail.move(to: CGPoint(x: x, y: lineY)); trail.addLine(to: CGPoint(x: x, y: y))
                    context.stroke(trail, with: .linearGradient(trailColor, startPoint: CGPoint(x: x, y: lineY), endPoint: CGPoint(x: x, y: y)),
                                   style: StrokeStyle(lineWidth: max(3, dot * 0.22), lineCap: .round))
                }
                let radius = dot / 2 * CGFloat(0.5 + 0.5 * land)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let fill: Gradient = switch day.kind {
                case .onPlan: ReportPalette.work
                case .late: ReportPalette.overtime
                case .early: ReportPalette.rest
                }
                context.drawLayer { layer in
                    layer.opacity = min(1, t * 2)
                    layer.addFilter(.shadow(color: (day.kind == .onPlan ? ReportPalette.orange : ReportPalette.hot).opacity(0.5), radius: 8))
                    layer.fill(Path(ellipseIn: rect), with: .linearGradient(fill, startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: rect.maxY)))
                }
                if labels.indices.contains(i) {
                    context.draw(
                        Text(labels[i]).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6 * min(1, t * 2))),
                        at: CGPoint(x: x, y: size.height - 8), anchor: .center
                    )
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHidden(true)
    }
}

// MARK: - The road ahead

/// The next four weeks as a row of days, rest days lit, with the coming break
/// picked out. Left is tomorrow.
struct ReportHorizonArt: View {
    let ahead: CycleReportAhead
    var build: Double
    var time: Double

    var body: some View {
        ReportCanvas { context, size in
            let flags = ahead.horizon
            guard !flags.isEmpty else { return }
            let slot = size.width / CGFloat(flags.count)
            let width = max(4, slot * 0.62)
            let height: CGFloat = min(size.height * 0.6, 74)
            let baseline = size.height * 0.72
            let breakRange: Range<Int>? = ahead.nextBreak.map { ($0.daysAway - 1)..<($0.daysAway - 1 + $0.length) }

            for (i, rest) in flags.enumerated() {
                let t = ReportEase.outBack(ReportEase.staggered(ReportEase.window(build, 0, 0.8), index: i, count: flags.count, span: 0.35), 1.2)
                guard t > 0 else { continue }
                let inBreak = breakRange?.contains(i) ?? false
                let lit = inBreak ? ReportEase.outCubic(ReportEase.window(build, 0.72, 1)) : 0
                let h = (rest ? height * 0.78 : height * 0.5) * CGFloat(min(1.15, t))
                let rect = CGRect(x: slot * (CGFloat(i) + 0.5) - width / 2, y: baseline - h, width: width, height: h)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                if lit > 0.01 {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 10))
                        layer.fill(Path(roundedRect: rect.insetBy(dx: -width * 0.5, dy: -width * 0.5), cornerRadius: width),
                                   with: .color(ReportPalette.gold.opacity(0.6 * lit * (1 + 0.1 * sin(time * 2.2 + Double(i))))))
                    }
                }
                let base: Color = rest ? ReportPalette.moon.opacity(0.55) : .white.opacity(0.16)
                context.fill(path, with: .color(base))
                if lit > 0.01 {
                    context.fill(path, with: .linearGradient(Gradient(colors: [ReportPalette.cream, ReportPalette.gold]),
                                                             startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                }
            }
            if let range = breakRange, ReportEase.window(build, 0.72, 1) > 0 {
                let progress = ReportEase.outCubic(ReportEase.window(build, 0.8, 1))
                let x0 = slot * CGFloat(range.lowerBound) + slot * 0.1
                let x1 = slot * CGFloat(range.upperBound) - slot * 0.1
                var bracket = Path(); bracket.move(to: CGPoint(x: x0, y: baseline + 14))
                bracket.addLine(to: CGPoint(x: ReportEase.lerp(x0, x1, progress), y: baseline + 14))
                context.stroke(bracket, with: .color(ReportPalette.gold), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Focus

/// Completed focus rounds on each day, the best day picked out in gold.
struct ReportFocusArt: View {
    let focus: CycleReportFocus
    let labels: [String]
    var build: Double

    var body: some View {
        ReportCanvas { context, size in
            let counts = focus.perDay
            let n = counts.count
            guard n > 0 else { return }
            let peak = CGFloat(max(1, counts.max() ?? 1))
            let slot = size.width / CGFloat(n)
            let width = max(4, min(40, slot * 0.6))
            let labelBand: CGFloat = labels.isEmpty ? 0 : 26
            let area = size.height - labelBand - 22
            for (i, count) in counts.enumerated() {
                let t = ReportEase.outBack(ReportEase.staggered(ReportEase.window(build, 0.05, 1), index: i, count: n, span: 0.5), 1.25)
                let h = max(width, CGFloat(count) / peak * area) * CGFloat(max(0, t))
                let rect = CGRect(x: slot * (CGFloat(i) + 0.5) - width / 2, y: size.height - labelBand - h, width: width, height: h)
                let best = i == focus.bestDayIndex
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                if count == 0 {
                    context.fill(Path(ellipseIn: CGRect(x: rect.midX - width / 2, y: size.height - labelBand - width, width: width, height: width)),
                                 with: .color(.white.opacity(0.12)))
                } else {
                    if best {
                        context.drawLayer { layer in
                            layer.addFilter(.blur(radius: 10))
                            layer.fill(path, with: .color(ReportPalette.gold.opacity(0.4)))
                        }
                    }
                    context.fill(path, with: .linearGradient(
                        best ? Gradient(colors: [ReportPalette.cream, ReportPalette.gold]) : Gradient(colors: [.white.opacity(0.55), .white.opacity(0.22)]),
                        startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                    if t > 0.9, slot > 18 {
                        context.draw(Text("\(count)").font(.footnote.weight(.bold).monospacedDigit()).foregroundStyle(.white.opacity(0.9)),
                                     at: CGPoint(x: rect.midX, y: rect.minY - 12), anchor: .center)
                    }
                }
                if labels.indices.contains(i) {
                    context.draw(Text(labels[i]).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6)),
                                 at: CGPoint(x: slot * (CGFloat(i) + 0.5), y: size.height - 8), anchor: .center)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHidden(true)
    }
}
