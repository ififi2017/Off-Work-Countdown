import Foundation
import Observation

@MainActor
@Observable
final class LifeSummaryModel {
    let queries: RecordsQueries
    private let readPreferences: (Date) -> LifeSummaryPreferences
    @ObservationIgnored private let lifeSummaryCache: LifeSummaryCacheStore
    private var records: RecordCoordinator { queries.records }
    private var recordsCalendar: Calendar { queries.recordsCalendar }
    private var recordsTimeZone: TimeZone { queries.recordsTimeZone }

    init(
        queries: RecordsQueries,
        readPreferences: @escaping (Date) -> LifeSummaryPreferences,
        lifeSummaryCache: LifeSummaryCacheStore = .shared
    ) {
        self.queries = queries
        self.readPreferences = readPreferences
        self.lifeSummaryCache = lifeSummaryCache
    }

    /// Merge the editor's fields into the latest profile. Sleep provenance
    /// changes when its value/source changes, not whenever another field saves.
    @discardableResult
    func applyProfileEdit(
        at date: Date = .now,
        _ changes: @escaping @MainActor (inout LifeProfile) -> Void
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            let previous = records.state.lifeProfile
            var profile = previous ?? LifeProfile(editedAt: date, editCount: 0, editTieBreaker: UUID())
            changes(&profile)
            if profile.sleepSource == .manual {
                let unchanged = previous?.sleepSource == .manual
                    && previous?.averageSleepMinutes == profile.averageSleepMinutes
                    && previous?.averageSleepHours == profile.averageSleepHours
                profile.sleepSourceUpdatedAt = unchanged ? previous?.sleepSourceUpdatedAt : date
            }
            records.updateLifeProfile(profile)
            return true
        }
    }

    /// Life spans a career, so its model costs two orders of magnitude more
    /// than any other Records window. Nothing about it changes between two
    /// visits to the tab on the same day with the same archive, and it used to
    /// be rebuilt from scratch on every one of them.
    @ObservationIgnored
    private var lifeViewModelCache: (key: LifeViewModelCacheKey, model: LifeViewModel?)?
    @ObservationIgnored
    private let lifeInputsCache = LifeSummaryInputsCache()
    @discardableResult
    func saveLifeProfile(
        birthYear: Int?,
        workStartedYear: Int?,
        retirementAge: Int?,
        sleepHours: Double?,
        hidesExactAges: Bool
    ) -> RecordCommand<Bool> {
        saveLifeProfileV2(
            bornOn: birthYear.map { .yearOnly($0) },
            schoolStartedOn: nil,
            workStartedOn: workStartedYear.flatMap { year in
                PartialCivilDate.exact(year: year, month: 7, day: 1) ?? .yearOnly(year)
            },
            retirementOn: {
                guard let birthYear, let retirementAge else { return nil }
                return .yearOnly(birthYear + retirementAge)
            }(),
            sleepHours: sleepHours
        )
    }

    @discardableResult
    func saveLifeProfileV2(
        bornOn: PartialCivilDate?,
        schoolStartedOn: PartialCivilDate?,
        workStartedOn: PartialCivilDate?,
        retirementOn: PartialCivilDate?,
        sleepHours: Double?
    ) -> RecordCommand<Bool> {
        applyProfileEdit { [self] profile in
            profile.bornOn = bornOn
            profile.schoolStartedOn = schoolStartedOn
            profile.workStartedPartial = workStartedOn
            profile.retirementOn = retirementOn
            profile.birthYear = bornOn?.year
            profile.workStartedOn = workStartedOn?.calculationAnchor(in: recordsCalendar)
            if let born = bornOn?.year, let retire = retirementOn?.year {
                profile.retirementAge = retire - born
            } else {
                profile.retirementAge = nil
            }
            profile.averageSleepHours = sleepHours
            if let sleepHours {
                profile.averageSleepMinutes = Int((sleepHours * 60).rounded())
                profile.sleepSource = .manual
            }
        }
    }

    /// Whether the life grid may print years on screen.
    var hidesLifeAges: Bool {
        records.state.lifeProfile?.hidesExactAges ?? false
    }

    // Publish only from the background refresh flow. The internal cache stays
    // observation-ignored because legacy synchronous getters also populate it.
    private(set) var cachedLifeViewModel: LifeViewModel?
    @ObservationIgnored private var restoredLifeCache = false
    @ObservationIgnored private var refreshGeneration: UInt64 = 0
    @ObservationIgnored private var reconciledRefreshInput: LifeSummaryRefreshInput?

    /// External archive replacement is published synchronously. Invalidate
    /// every derived value in that same transaction and reserve deletion before
    /// a replacement profile can start producing its newer cache.
    @discardableResult
    func reconcileExternalState(at date: Date = .now) -> Task<Void, Never>? {
        let input = lifeSummaryRefreshInput(now: date)
        if let reconciledRefreshInput {
            guard input != reconciledRefreshInput else { return nil }
        } else if records.state.lifeProfile != nil {
            // A lazily created owner with a profile has no stale in-memory
            // projection, and its disk value will still be checked by key.
            reconciledRefreshInput = input
            return nil
        }
        reconciledRefreshInput = input
        refreshGeneration &+= 1
        lifeViewModelCache = nil
        cachedLifeViewModel = nil
        // The archive has changed underneath any disk value already present.
        // Build from the newly published state instead of restoring that value.
        restoredLifeCache = true
        guard records.state.lifeProfile == nil,
              let url = records.lifeSummaryCacheURL else { return nil }
        return lifeSummaryCache.enqueueRemove(at: url)
    }

    func refreshLifeSummary(now: Date = .now) async {
        guard !Task.isCancelled else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard records.state.lifeProfile != nil else {
            lifeViewModelCache = nil
            cachedLifeViewModel = nil
            if let url = records.lifeSummaryCacheURL { await lifeSummaryCache.remove(at: url) }
            return
        }
        if !restoredLifeCache {
            restoredLifeCache = true
            if let url = records.lifeSummaryCacheURL,
               let cached = await lifeSummaryCache.read(from: url),
               !Task.isCancelled, generation == refreshGeneration,
               cached.key == lifeViewModelCacheKey(now: now), lifeViewModelCache == nil {
                lifeViewModelCache = (cached.key, cached.model)
                cachedLifeViewModel = cached.model
            }
        }
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        let model = await prepareLifeViewModel(now: now)
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        cachedLifeViewModel = model
        reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
    }

    func lifeSummaryRefreshInput(now: Date = .now) -> LifeSummaryRefreshInput {
        let preferences = readPreferences(now)
        return LifeSummaryRefreshInput(
            projectionRevision: records.projectionRevision,
            dayKey: RecordJSON.dayKey(now, calendar: recordsCalendar),
            timeZoneIdentifier: recordsTimeZone.identifier,
            hours: preferences.hours,
            salary: preferences.salary
        )
    }

    func lifeViewModelCacheKey(now: Date) -> LifeViewModelCacheKey {
        lifeInputsCache.key(for: records.state, input: lifeSummaryRefreshInput(now: now),
            cacheAllowed: !records.hasUncommittedProjectionChanges)
    }

    func lifeViewModel(now: Date = .now) -> LifeViewModel? {
        let cacheKey = lifeViewModelCacheKey(now: now)
        if let cached = lifeViewModelCache, cached.key == cacheKey { return cached.model }
        let model = LaunchTrace.interval("lifeBuildModel") { buildLifeViewModel(now: now) }
        lifeViewModelCache = (cacheKey, model)
        reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
        return model
    }

    /// What a Life build needs once the main actor has done its half: the
    /// profile, the in-memory career archive, and every schedule expansion the
    /// day walk will ask for. Nothing in here reads the store, so the rest of
    /// the build does not have to run on the main actor.
    nonisolated private struct LifeBuildInputs: Sendable {
        var profile: LifeProfile
        var calendar: Calendar
        var outsideZoneDays: Set<String>
        var workStart: Date
        var finalDay: Date
        var periods: [CareerPeriod]
        var snapshots: [ScheduleSnapshot]
        var exceptions: [CalendarException]
        var overrides: [DayOverride]
        var expansions: ScheduleExpansionTable
        var observationsByDay: [String: [WorkObservation]]
    }

    /// A life with no career to walk — retirement is not after the work start —
    /// is built from the profile's stage dates alone, and is cheap enough to
    /// stay wherever it is asked for.
    nonisolated private enum LifeBuildPlan: Sendable {
        case noProfile
        case stagesOnly(profile: LifeProfile, calendar: Calendar, outsideZoneDays: Set<String>)
        case career(LifeBuildInputs)
    }

    /// The main-actor half of a Life build, in one place so the synchronous and
    /// off-main-actor builders cannot drift on the guards or the archive.
    private func lifeBuildPlan(now: Date) -> LifeBuildPlan {
        guard var profile = records.state.lifeProfile else { return .noProfile }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        let outsideZoneDays = Set(queries.daysRecordedOutsidePeriodTimeZone())
        guard let lifeStart = profile.bornOn?.calculationAnchor(in: calendar),
              let lifeEnd = profile.retirementOn?.calculationAnchor(in: calendar),
              lifeEnd > lifeStart
        else { return .noProfile }
        let configuredWorkStart = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn
            ?? calendar.date(byAdding: .year, value: 22, to: lifeStart)
            ?? now
        let workStart = max(lifeStart, configuredWorkStart)
        guard workStart < lifeEnd else {
            return .stagesOnly(
                profile: profile,
                calendar: calendar,
                outsideZoneDays: outsideZoneDays
            )
        }
        let archive = queries.lifeScheduleArchive(workStart: workStart, now: now)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: lifeEnd))
            ?? lifeEnd
        return .career(
            LifeBuildInputs(
                profile: profile,
                calendar: calendar,
                outsideZoneDays: outsideZoneDays,
                workStart: workStart,
                finalDay: finalDay,
                periods: archive.periods,
                snapshots: archive.snapshots,
                exceptions: records.state.exceptions,
                overrides: records.state.overrides,
                expansions: queries.gatherScheduleExpansions(
                    from: workStart,
                    through: finalDay,
                    periods: archive.periods,
                    snapshots: archive.snapshots
                ),
                observationsByDay: queries.observationIndex()
            )
        )
    }

    private func buildLifeViewModel(now: Date) -> LifeViewModel? {
        var model = Self.assembleLifePlan(lifeBuildPlan(now: now), now: now)
        if var profile = records.state.lifeProfile {
            profile.migrateLegacyFields(calendar: recordsCalendar)
            model?.income = lifeIncomeSummary(profile: profile, now: now, calendar: recordsCalendar)
        }
        return model
    }

    nonisolated private static func assembleLifePlan(_ plan: LifeBuildPlan, now: Date) -> LifeViewModel? {
        switch plan {
        case .noProfile:
            return nil
        case let .stagesOnly(profile, calendar, outsideZoneDays):
            return Self.assembleStagesOnly(
                profile: profile,
                calendar: calendar,
                outsideZoneDays: outsideZoneDays,
                now: now
            )
        case let .career(inputs):
            return Self.assembleLifeViewModel(inputs, now: now)
        }
    }

    nonisolated private static func assembleStagesOnly(
        profile: LifeProfile,
        calendar: Calendar,
        outsideZoneDays: Set<String>,
        now: Date
    ) -> LifeViewModel {
        LifeViewCalculator.build(
            profile: profile,
            scheduleDays: [],
            outsideZoneDays: outsideZoneDays,
            now: now,
            calendar: calendar
        )
    }

    /// The career walk and the week-cell assembly, with no store access left in
    /// either. This is the ~15,700-day half.
    nonisolated private static func assembleLifeViewModel(
        _ inputs: LifeBuildInputs,
        now: Date
    ) -> LifeViewModel {
        let scheduleDays = RecordsQueries.walkResolutions(
            from: inputs.calendar.startOfDay(for: inputs.workStart),
            through: inputs.calendar.startOfDay(for: inputs.finalDay),
            calendar: inputs.calendar,
            periods: inputs.periods,
            snapshots: inputs.snapshots,
            exceptions: inputs.exceptions,
            overrides: inputs.overrides,
            expansions: inputs.expansions
        ).compactMap { resolution in
            LifeScheduleDay(
                resolution: resolution,
                overtimeSegments: (inputs.observationsByDay[resolution.dayKey] ?? []).compactMap {
                    RecordsMetrics.declaredOvertimeSegment(
                        observation: $0,
                        day: resolution,
                        avoidingRegularWork: true
                    )
                }
            )
        }
        return LifeViewCalculator.build(
            profile: inputs.profile,
            scheduleDays: scheduleDays,
            outsideZoneDays: inputs.outsideZoneDays,
            now: now,
            calendar: inputs.calendar
        )
    }

    @concurrent
    nonisolated private static func assembleLifePlanOffMainActor(
        _ plan: LifeBuildPlan, now: Date
    ) async -> LifeViewModel? {
        assembleLifePlan(plan, now: now)
    }

    private func lifeIncomeSummary(
        profile: LifeProfile,
        now: Date,
        calendar: Calendar
    ) -> NativeLifetimeIncomeSummary? {
        guard let retirement = profile.retirementOn?.calculationAnchor(in: calendar) else { return nil }
        let asOf = RecordJSON.dayKey(now, calendar: calendar)
        let salary = profile.roughCurrentSalary
            ?? profile.employmentPeriods.first(where: { $0.endsOn == nil })?.salary
        // Current preferences only project forward. Prior employment salaries
        // stay exactly as entered in the life archive.
        let configuredMonthly = readPreferences(now).salary.enabled
            ? queries.rulesInput(at: now).flatMap { try? CountdownRules.shared.salaryMonthlyEquivalent(input: $0).amount }
            : nil
        let projectedSalary = configuredMonthly.flatMap { amount in
            amount > 0 ? LifeSalary(amount: amount, cadence: .monthly) : nil
        } ?? salary
        var currentSalaryStartsOn = asOf
        let periods: [NativeLifetimeIncomePeriod]
        switch profile.workHistoryMode {
        case .rough:
            let start = profile.workStartedPartial
                ?? profile.suggestedWorkYear.map(PartialCivilDate.yearOnly)
            guard let start,
                  let salary,
                  salary.isValid,
                  let startsOn = lifeCivilDay(start, calendar: calendar)
            else { return nil }
            currentSalaryStartsOn = max(startsOn, asOf)
            periods = [NativeLifetimeIncomePeriod(
                startsOn: startsOn,
                endsOn: asOf,
                salaryAmount: salary.amount,
                salaryCadence: salary.cadence.rawValue
            )]
        case .detailed:
            periods = profile.employmentPeriods.compactMap { period in
                guard period.salary.isValid,
                      let startsOn = lifeCivilDay(period.startsOn, calendar: calendar)
                else { return nil }
                return NativeLifetimeIncomePeriod(
                    startsOn: startsOn,
                    endsOn: period.endsOn.flatMap { lifeCivilDay($0, calendar: calendar) } ?? asOf,
                    salaryAmount: period.salary.amount,
                    salaryCadence: period.salary.cadence.rawValue
                )
            }
            guard !periods.isEmpty || salary?.isValid == true else { return nil }
        }
        return try? CountdownRules.shared.lifetimeIncome(input: .init(
            periods: periods,
            currentSalary: projectedSalary.map {
                NativeLifetimeIncomeSalary(
                    salaryAmount: $0.amount,
                    salaryCadence: $0.cadence.rawValue,
                    startsOn: currentSalaryStartsOn
                )
            },
            futureIncomeDecline: profile.futureIncomeDecline.flatMap { decline in
                guard let birthYear = profile.bornOn?.year ?? profile.birthYear,
                      let startsOn = lifeCivilDay(
                        .yearOnly(birthYear + decline.startsAtAge),
                        calendar: calendar
                      )
                else { return nil }
                return NativeLifetimeIncomeDecline(
                    startsOn: startsOn,
                    retirementRatio: decline.retirementRatio
                )
            },
            asOf: asOf,
            retirementOn: RecordJSON.dayKey(retirement, calendar: calendar)
        ))
    }

    private func lifeCivilDay(_ value: PartialCivilDate, calendar: Calendar) -> String? {
        value.calculationAnchor(in: calendar).map { RecordJSON.dayKey($0, calendar: calendar) }
    }

    /// Warms every schedule expansion needed by Life off the main actor, then
    /// builds the model off the main actor too.
    func prepareLifeViewModel(now: Date = .now) async -> LifeViewModel? {
        // Before the prefetch, not only inside the builder: decoding a
        // configuration and expanding off the main actor once per snapshot is
        // itself worth skipping when the answer is already known.
        if let cached = lifeViewModelCache, cached.key == lifeViewModelCacheKey(now: now) {
            reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
            return cached.model
        }
        guard var profile = records.state.lifeProfile else { return nil }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        let currentKey = lifeViewModelCacheKey(now: now)
        if let cached = lifeViewModelCache, cached.key.hasSameSchedule(as: currentKey) {
            var model = cached.model
            model?.income = lifeIncomeSummary(profile: profile, now: now, calendar: calendar)
            lifeViewModelCache = (currentKey, model)
            if let model, let url = records.lifeSummaryCacheURL {
                await lifeSummaryCache.write(.init(key: currentKey, model: model), to: url)
            }
            guard !Task.isCancelled else { return nil }
            guard currentKey == lifeViewModelCacheKey(now: now) else {
                return await prepareLifeViewModel(now: now)
            }
            reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
            return model
        }
        guard let lifeStart = profile.bornOn?.calculationAnchor(in: calendar),
              let lifeEnd = profile.retirementOn?.calculationAnchor(in: calendar),
              lifeEnd > lifeStart
        else { return nil }
        let configuredWorkStart = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn
            ?? calendar.date(byAdding: .year, value: 22, to: lifeStart)
            ?? now
        let workStart = max(lifeStart, configuredWorkStart)
        guard workStart < lifeEnd else { return lifeViewModel(now: now) }
        let finalDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: lifeEnd))
            ?? lifeEnd
        let archive = queries.lifeScheduleArchive(workStart: workStart, now: now)

        let prefetch = LaunchTrace.signposter.beginInterval("lifePrefetch")
        for snapshot in archive.snapshots {
            guard let period = archive.periods.first(where: { $0.id == snapshot.periodID }),
                  period.startsOn <= finalDay,
                  period.endsBefore.map({ $0 > workStart }) ?? true,
                  snapshot.effectiveFrom <= finalDay,
                  let configuration = try? JSONDecoder().decode(
                    ScheduleHoursConfiguration.self,
                    from: snapshot.configurationData
                  )
            else { continue }
            let periodCalendar = period.civilCalendar()
            await ScheduleExpansionCache.shared.prefetch(
                configuration: configuration,
                from: periodCalendar.startOfDay(for: workStart),
                through: periodCalendar.startOfDay(for: finalDay),
                timeZone: period.timeZone
            )
        }
        LaunchTrace.signposter.endInterval("lifePrefetch", prefetch)
        // The life canvas only needs the profile's stage dates, so it can be on
        // screen before the career is walked. Yielding lets the scale change
        // that asked for this commit its own frame first.
        await Task.yield()
        // Re-check after the awaits: another task can have built and cached the
        // same model while the prefetch was running.
        if let cached = lifeViewModelCache, cached.key == lifeViewModelCacheKey(now: now) {
            reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
            return cached.model
        }
        guard !Task.isCancelled else { return nil }
        let key = lifeViewModelCacheKey(now: now)
        var model = await Self.assembleLifePlanOffMainActor(lifeBuildPlan(now: now), now: now)
        guard !Task.isCancelled else { return nil }
        guard key == lifeViewModelCacheKey(now: now) else {
            return await prepareLifeViewModel(now: now)
        }
        if var profile = records.state.lifeProfile {
            profile.migrateLegacyFields(calendar: recordsCalendar)
            model?.income = lifeIncomeSummary(profile: profile, now: now, calendar: recordsCalendar)
        }
        lifeViewModelCache = (key, model)
        if let model, let url = records.lifeSummaryCacheURL {
            await lifeSummaryCache.write(.init(key: key, model: model), to: url)
        }
        guard !Task.isCancelled else { return nil }
        guard key == lifeViewModelCacheKey(now: now) else {
            return await prepareLifeViewModel(now: now)
        }
        reconciledRefreshInput = lifeSummaryRefreshInput(now: now)
        return model
    }

}
