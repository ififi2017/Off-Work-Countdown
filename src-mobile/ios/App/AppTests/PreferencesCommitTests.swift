import Foundation
import Testing
@testable import App

@MainActor
@Suite("Preference commits")
struct PreferencesCommitTests {
    @Test("Initial schedule edits remain preferences; onboarding commits its final notification choice once")
    func setupCommit() throws {
        let suite = "InitialPreferencesCommit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)
        ))
        let originalRecords = store.records.state
        store.preferences.applySetupScheduleChange(ScheduleFieldChange(
            startMinutes: 8 * 60, endMinutes: 16 * 60,
            scheduleMode: .rotation, rotationWorkDays: 3, rotationRestDays: 2,
            rotationCycleDay: 2
        ), at: date)
        #expect(store.records.state == originalRecords)
        #expect(!store.session.countdownStarted)
        #expect(store.preferences.rotationCycleDay(at: date) == 2)
        #expect(store.preferences.startMinutes == 8 * 60)
        var notifications = 0
        store.records.onDirty = { notifications += 1 }
        store.preferences.completeSetup(enableNotifications: true)
        let committed = try #require(store.records.state.syncedPreferences)
        #expect(committed.notificationMode == .simple)
        #expect(committed.scheduleMode == .rotation)
        #expect(committed.startMinutes == 8 * 60)
        #expect(committed.editCount == 1)
        #expect(notifications == 1)
        store.preferences.completeSetup(enableNotifications: true)
        #expect(store.records.state.syncedPreferences == committed)
        #expect(notifications == 1)
    }

    private func withStore(_ body: (AppRuntime) throws -> Void) throws {
        let suite = "PreferencesCommit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        try body(store)
    }

    @Test("One interaction creates one preference revision; repeating it changes nothing")
    func compoundCommit() throws {
        try withStore { store in
            let initial = try #require(store.records.state.syncedPreferences)
            var notifications = 0
            store.records.onDirty = { notifications += 1 }
            #expect(store.preferences.applyPreferences {
                $0.salaryAmount = "23000"
                $0.annualBonusMonths = 3
                $0.annualBonusEnabled = true
            }.synchronousResult)
            let committed = store.records.state
            #expect(committed.syncedPreferences?.editCount == initial.editCount + 1)
            #expect(notifications == 1)
            let revision = store.records.revision
            #expect(!store.preferences.applyPreferences {
                $0.salaryAmount = "23000"
                $0.annualBonusMonths = 3
                $0.annualBonusEnabled = true
            }.synchronousResult)
            #expect(store.records.state == committed)
            #expect(store.records.revision == revision)
            #expect(notifications == 1)
        }
    }

    @Test("An invalid compound edit never partially changes settings or the outbox")
    func invalidCommit() throws {
        try withStore { store in
            let original = store.records.state
            let theme = store.preferences.theme
            #expect(!store.preferences.applyPreferences {
                $0.theme = theme == .dark ? .light : .dark
                $0.monthlyWorkingDays = 0
            }.synchronousResult)
            #expect(store.preferences.theme == theme)
            #expect(store.records.state == original)
        }
    }

    @Test("An untouched text field adopts incoming values; a dirty field preserves its edit")
    func incomingSettingsDuringEditing() throws {
        try withStore { store in
            var amount = SettingsFieldDraft("")
            var bonus = SettingsFieldDraft(0.0)
            amount.receive(store.preferences.salaryAmount)
            bonus.receive(store.preferences.annualBonusMonths)
            amount.value = "42000"
            store.preferences.applyPreferences {
                $0.salaryAmount = "18000"
                $0.annualBonusMonths = 4
                $0.salaryType = .daily
            }
            amount.receive(store.preferences.salaryAmount)
            bonus.receive(store.preferences.annualBonusMonths)
            #expect(amount.value == "42000")
            #expect(amount.hasChanges)
            #expect(bonus.value == 4)
            #expect(!bonus.hasChanges)
            let submittedAmount = amount.hasChanges ? amount.value : nil
            let submittedBonus = bonus.hasChanges ? bonus.value : nil
            store.preferences.applyPreferences {
                if let submittedAmount { $0.salaryAmount = submittedAmount }
                if let submittedBonus { $0.annualBonusMonths = submittedBonus }
            }
            amount.accept(store.preferences.salaryAmount)
            #expect(!amount.hasChanges)
            #expect(store.preferences.salaryAmount == "42000")
            #expect(store.preferences.annualBonusMonths == 4)
            #expect(store.preferences.salaryType == .daily)
        }
    }

    @Test("An identical schedule does not write records or alter the running session")
    func unchangedSchedule() throws {
        try withStore { store in
            let state = store.records.state
            let signal = ServiceScheduleSignal(shifts: store.shifts)
            let revision = store.records.revision
            store.shifts.applyScheduleChange(
                ScheduleFieldChange(
                    startMinutes: store.preferences.startMinutes,
                    endMinutes: store.preferences.endMinutes,
                    scheduleMode: store.preferences.scheduleMode,
                    lunchEnabled: store.preferences.lunchEnabled
                ),
                decision: .applyToToday
            )
            #expect(store.records.state == state)
            #expect(store.records.revision == revision)
            #expect(ServiceScheduleSignal(shifts: store.shifts) == signal)
        }
    }

    @Test("Sunday settings use the shared rules' zero-based weekday convention")
    func sundayPreferences() throws {
        try withStore { store in
            #expect(store.preferences.applyPreferences {
                $0.recordsTimeZoneIdentifier = "UTC"
                $0.workdays = [0]
                $0.scheduleMode = .classic
                $0.alternatingWeekendWorkday = 0
            }.synchronousResult)
            let sunday = try #require(store.preferences.recordsCalendar.date(from:
                DateComponents(year: 2026, month: 9, day: 6, hour: 10)
            ))
            #expect(store.session.snapshot(at: sunday)?.isWorkday == true)
            #expect(store.records.state.syncedPreferences?.workdays == [0])
            #expect(store.records.state.syncedPreferences?.alternatingWeekendWorkday == 0)
            #expect(store.preferences.applyPreferences { $0.theme = store.preferences.theme == .dark ? .light : .dark }.synchronousResult)
            #expect(!store.preferences.applyPreferences { $0.workdays = [8] }.synchronousResult)
        }
    }
    @Test("Rejected schedule edits preserve the running session and its archive")
    func invalidSchedulePreservesSession() throws {
        try withStore { store in
            store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
            let date = try #require(store.preferences.recordsCalendar.date(from:
                DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
            store.shifts.startCountdown(at: date)
            store.shifts.applyOvertime(date: date.addingTimeInterval(8 * 3600), declaredAt: date)
            let before = store.records.state
            let signal = ServiceScheduleSignal(shifts: store.shifts)
            store.shifts.applyScheduleChange(ScheduleFieldChange(endMinutes: -1),
                decision: .applyToToday, at: date)
            #expect(store.records.state == before)
            #expect(ServiceScheduleSignal(shifts: store.shifts) == signal)
        }
    }

    @Test("A records timezone change and its preference commit notify once; repeating it changes nothing")
    func timeZoneCommit() throws {
        try withStore { store in
            store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
            let date = try #require(store.preferences.recordsCalendar.date(from:
                DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
            store.shifts.startCountdown(at: date)
            var notifications = 0
            store.records.onDirty = { notifications += 1 }
            let target = try #require(TimeZone(identifier: "Asia/Tokyo"))
            store.shifts.migrateRecordsTimeZone(to: target, at: date)
            #expect(notifications == 1)
            #expect(store.preferences.recordsTimeZoneIdentifier == target.identifier)
            #expect(store.records.state.syncedPreferences?.recordsTimeZoneIdentifier == target.identifier)
            #expect(store.session.sessionTimeZoneIdentifier == "UTC")
            #expect(store.records.state.periods.allSatisfy { $0.timeZoneIdentifier == target.identifier })
            let saved = store.records.state
            store.shifts.migrateRecordsTimeZone(to: target, at: date)
            #expect(store.records.state == saved)
            #expect(store.session.sessionTimeZoneIdentifier == "UTC")
            #expect(notifications == 1)
        }
    }

}
