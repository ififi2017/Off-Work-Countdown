import Foundation
import Testing
@testable import App

/// Plan 021 P1: the shared rule fixture both platforms run. Swift is the
/// specification; Android A1 reads the JSON from its test resources.
@Suite("Workplace automation shared fixture")
nonisolated struct WorkplaceAutomationFixtureTests {
    struct Fixture: Decodable {
        struct Shift: Decodable { let start: String; let end: String; let segments: [[String]] }
        struct Arrival: Decodable { let name: String; let at: String; let delayMinutes: Int; let expect: String; let promptAt: String? }
        struct Match: Decodable { let name: String; let at: String; let expect: String }
        struct Exit: Decodable { let name: String; let at: String; let expect: String; let overtimeMinutes: Int?; let reason: String? }
        struct Segments: Decodable { let name: String; let start: String; let end: String; let expect: [[String]] }
        struct Status: Decodable {
            let name: String; let arrival: String?; let now: String; let expect: String
            let confirmed: Bool?; let context: String?; let leave: Bool?
        }
        struct Leaves: Decodable { let name: String; let exiting: String?; let inside: [String]; let expect: Bool }

        let version: Int
        let shift: Shift
        let arrival: [Arrival]
        let matchArrival: [Match]
        let exit: [Exit]
        let segments: [Segments]
        let statusPrompt: [Status]
        let leavesAllWorkplaces: [Leaves]
    }

    /// Compiled in from the shared JSON (see the generator), so it is
    /// present wherever the tests run. An undecodable copy fails `version`.
    static let fixture: Fixture? = try? JSONDecoder().decode(
        Fixture.self, from: Data(WorkplaceAutomationFixtureData.json.utf8)
    )

    /// "HH:mm" on 2026-11-09 UTC, or "+1 HH:mm" for the next day.
    private static func time(_ value: String) -> Date {
        var text = value
        var day = 9
        if text.hasPrefix("+1 ") { day = 10; text.removeFirst(3) }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: parts[0], minute: parts[1]))!
    }

    private static func segment(_ pair: [String]) -> NativeShiftSegment {
        NativeShiftSegment(startAtMs: time(pair[0]).timeIntervalSince1970 * 1_000,
                           endAtMs: time(pair[1]).timeIntervalSince1970 * 1_000)
    }

    private static let shift = AutomationShift(
        shiftKey: "2026-11-09#fixture", anchorDayKey: "2026-11-09",
        plannedStart: time(fixture?.shift.start ?? "09:00"), plannedEnd: time(fixture?.shift.end ?? "18:00"),
        segments: (fixture?.shift.segments ?? []).map(segment)
    )

    @Test("The fixture decodes and is the version this build understands")
    func version() throws { #expect(try #require(Self.fixture).version == 1) }

    @Test("Arrivals: early, on time or late", arguments: WorkplaceAutomationFixtureTests.fixture?.arrival.map(\.name) ?? [])
    func arrival(_ name: String) throws {
        let item = try #require(Self.fixture?.arrival.first { $0.name == name })
        let delay = try #require(WorkplaceVisitPromptDelay(rawValue: item.delayMinutes))
        let result = WorkplaceAutomationRules.assessArrival(at: Self.time(item.at), for: Self.shift, promptDelay: delay)
        switch item.expect {
        case "early": #expect(result == .early(promptAt: Self.time(try #require(item.promptAt))))
        case "punctual": #expect(result == .punctual)
        default: #expect(result == .late)
        }
    }

    @Test("Arrivals find their shift only inside the window", arguments: WorkplaceAutomationFixtureTests.fixture?.matchArrival.map(\.name) ?? [])
    func matchArrival(_ name: String) throws {
        let item = try #require(Self.fixture?.matchArrival.first { $0.name == name })
        let result = WorkplaceAutomationRules.matchArrival(at: Self.time(item.at), among: [Self.shift])
        #expect(result == (item.expect == "matched" ? .matched(Self.shift) : .noShift))
    }

    @Test("Exits: a break, the end, or review", arguments: WorkplaceAutomationFixtureTests.fixture?.exit.map(\.name) ?? [])
    func exit(_ name: String) throws {
        let item = try #require(Self.fixture?.exit.first { $0.name == name })
        let result = WorkplaceAutomationRules.assessExit(at: Self.time(item.at), for: Self.shift)
        switch item.expect {
        case "temporaryAbsence": #expect(result == .temporaryAbsence)
        case "shiftEnded": #expect(result == .shiftEnded(overtime: TimeInterval(try #require(item.overtimeMinutes) * 60)))
        default:
            let reason = try #require(item.reason.flatMap(AutomationReviewReason.init(rawValue:)))
            #expect(result == .needsReview(reason))
        }
    }

    @Test("Adopted segments keep real gaps", arguments: WorkplaceAutomationFixtureTests.fixture?.segments.map(\.name) ?? [])
    func segments(_ name: String) throws {
        let item = try #require(Self.fixture?.segments.first { $0.name == name })
        let result = WorkplaceAutomationRules.proposedSegments(
            for: Self.shift, start: Self.time(item.start), end: Self.time(item.end)
        )
        #expect(result == item.expect.map(Self.segment))
    }

    @Test("The once-per-shift status question", arguments: WorkplaceAutomationFixtureTests.fixture?.statusPrompt.map(\.name) ?? [])
    func statusPrompt(_ name: String) throws {
        let item = try #require(Self.fixture?.statusPrompt.first { $0.name == name })
        let result = WorkplaceAutomationRules.statusPrompt(
            for: Self.shift,
            knownArrival: item.arrival.map(Self.time),
            workConfirmed: item.confirmed ?? false,
            context: item.context.flatMap(WorkDayContext.init(rawValue:)) ?? .regular,
            isFullDayLeave: item.leave ?? false,
            now: Self.time(item.now)
        )
        let expected: AutomationStatusPrompt = switch item.expect {
        case "statusUnconfirmed": .statusUnconfirmed
        case "lateArrival": .lateArrival
        default: .none
        }
        #expect(result == expected)
    }

    @Test("Leaving one workplace is not leaving work", arguments: WorkplaceAutomationFixtureTests.fixture?.leavesAllWorkplaces.map(\.name) ?? [])
    func leavesAll(_ name: String) throws {
        let item = try #require(Self.fixture?.leavesAllWorkplaces.first { $0.name == name })
        let ids = ["A": UUID(), "B": UUID()]
        let result = WorkplaceAutomationRules.leavesAllWorkplaces(
            exitingWorkplace: item.exiting.flatMap { ids[$0] },
            inside: Set(item.inside.compactMap { ids[$0] })
        )
        #expect(result == item.expect)
    }
}
