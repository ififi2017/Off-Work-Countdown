import SwiftUI
import Testing
@testable import App

@MainActor
@Test("Canvas callouts stay inside the chart and avoid their tapped point at the edges")
func recordsCanvasCalloutEdges() {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 220)
    for size in [CGSize(width: 110, height: 44), CGSize(width: 300, height: 120)] {
        for anchor in [CGRect(x: 0, y: 0, width: 12, height: 12),
                       CGRect(x: 308, y: 208, width: 12, height: 12)] {
            let origin = RecordsCanvasCalloutLayout.origin(for: size, anchor: anchor, in: bounds)
            let label = CGRect(origin: origin, size: size)
            #expect(bounds.contains(label))
            #expect(!label.intersects(anchor))
        }
    }
}

@MainActor
@Test("A canvas selection joins adjacent rows without covering unselected cells")
func recordsCanvasSelectionOutline() {
    let grid = RecordsCanvasGrid(size: CGSize(width: 147, height: 72), targetCell: 12,
                                 gap: 3, minimumColumns: 1, minimumRows: 1)
    let path = grid.selectionPath(for: Array(2..<28))
    for index in 0..<grid.count {
        let rect = grid.rect(at: index)
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)) == (2..<28).contains(index))
    }
    #expect(grid.index(at: CGPoint(x: -0.1, y: 2)) == nil)
    #expect(grid.index(at: CGPoint(x: 2, y: -0.1)) == nil)
}

@MainActor
@Test("Career presentation splits at now without changing the profile interval")
func recordsLifeWorkPeriods() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = Date(timeIntervalSince1970: 3_000)
    let work = LifeStageSpan(kind: .work, start: start, end: end,
                             startPrecision: .year, endPrecision: .year)
    for timestamp in [500.0, 1_000, 2_000, 3_000, 4_000] {
        let now = Date(timeIntervalSince1970: timestamp)
        let spans = LifeStageCalculator.canvasStages([work], now: now)
        #expect(spans.first?.start == start)
        #expect(spans.last?.end == end)
        #expect(Set(spans.map(\.id)).count == spans.count)
        if now > start && now < end {
            #expect(spans.map(\.workPeriod) == [.elapsed, .future])
            #expect(spans.first?.end == now)
            #expect(spans.last?.start == now)
            let buckets = LifeStageCalculator.buckets(stages: spans, from: start, to: end, count: 100, now: now)
            #expect(Set(buckets.map(\.stageID)) == Set(spans.map(\.id)))
        } else {
            #expect(spans.count == 1)
            #expect(spans.first?.workPeriod == (now <= start ? .future : .elapsed))
        }
    }
    var openEnded = work
    openEnded.end = nil
    let known = LifeStageCalculator.canvasStages([openEnded], now: Date(timeIntervalSince1970: 2_000))
    #expect(known.count == 1)
    #expect(known.first?.workPeriod == .elapsed)
    #expect(known.first?.end == Date(timeIntervalSince1970: 2_000))
    #expect(work.end == end)
}
