import Foundation
import Testing
#if os(watchOS)
@testable import DoneAtWatchApp
#else
@testable import App
#endif

@Suite("Independent Watch schedule")
struct WatchIndependentScheduleTests {
    private func date(_ value: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 * 1_000)
    }
    private func schedule(zone: String = "Asia/Shanghai", plan: ExtendedSchedulePlan? = nil) -> WatchScheduleV2 {
        .init(configuration: .init(startTime: "09:00", endTime: "17:00", nowMs: 0, workdays: [1,2,3,4,5],
              schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                              singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
              breakStartTime: "12:00", breakDurationMinutes: 60, overtimeEndAtMs: nil,
              forcedWorkdayStartMs: nil, timeZoneIdentifier: zone, extendedSchedule: plan),
              automaticallyRuns: true, isConfigured: true, currentShift: nil, currentUntilMs: 0,
              presentation: .init(localeIdentifier: "en", timeZoneIdentifier: zone, workingLabel: "Working",
                                  lunchLabel: "Break", restingLabel: "Rest", overtimeLabel: "Overtime", finishedLabel: "Finished"))
    }
    private func package(_ schedule: WatchScheduleV2, revision: UInt64 = 1, schemaVersion: Int = 2) -> WatchSnapshotPackageV1 {
        .init(schemaVersion: schemaVersion, sourceGeneration: "phone", revision: revision,
              generatedAtMs: date("2026-09-18T00:00:00Z"), expiresAtMs: WatchSnapshotContract.maximumJSONTimestamp,
              access: .init(schemaVersion: 1, revision: 0, verifiedAtMs: 0, status: .free, validUntilMs: nil),
              content: nil, schedule: schedule)
    }

    @Test("One delivery continues across a weekend, months and years without expiring")
    func offlineRecurrence() throws {
        let value = package(schedule())
        for day in ["2026-09-18", "2026-09-21", "2026-10-05", "2027-09-20", "2036-09-22"] {
            let now = date(day + "T02:00:00Z")
            guard case .content(let display) = WatchDisplayProjection.project(value, nowMs: now) else {
                Issue.record("A valid local schedule must remain usable at \(day)"); continue
            }
            #expect(display.phase == .working)
            #expect(display.remainingMs == Int64(6 * 3_600_000))
        }
        let weekend = WatchDisplayProjection.project(value, nowMs: date("2026-09-20T02:00:00Z"))
        guard case .content(let rest) = weekend else { Issue.record("Weekend must remain readable"); return }
        #expect(rest.phase == nil)
        #expect(rest.nextShiftStartAtMs == date("2026-09-21T01:00:00Z"))
    }

    @Test("Breaks and daylight-saving use the same local rules on both devices")
    func breakAndDST() {
        let value = package(schedule(zone: "America/New_York"))
        for now in ["2026-10-30T16:15:00Z", "2026-11-02T17:15:00Z"] {
            guard case .content(let display) = WatchDisplayProjection.project(value, nowMs: date(now)) else {
                Issue.record("Expected locally resolved break"); continue
            }
            #expect(display.phase == .resting)
            #expect(display.remainingMs == Int64(4 * 3_600_000))
        }
    }

    @Test("An overnight shift remains current across its civil-day boundary")
    func overnight() {
        let zone = "Asia/Shanghai"
        let configuration = ScheduleRuleInput(
            startTime: "22:00", endTime: "06:00", nowMs: 0, workdays: [1,2,3,4,5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                            singleWeekendWorkday: nil, rotationAnchorMs: nil,
                            rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: zone)
        let value = package(.init(
            configuration: configuration, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0,
            presentation: schedule(zone: zone).presentation))
        guard case .content(let display) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-21T18:00:00Z")) else {
            Issue.record("Expected the Monday overnight shift after local midnight"); return
        }
        #expect(display.phase == .working)
        #expect(display.remainingMs == Int64(4 * 3_600_000))
    }

    @Test("Rotation recurrence remains deterministic without another phone delivery")
    func rotation() {
        let anchor = date("2026-09-01T00:00:00Z")
        let configuration = ScheduleRuleInput(
            startTime: "09:00", endTime: "17:00", nowMs: 0, workdays: [],
            schedule: .init(mode: "rotation", referenceWeekStartMs: nil, referenceWeekType: nil,
                            singleWeekendWorkday: nil, rotationAnchorMs: Double(anchor),
                            rotationWorkDays: 2, rotationRestDays: 2),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC")
        let value = package(.init(
            configuration: configuration, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0,
            presentation: schedule(zone: "UTC").presentation))
        for instant in ["2026-09-01T10:00:00Z", "2027-09-21T10:00:00Z"] {
            guard case .content(let display) = WatchDisplayProjection.project(value, nowMs: date(instant)) else {
                Issue.record("Expected rotation workday at \(instant)"); continue
            }
            #expect(display.phase == .working)
        }
        guard case .content(let rest) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-03T10:00:00Z")) else {
            Issue.record("Expected rotation rest day"); return
        }
        #expect(rest.phase == nil)
    }

    @Test("A frozen current shift ends before the recurring configuration takes over")
    func currentOverrideScope() {
        let current = WatchShiftProjectionV1(
            segments: [.init(startAtMs: date("2026-09-21T10:00:00Z"), endAtMs: date("2026-09-21T20:00:00Z"))],
            plannedEndAtMs: date("2026-09-21T20:00:00Z"), overtimeEndAtMs: nil,
            finishedAtMs: nil, isRunning: true,
            transitions: [.init(atMs: date("2026-09-21T10:00:00Z"), state: .working),
                          .init(atMs: date("2026-09-21T20:00:00Z"), state: .finished)])
        let value = package(.init(
            configuration: schedule(zone: "UTC").configuration,
            automaticallyRuns: true, isConfigured: true, currentShift: current,
            currentUntilMs: date("2026-09-22T00:00:00Z"),
            presentation: schedule(zone: "UTC").presentation))
        guard case .content(let during) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-21T19:00:00Z")),
              case .content(let after) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-22T01:00:00Z")) else {
            Issue.record("Expected both override projections"); return
        }
        #expect(during.effectiveEndAtMs == date("2026-09-21T20:00:00Z"))
        #expect(during.remainingMs == 3_600_000)
        #expect(after.effectiveEndAtMs == date("2026-09-22T17:00:00Z"))
        #expect(after.phase == .before)
    }

    @Test("An overlapping scheduled shift stays discarded until recurrence resumes")
    func overlappingNextShift() {
        let base = ScheduleRuleInput(
            startTime: "22:00", endTime: "06:00", nowMs: 0, workdays: [1,2,3,4,5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                            singleWeekendWorkday: nil, rotationAnchorMs: nil,
                            rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC")
        let current = WatchShiftProjectionV1(
            segments: [.init(startAtMs: date("2026-09-21T22:00:00Z"), endAtMs: date("2026-09-22T23:00:00Z"))],
            plannedEndAtMs: date("2026-09-22T06:00:00Z"),
            overtimeEndAtMs: date("2026-09-22T23:00:00Z"), finishedAtMs: nil, isRunning: true,
            transitions: [.init(atMs: date("2026-09-21T22:00:00Z"), state: .working),
                          .init(atMs: date("2026-09-22T06:00:00Z"), state: .overtime),
                          .init(atMs: date("2026-09-22T23:00:00Z"), state: .finished)])
        let resume = date("2026-09-23T22:00:00Z")
        let value = package(.init(
            configuration: base, automaticallyRuns: true, isConfigured: true,
            currentShift: current, currentUntilMs: date("2026-09-23T00:00:00Z"),
            resumeAtMs: resume, presentation: schedule(zone: "UTC").presentation))
        guard case .content(let waiting) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-23T01:00:00Z")),
              case .content(let resumed) = WatchDisplayProjection.project(value, nowMs: resume),
              case .content(let following) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-24T07:00:00Z")),
              case .content(let weekend) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-26T12:00:00Z")) else {
            Issue.record("Expected waiting and resumed recurrence"); return
        }
        #expect(waiting.phase == nil)
        #expect(waiting.nextShiftStartAtMs == resume)
        #expect(resumed.phase == .working)
        #expect(following.nextShiftStartAtMs == date("2026-09-24T22:00:00Z"))
        #expect(weekend.nextShiftStartAtMs == date("2026-09-28T22:00:00Z"))
    }

    @Test("Early finish settles at midnight and keeps the next shift cached")
    func earlyFinishResume() {
        let finished = date("2026-09-21T14:00:00Z")
        let resume = date("2026-09-22T09:00:00Z")
        let current = WatchShiftProjectionV1(
            segments: [.init(startAtMs: date("2026-09-21T09:00:00Z"), endAtMs: date("2026-09-21T17:00:00Z"))],
            plannedEndAtMs: date("2026-09-21T17:00:00Z"), overtimeEndAtMs: nil,
            finishedAtMs: finished, isRunning: false,
            transitions: [.init(atMs: date("2026-09-21T09:00:00Z"), state: .working),
                          .init(atMs: finished, state: .finished)])
        let value = package(.init(
            configuration: schedule(zone: "UTC").configuration,
            automaticallyRuns: true, isConfigured: true, currentShift: current,
            currentUntilMs: date("2026-09-22T00:00:00Z"), resumeAtMs: resume,
            presentation: schedule(zone: "UTC").presentation))
        guard case .content(let settled) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-21T15:00:00Z")),
              case .content(let waiting) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-22T01:00:00Z")) else {
            Issue.record("Expected settled and waiting early-finish states"); return
        }
        #expect(settled.phase == .finished)
        #expect(settled.nextShiftStartAtMs == resume)
        #expect(waiting.phase == nil)
        #expect(waiting.nextShiftStartAtMs == resume)
    }

    @Test("V2 wire has no entitlement or salary fields and round-trips through the decoder")
    func privateWire() throws {
        let value = package(schedule())
        let bytes = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["access"] == nil)
        #expect(object["content"] == nil)
        let string = try #require(String(data: bytes, encoding: .utf8))
        #expect(!string.contains("salary"))
        #expect(!string.contains("earned"))
        #expect(try WatchSnapshotDecoderV1.decode(bytes) == value)
    }

    @Test("Free roster round-trip carries the nearest authored month across future months and years")
    func rosterCarryOverRoundTrip() throws {
        let early = ShiftType(
            id: UUID(), name: "Early", kind: .work, startMinutes: 8 * 60, endMinutes: 16 * 60,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#123456", isArchived: false)
        let late = ShiftType(
            id: UUID(), name: "Late", kind: .work, startMinutes: 10 * 60, endMinutes: 18 * 60,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#654321", isArchived: false)
        let plan = ExtendedSchedulePlan(
            shiftTypes: [early, late], rule: nil,
            handSetDays: ["2026-08-03": early.id, "2026-11-03": late.id])
        let original = package(schedule(zone: "UTC", plan: plan))
        let decoded = try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(original))
        #expect(decoded.access.status == .free)

        for (instant, expectedEnd) in [
            ("2026-10-03T11:00:00Z", "2026-10-03T16:00:00Z"),
            ("2026-11-03T11:00:00Z", "2026-11-03T18:00:00Z"),
            ("2026-12-03T11:00:00Z", "2026-12-03T18:00:00Z"),
            ("2037-01-03T11:00:00Z", "2037-01-03T18:00:00Z")
        ] {
            guard case .content(let display) = WatchDisplayProjection.project(decoded, nowMs: date(instant)) else {
                Issue.record("Expected carried roster shift at \(instant)"); continue
            }
            #expect(display.phase == .working)
            #expect(display.effectiveEndAtMs == date(expectedEnd))
        }
    }

    @Test("Alternating weekends continue offline from the serialized reference week")
    func alternatingWeekends() throws {
        let anchor = date("2026-09-14T00:00:00Z")
        let configuration = ScheduleRuleInput(
            startTime: "09:00", endTime: "17:00", nowMs: 0, workdays: [1,2,3,4,5],
            schedule: .init(mode: "alternating", referenceWeekStartMs: Double(anchor),
                            referenceWeekType: "single", singleWeekendWorkday: 6,
                            rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC")
        let value = try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(package(.init(
            configuration: configuration, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0,
            presentation: schedule(zone: "UTC").presentation))))
        guard case .content(let firstSaturday) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-19T10:00:00Z")),
              case .content(let doubleWeekend) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-26T10:00:00Z")),
              case .content(let nextSingleSaturday) = WatchDisplayProjection.project(
                value, nowMs: date("2026-10-03T10:00:00Z")) else {
            Issue.record("Expected alternating weekend projections"); return
        }
        #expect(firstSaturday.phase == .working)
        #expect(doubleWeekend.phase == nil)
        #expect(nextSingleSaturday.phase == .working)
    }

    @Test("V2 accepts frozen roster types and base fallback without accepting mismatched assignments")
    func extendedPlanCompatibility() throws {
        let type = ShiftType(
            id: UUID(), name: "Historical", kind: .work, startMinutes: 10 * 60,
            endMinutes: 18 * 60, breakEnabled: false, breakStartMinutes: 0,
            breakDurationMinutes: 0, colorHex: "#112233", isArchived: true)
        let key = "2026-09-21"
        let plan = ExtendedSchedulePlan(
            shiftTypes: [], rule: nil, handSetDays: [key: type.id],
            frozenShiftTypes: [key: type], fallsBackToBaseSchedule: true)
        let value = package(schedule(zone: "UTC", plan: plan))
        #expect(value.isValid)
        #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(value)) == value)

        guard case .content(let exact) = WatchDisplayProjection.project(
            value, nowMs: date("2026-09-21T11:00:00Z")),
              case .content(let fallback) = WatchDisplayProjection.project(
                value, nowMs: date("2026-09-22T10:00:00Z")) else {
            Issue.record("Expected frozen and fallback shifts"); return
        }
        #expect(exact.effectiveEndAtMs == date("2026-09-21T18:00:00Z"))
        #expect(fallback.effectiveEndAtMs == date("2026-09-22T17:00:00Z"))

        let mismatch = ExtendedSchedulePlan(
            shiftTypes: [], rule: nil, handSetDays: [key: UUID()],
            frozenShiftTypes: [key: type], fallsBackToBaseSchedule: true)
        #expect(schedule(zone: "UTC", plan: mismatch).isValid == false)
    }

    @Test("Timeline includes a later shift even when the app was never opened again")
    func futureTimeline() {
        let value = package(schedule())
        let now = Date(timeIntervalSince1970: Double(date("2026-09-20T00:00:00Z")) / 1_000)
        let times = WatchDisplayProjection.timelineDates(for: value, from: now)
            .map { Int64($0.timeIntervalSince1970 * 1_000) }
        #expect(times.contains(date("2026-09-21T01:00:00Z")))
        #expect(times.contains(date("2026-09-21T04:00:00Z")))
        #expect(times.contains(date("2026-09-21T05:00:00Z")))
        #expect(times.contains(date("2026-09-21T09:00:00Z")))
    }

    @Test("Complication timelines update each minute without dropping shift boundaries")
    func complicationRenderVolume() {
        let value = package(schedule())
        let start = date("2026-09-21T00:02:13Z")
        let now = Date(timeIntervalSince1970: Double(start) / 1_000)
        let dates = WatchDisplayProjection.timelineDates(for: value, from: now)
        let times = dates.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
        // Minute entries cover the next hour; later coverage stays sparse so
        // this ordinary two-day schedule remains well below the old 250 views.
        #expect(dates.count <= 128)
        #expect(times.first == start)
        #expect(times.last == start + 48 * 3_600_000)
        #expect(times == Array(Set(times)).sorted())
        for offset in 1...60 {
            #expect(times.contains(start + Int64(offset) * 60_000))
        }
        for day in ["2026-09-21", "2026-09-22"] {
            for clock in ["01:00:00Z", "04:00:00Z", "05:00:00Z", "09:00:00Z", "16:00:00Z"] {
                #expect(times.contains(date(day + "T" + clock)))
            }
        }
        for time in times {
            guard case .content = WatchDisplayProjection.project(value, nowMs: time) else {
                Issue.record("Every complication entry must resolve from the cached schedule")
                return
            }
        }
    }

    @Test("V2 remains atomic on disk, rejects late revisions and restores after restart")
    func durableSchedule() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "watch.json")
        let cache = await WatchSnapshotCache.open(fileURL: url)
        let hello = await cache.makePairingHello()
        let newest = package(schedule(), revision: 3)
        let reply = WatchPairingReplyV1(schemaVersion: 1, pairingSession: hello.pairingSession, nonce: hello.nonce,
          baseline: .init(schemaVersion: 1, pairingSession: hello.pairingSession, sourceGeneration: "phone", replacesGeneration: nil),
          packageData: try JSONEncoder().encode(newest))
        #expect(await cache.receivePairingReply(try JSONEncoder().encode(reply)) == .accepted)
        #expect(await cache.receiveApplicationContext(try JSONEncoder().encode(package(schedule(), revision: 2))) == .rejected(.rejectStaleRevision))
        let reopened = await WatchSnapshotCache.open(fileURL: url)
        #expect(await reopened.currentPackage() == newest)
    }

    @Test("V3 uses the phone's holiday effects offline and cannot be downgraded to V2")
    func transportedHolidays() async throws {
        let work = ShiftType(id: UUID(), name: "Day", kind: .work,
            startMinutes: 540, endMinutes: 1_020, breakEnabled: false,
            breakStartMinutes: 0, breakDurationMinutes: 0, colorHex: "#F28C28", isArchived: false)
        let plan = ExtendedSchedulePlan(shiftTypes: [work],
            rule: .init(preset: .weekly, anchorDayKey: "2026-09-14", days: Array(repeating: work.id, count: 7)),
            handSetDays: [:], holidayRegionIdentifier: "CN",
            holidayOverrides: [20260919: true, 20260921: false])
        let newest = package(schedule(plan: plan), revision: 3, schemaVersion: 3)
        let decoded = try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(newest))
        #expect(decoded == newest)
        #expect(package(schedule(plan: plan)).isValid == false)
        guard case .content(let saturday) = WatchDisplayProjection.project(decoded, nowMs: date("2026-09-19T02:00:00Z")),
              case .content(let monday) = WatchDisplayProjection.project(decoded, nowMs: date("2026-09-21T02:00:00Z")) else {
            Issue.record("Transported holidays must resolve on either device"); return
        }
        #expect(saturday.phase == .working)
        #expect(monday.phase == nil)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "watch.json")
        let cache = await WatchSnapshotCache.open(fileURL: url)
        let hello = await cache.makePairingHello()
        let reply = WatchPairingReplyV1(schemaVersion: 1, pairingSession: hello.pairingSession, nonce: hello.nonce,
            baseline: .init(schemaVersion: 1, pairingSession: hello.pairingSession, sourceGeneration: "phone", replacesGeneration: nil),
            packageData: try JSONEncoder().encode(package(schedule())))
        #expect(await cache.receivePairingReply(try JSONEncoder().encode(reply)) == .accepted)
        #expect(await cache.receiveApplicationContext(try JSONEncoder().encode(newest)) == .accepted)
        #expect(await cache.receiveApplicationContext(try JSONEncoder().encode(package(schedule(), revision: 4))) == .rejected(.rejectInvalidPackage))
        let restored = await WatchSnapshotCache.open(fileURL: url)
        #expect(await restored.currentPackage() == newest)
    }
    @Test("Sunday makeup starts stay consistent across midnight and both Watch surfaces")
    func holidaySundayAcrossMidnight() throws {
        let workID = UUID(), restID = UUID()
        let work = ShiftType(id: workID, name: "Day", kind: .work,
            startMinutes: 600, endMinutes: 1140, breakEnabled: true,
            breakStartMinutes: 780, breakDurationMinutes: 90, colorHex: "#FF9500", isArchived: false)
        var rest = work
        rest.id = restID
        rest.kind = .rest
        let plan = ExtendedSchedulePlan(shiftTypes: [work, rest],
            rule: .init(preset: .weekly, anchorDayKey: "2026-09-14", days: [workID, workID, workID, workID, workID, restID, restID]),
            handSetDays: [:], holidayRegionIdentifier: "CN", holidayOverrides: [20260920: true])
        let value = package(schedule(plan: plan), schemaVersion: 3)
        let start = date("2026-09-20T02:00:00Z")
        for instant in ["2026-09-19T15:48:00Z", "2026-09-19T16:00:00Z", "2026-09-20T01:59:00Z"] {
            guard case .content(let display) = WatchDisplayProjection.project(value, nowMs: date(instant)) else {
                Issue.record("Expected valid holiday projection"); return
            }
            #expect(display.upcomingShiftStartAtMs == start)
            #expect(WatchDisplayFormat.footnote(for: display)?.atMs == start)
        }
        let dates = WatchDisplayProjection.timelineDates(for: value,
            from: Date(timeIntervalSince1970: Double(date("2026-09-19T15:48:00Z")) / 1000), minuteCount: 0)
            .map { Int64($0.timeIntervalSince1970 * 1000) }
        #expect(dates.contains(date("2026-09-19T16:00:00Z")))
        #expect(dates.contains(start))
        guard case .content(let working) = WatchDisplayProjection.project(value, nowMs: start) else {
            Issue.record("Expected makeup shift to start"); return
        }
        #expect(working.phase == .working)
    }

}
