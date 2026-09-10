import Testing
@testable import App

/// The work countdown is only published for the last 5, 15 or 30 minutes of a
/// shift, so its bar and ring measure that window rather than the whole day.
/// These pin the arithmetic the card draws.
struct LiveActivityWindowTests {
    private static let minute: Int64 = 60_000

    /// 09:00–17:00 with an hour of lunch at noon, as absolute milliseconds.
    private static func shift(
        displayStartAtMs: Int64?,
        progress: Double = 0
    ) -> OffWorkActivityAttributes.ContentState {
        OffWorkActivityAttributes.ContentState(
            endAtMs: 17 * 60 * minute,
            progress: progress,
            segments: [
                .init(startAtMs: 9 * 60 * minute, endAtMs: 12 * 60 * minute),
                .init(startAtMs: 13 * 60 * minute, endAtMs: 17 * 60 * minute),
            ],
            phase: "working",
            locale: "en",
            appTitle: "DoneAt",
            caption: "left today",
            completedCaption: "Off work",
            completedNote: "Well done",
            displayStartAtMs: displayStartAtMs
        )
    }

    @Test func aPayloadWithoutAWindowStillMeasuresTheWholeShift() {
        let state = Self.shift(displayStartAtMs: nil)

        #expect(state.windowSegments == state.segments)
        // Noon is three of the seven effective hours.
        let atNoon = state.windowProgress(atMs: 12 * 60 * Self.minute)
        #expect(abs(atNoon - 3.0 / 7.0 * 100) < 0.001)
    }

    @Test func theWindowKeepsOnlyTheLastStretchOfTheShift() {
        let state = Self.shift(displayStartAtMs: (16 * 60 + 45) * Self.minute)

        #expect(state.windowSegments == [
            .init(startAtMs: (16 * 60 + 45) * Self.minute, endAtMs: 17 * 60 * Self.minute),
        ])
        #expect(state.windowProgress(atMs: (16 * 60 + 45) * Self.minute) == 0)
        #expect(abs(state.windowProgress(atMs: (16 * 60 + 50) * Self.minute) - 100.0 / 3) < 0.001)
        #expect(state.windowProgress(atMs: 17 * 60 * Self.minute) == 100)
    }

    /// The shift's own progress must not become the window's floor. Before
    /// this was split from `projectedProgress`, a payload carrying 96.9% —
    /// which is what the last fifteen minutes of an eight-hour day looks like
    /// — pinned the bar full from the activity's first frame.
    @Test func theShiftsOwnProgressIsNotAFloorForTheWindow() {
        let state = Self.shift(displayStartAtMs: (16 * 60 + 45) * Self.minute, progress: 96.9)

        #expect(state.windowProgress(atMs: (16 * 60 + 45) * Self.minute) == 0)
        #expect(state.projectedProgress(atMs: (16 * 60 + 45) * Self.minute) == 96.9)
    }

    /// A window that opens before lunch ends keeps both stretches, and the gap
    /// between them stays uncounted: the bar holds still over lunch.
    @Test func lunchInsideTheWindowIsStillNotWorkedTime() {
        let state = Self.shift(displayStartAtMs: (11 * 60 + 30) * Self.minute)

        #expect(state.windowSegments == [
            .init(startAtMs: (11 * 60 + 30) * Self.minute, endAtMs: 12 * 60 * Self.minute),
            .init(startAtMs: 13 * 60 * Self.minute, endAtMs: 17 * 60 * Self.minute),
        ])
        // Half an hour of the four and a half in the window.
        let atLunchStart = state.windowProgress(atMs: 12 * 60 * Self.minute)
        #expect(abs(atLunchStart - 0.5 / 4.5 * 100) < 0.001)
        #expect(state.windowProgress(atMs: (12 * 60 + 45) * Self.minute) == atLunchStart)
        #expect(state.windowProgress(atMs: 13 * 60 * Self.minute) == atLunchStart)
    }

    /// Overtime arrives as a longer last segment from the rules bundle, so the
    /// window grows with it rather than sitting full for the extra time.
    @Test func overtimeExtendsTheWindowRatherThanPinningItFull() {
        var state = Self.shift(displayStartAtMs: (16 * 60 + 45) * Self.minute)
        #expect(state.windowProgress(atMs: 17 * 60 * Self.minute) == 100)

        state = OffWorkActivityAttributes.ContentState(
            endAtMs: (17 * 60 + 30) * Self.minute,
            progress: state.progress,
            segments: [
                state.segments[0],
                .init(startAtMs: 13 * 60 * Self.minute, endAtMs: (17 * 60 + 30) * Self.minute),
            ],
            phase: "overtime",
            locale: state.locale,
            appTitle: state.appTitle,
            caption: state.caption,
            completedCaption: state.completedCaption,
            completedNote: state.completedNote,
            displayStartAtMs: state.displayStartAtMs
        )

        // Fifteen minutes of the forty-five the activity now covers.
        #expect(abs(state.windowProgress(atMs: 17 * 60 * Self.minute) - 100.0 / 3) < 0.001)
        #expect(state.windowProgress(atMs: (17 * 60 + 30) * Self.minute) == 100)
    }

    /// A focus payload has no window: its single segment is already the block.
    @Test func aWindowStartingPastEverySegmentFallsBackToTheShift() {
        let state = Self.shift(displayStartAtMs: 23 * 60 * Self.minute)

        #expect(state.windowSegments == state.segments)
    }
}
