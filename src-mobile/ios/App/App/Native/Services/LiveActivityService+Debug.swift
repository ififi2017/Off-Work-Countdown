#if DEBUG
@preconcurrency import ActivityKit
import Foundation

extension LiveActivityService {
    /// Creates a short, real-time capture activity without changing the user's
    /// saved schedule. The attributes retain the requested 09:00–19:00 shift;
    /// the content uses a fifteen-minute segment so the system timer can be
    /// recorded immediately.
    func startDebugLiveActivity(
        shifts: ShiftSessionStore,
        now: Date = .now
    ) async throws {
        await endAll()

        let calendar = Calendar.current
        let shiftStart = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        let plannedEnd = calendar.date(
            bySettingHour: 19,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        let captureEnd = now.addingTimeInterval(15 * 60)
        let attributes = OffWorkActivityAttributes(
            shiftStartAtMs: Int64(shiftStart.timeIntervalSince1970 * 1_000),
            plannedEndAtMs: Int64(plannedEnd.timeIntervalSince1970 * 1_000)
        )
        let state = OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(captureEnd.timeIntervalSince1970 * 1_000),
            progress: 0,
            segments: [
                .init(
                    startAtMs: Int64(now.timeIntervalSince1970 * 1_000),
                    endAtMs: Int64(captureEnd.timeIntervalSince1970 * 1_000)
                ),
            ],
            phase: "working",
            locale: shifts.preferences.languageCode,
            appTitle: OWCBrand.shortName,
            caption: shifts.text.t("timeLeftCaption"),
            completedCaption: shifts.text.t("offWorkTime"),
            completedNote: shifts.text.t("offWorkWellDone")
        )
        let content = ActivityContent(
            state: state,
            staleDate: captureEnd,
            relevanceScore: 100
        )
        _ = try Activity<OffWorkActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil,
            style: .standard
        )
    }
}
#endif
