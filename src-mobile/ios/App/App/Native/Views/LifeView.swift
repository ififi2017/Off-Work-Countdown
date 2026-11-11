import SwiftUI

/// Editing the profile, on its own surface.
struct LifeProfileEditView: View {
    let life: LifeSummaryModel
    let actions: RecordsActions
    let preferences: PreferencesStore
    let text: AppText

    private var queries: RecordsQueries { life.queries }

    private enum FutureIncomeMode: String, CaseIterable, Identifiable {
        case keepCurrent
        case decline

        var id: String { rawValue }
    }

    @State private var bornYear = ""
    @State private var schoolYear = ""
    @State private var workYear = ""
    @State private var retirementAge = ""
    @State private var sleepHours = ""
    @State private var workHistoryMode: LifeWorkHistoryMode = .rough
    @State private var roughSalaryAmount = ""
    @State private var roughSalaryCadence: LifeSalaryCadence = .monthly
    @State private var employmentDrafts: [EmploymentDraft] = []
    @State private var futureIncomeMode: FutureIncomeMode = .keepCurrent
    @State private var declineStartAge = "45"
    @State private var retirementIncomePercent = "60"
    @State private var savedFeedback = 0
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OWCGroupCard {
                        numberRow(text.t("lifeBirthYear"), text: $bornYear, placeholder: "1990", maxDigits: 4)
                        numberRow(
                            text.t("lifeSchoolStarted"),
                            text: $schoolYear,
                            placeholder: suggestedSchoolYear,
                            maxDigits: 4
                        )
                        numberRow(text.t("lifeRetirementAge"), text: $retirementAge, placeholder: "60", maxDigits: 3)
                        numberRow(
                            text.t("lifeSleepHours"),
                            text: $sleepHours,
                            placeholder: "8",
                            maxDigits: 4,
                            decimal: true,
                            isLast: true
                        )
                    }

                    workHistoryEditor
                        .environment(\.calendar, preferences.recordsCalendar)
                        .environment(\.timeZone, preferences.recordsCalendar.timeZone)

                    futureIncomeEditor

                    Text(text.t("lifeProfileFooter"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
            }
            .background(OWCDesign.page)
            .navigationTitle(text.t("lifeProfileTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("saveAction"), action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
            .sensoryFeedback(.success, trigger: savedFeedback)
            .onAppear(perform: load)
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var futureIncomeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text.t("lifeFutureIncomeMode"), selection: $futureIncomeMode) {
                Text(text.t("lifeFutureIncomeKeep")).tag(FutureIncomeMode.keepCurrent)
                Text(text.t("lifeFutureIncomeDecline")).tag(FutureIncomeMode.decline)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(text.t("lifeFutureIncomeMode"))

            if futureIncomeMode == .decline {
                OWCGroupCard {
                    numberRow(
                        text.t("lifeIncomeDeclineStartAge"),
                        text: $declineStartAge,
                        placeholder: "45",
                        maxDigits: 3
                    )
                    numberRow(
                        text.t("lifeIncomeRetirementRatio"),
                        text: $retirementIncomePercent,
                        placeholder: "60",
                        maxDigits: 3,
                        isLast: true
                    )
                }
                if let decline = incomeDecline {
                    Text(text.t("lifeIncomeDeclinePreview", values: [
                        "age": text.formatCount(decline.startsAtAge),
                        "percent": text.formatPercent(decline.retirementRatio * 100, fractionDigits: 0),
                    ]))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var workHistoryEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text.t("lifeWorkHistoryMode"), selection: $workHistoryMode) {
                Text(text.t("lifeWorkHistoryRough")).tag(LifeWorkHistoryMode.rough)
                Text(text.t("lifeWorkHistoryDetailed")).tag(LifeWorkHistoryMode.detailed)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(text.t("lifeWorkHistoryMode"))

            if workHistoryMode == .rough {
                OWCGroupCard {
                    numberRow(
                        text.t("lifeWorkStarted"),
                        text: $workYear,
                        placeholder: suggestedWorkYear,
                        maxDigits: 4
                    )
                    salaryRow(
                        title: text.t("lifeCurrentSalary"),
                        amount: $roughSalaryAmount,
                        cadence: $roughSalaryCadence,
                        isLast: true
                    )
                }
                Text(text.t("lifeRoughIncomeHelp"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            } else {
                Text(text.t("lifeDetailedIncomeHelp"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                if linkedEmploymentPeriods == nil {
                    Text(text.t("lifeEmploymentValidation"))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                ForEach($employmentDrafts) { $draft in
                    employmentCard(
                        $draft,
                        isCurrent: draft.id == employmentDrafts.first?.id,
                        endDate: employmentEndDate(for: draft.id)
                    )
                }
                Button {
                    let previousStart = employmentDrafts.last?.startDate ?? .now
                    employmentDrafts.append(EmploymentDraft(
                        startDate: preferences.recordsCalendar.date(
                            byAdding: .year,
                            value: -1,
                            to: previousStart
                        ) ?? previousStart
                    ))
                } label: {
                    Label(text.t("lifeAddEmployment"), systemImage: "plus")
                }
                .buttonStyle(OWCSecondaryButtonStyle())
            }
        }
    }

    private func numberRow(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        maxDigits: Int,
        decimal: Bool = false,
        isLast: Bool = false
    ) -> some View {
        OWCRow(title: title, isLast: isLast) {
            OWCNumberField(
                placeholder: placeholder,
                text: text,
                decimal: decimal,
                maxDigits: maxDigits,
                width: 84,
                validationMessage: self.text.t("numberInputInvalid", values: ["count": String(maxDigits)]),
                onCommit: {}
            )
        }
    }

    private func salaryRow(
        title: String,
        amount: Binding<String>,
        cadence: Binding<LifeSalaryCadence>,
        isLast: Bool
    ) -> some View {
        OWCRow(title: title, isLast: isLast) {
            HStack(spacing: 8) {
                if preferences.hideEarnings {
                    Text(verbatim: "••••")
                    OWCEarningsVisibilityButton(preferences: preferences, text: text)
                } else {
                    OWCNumberField(
                        placeholder: "0",
                        text: amount,
                        decimal: true,
                        maxDigits: 12,
                        width: 104,
                        validationMessage: text.t("numberInputInvalid", values: ["count": "12"]),
                        onCommit: {}
                    )
                }
                Picker("", selection: cadence) {
                    Text(text.t("lifeSalaryMonthly")).tag(LifeSalaryCadence.monthly)
                    Text(text.t("lifeSalaryYearly")).tag(LifeSalaryCadence.yearly)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(text.t("lifeSalaryCadence"))
            }
        }
    }

    private func employmentCard(
        _ draft: Binding<EmploymentDraft>,
        isCurrent: Bool,
        endDate: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCurrent {
                Text(text.t("lifeEmploymentCurrent"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 20)
            }
            OWCGroupCard {
                VStack(spacing: 0) {
                    OWCRow(title: text.t("lifeEmploymentStart")) {
                        DatePicker(
                            "",
                            selection: draft.startDate,
                            in: employmentStartRange(for: draft.wrappedValue.id),
                            displayedComponents: .date
                        )
                            .labelsHidden()
                            .accessibilityLabel(text.t("lifeEmploymentStart"))
                    }
                    OWCRow(title: text.t("lifeEmploymentEnd")) {
                        if endDate == nil {
                            Text(text.t("lifeStagePresent"))
                                .foregroundStyle(OWCDesign.secondary)
                        } else if let endDate {
                            Text(endDate, format: Date.FormatStyle(
                                date: .abbreviated, time: .omitted,
                                locale: preferences.locale, calendar: preferences.recordsCalendar,
                                timeZone: preferences.recordsCalendar.timeZone
                            ))
                            .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    salaryRow(
                        title: text.t("lifeEmploymentSalary"),
                        amount: isCurrent ? $roughSalaryAmount : draft.salaryAmount,
                        cadence: isCurrent ? $roughSalaryCadence : draft.salaryCadence,
                        isLast: isCurrent
                    )
                    if !isCurrent {
                        Button(role: .destructive) {
                            employmentDrafts.removeAll { $0.id == draft.wrappedValue.id }
                        } label: {
                            OWCRow(icon: "trash", title: text.t("lifeRemoveEmployment"), isLast: true) {
                                EmptyView()
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                }
            }
        }
    }

    private func employmentEndDate(for id: UUID) -> Date? {
        guard let index = employmentDrafts.firstIndex(where: { $0.id == id }) else { return nil }
        let draft = employmentDrafts[index]
        if !draft.linksEndToNext { return draft.endsOn?.calculationAnchor(in: preferences.recordsCalendar) }
        return index == 0 ? nil : employmentDrafts[index - 1].startDate
    }

    private func employmentStartRange(for id: UUID) -> ClosedRange<Date> {
        guard let index = employmentDrafts.firstIndex(where: { $0.id == id }) else {
            return .distantPast ... preferences.recordsCalendar.startOfDay(for: .now)
        }
        let upper = index == 0
            ? preferences.recordsCalendar.startOfDay(for: .now)
            : preferences.recordsCalendar.date(
                byAdding: .day,
                value: -1,
                to: employmentDrafts[index - 1].startDate
            ) ?? employmentDrafts[index - 1].startDate
        guard index + 1 < employmentDrafts.count,
              let lower = preferences.recordsCalendar.date(
                byAdding: .day,
                value: 1,
                to: employmentDrafts[index + 1].startDate
              ),
              lower <= upper
        else { return .distantPast ... upper }
        return lower ... upper
    }

    private func load() {
        var profile = queries.records.state.lifeProfile
        profile?.migrateLegacyFields(calendar: preferences.recordsCalendar)
        workHistoryMode = profile?.workHistoryMode ?? .rough
        if let year = profile?.bornOn?.year ?? profile?.birthYear { bornYear = Self.plain(year) }
        if let year = profile?.schoolStartedOn?.year { schoolYear = Self.plain(year) }
        if let year = profile?.workStartedPartial?.year
            ?? profile?.workStartedOn.map({ preferences.recordsCalendar.component(.year, from: $0) }) {
            workYear = Self.plain(year)
        }
        if let bornYear = profile?.bornOn?.year ?? profile?.birthYear,
           let retirementYear = profile?.retirementOn?.year {
            retirementAge = Self.plain(retirementYear - bornYear)
        } else if let age = profile?.retirementAge {
            retirementAge = Self.plain(age)
        } else {
            retirementAge = "60"
        }
        sleepHours = profile?.averageSleepHours.map(Self.plain) ?? "8"
        if let salary = profile?.roughCurrentSalary
            ?? profile?.employmentPeriods.first(where: { $0.endsOn == nil })?.salary {
            roughSalaryAmount = Self.plain(salary.amount)
            roughSalaryCadence = salary.cadence
        } else if preferences.salaryEnabled,
                  let input = queries.rulesInput(at: .now),
                  let amount = SummaryRules.salaryMonthlyEquivalent(input: input),
                  amount > 0 {
            roughSalaryAmount = Self.plain(amount)
            roughSalaryCadence = .monthly
        }
        let linkedEndIDs = LifeEmploymentTimeline.linkedEndIDs(
            in: profile?.employmentPeriods ?? [], calendar: preferences.recordsCalendar
        )
        employmentDrafts = (profile?.employmentPeriods ?? []).compactMap { period in
            guard var draft = EmploymentDraft(period, calendar: preferences.recordsCalendar) else { return nil }
            draft.linksEndToNext = linkedEndIDs.contains(period.id)
            return draft
        }
        if !employmentDrafts.contains(where: { $0.wasCurrent }) {
            employmentDrafts.append(EmploymentDraft(
                startDate: LifeEmploymentTimeline.inferredCurrentStart(
                    profile: profile,
                    calendar: preferences.recordsCalendar
                ),
                salary: profile?.roughCurrentSalary
            ))
        }
        employmentDrafts.sort { $0.startDate > $1.startDate }
        if let decline = profile?.futureIncomeDecline {
            futureIncomeMode = .decline
            declineStartAge = Self.plain(decline.startsAtAge)
            retirementIncomePercent = Self.plain(decline.retirementRatio * 100)
        }
    }

    private func save() {
        guard !isSaving else { return }
        let bornOn = Int(bornYear).map { PartialCivilDate.yearOnly($0) }
        let retirementOn = {
            guard let birthYear = bornOn?.year,
                  let age = Int(retirementAge) else { return nil as PartialCivilDate? }
            return .yearOnly(birthYear + age)
        }()
        let detailedPeriods = linkedEmploymentPeriods
        guard workHistoryMode == .rough || detailedPeriods != nil else { return }
        let schoolStartedOn = (Int(schoolYear) ?? bornOn.map { $0.year + 6 })
            .map { PartialCivilDate.yearOnly($0) }
        let workStartedPartial = workHistoryMode == .rough
            ? (Int(workYear) ?? bornOn.map { $0.year + 22 }).map { PartialCivilDate.yearOnly($0) }
            : earliestStart(in: detailedPeriods ?? [])
        let retirementAgeValue = Int(retirementAge)
        let sleepHoursValue = Double(sleepHours)
        let historyMode = workHistoryMode
        let roughCurrentSalary = salary(amount: roughSalaryAmount, cadence: roughSalaryCadence)
        let futureIncomeDecline = futureIncomeMode == .decline ? incomeDecline : nil
        isSaving = true
        Task {
            guard await actions.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
                isSaving = false
                return
            }
            let command = life.applyProfileEdit { profile in
                profile.bornOn = bornOn
                profile.schoolStartedOn = schoolStartedOn
                profile.workStartedPartial = workStartedPartial
                profile.retirementOn = retirementOn
                profile.birthYear = bornOn?.year
                profile.workStartedOn = profile.workStartedPartial?.calculationAnchor(in: preferences.recordsCalendar)
                profile.retirementAge = retirementAgeValue
                profile.averageSleepHours = sleepHoursValue
                profile.averageSleepMinutes = sleepHoursValue.map { Int(($0 * 60).rounded()) }
                if profile.averageSleepMinutes != nil {
                    profile.sleepSource = .manual
                }
                profile.workHistoryMode = historyMode
                profile.roughCurrentSalary = roughCurrentSalary
                if historyMode == .detailed, let detailedPeriods {
                    profile.employmentPeriods = detailedPeriods
                }
                profile.futureIncomeDecline = futureIncomeDecline
            }
            guard await command.value else {
                isSaving = false
                return
            }
            savedFeedback += 1
            dismiss()
        }
    }

    private var suggestedSchoolYear: String {
        Int(bornYear).map { Self.plain($0 + 6) } ?? text.t("lifeSuggestedYear")
    }

    private var suggestedWorkYear: String {
        Int(bornYear).map { Self.plain($0 + 22) } ?? text.t("lifeSuggestedYear")
    }

    private var canSave: Bool {
        guard NumberInput.committedText(sleepHours, decimal: true, maxDigits: 4).flatMap(NumberInput.parse) != nil,
              validOptionalYear(bornYear),
              validOptionalYear(schoolYear),
              validOptionalYear(workYear),
              NumberInput.committedText(retirementAge, decimal: false, maxDigits: 3)
                .flatMap(Int.init).map({ (1...120).contains($0) }) == true
        else { return false }
        if !roughSalaryAmount.isEmpty,
           salary(amount: roughSalaryAmount, cadence: roughSalaryCadence) == nil {
            return false
        }
        if futureIncomeMode == .decline {
            guard let decline = incomeDecline,
                  Int(bornYear) != nil,
                  Int(retirementAge).map({ decline.startsAtAge < $0 }) == true
            else { return false }
        }
        return workHistoryMode == .rough || linkedEmploymentPeriods?.count == employmentDrafts.count
    }

    private func validOptionalYear(_ value: String) -> Bool {
        value.isEmpty || NumberInput.committedText(value, decimal: false, maxDigits: 4)
            .flatMap(Int.init).map { (1_000...9_999).contains($0) } == true
    }

    private func salary(amount: String, cadence: LifeSalaryCadence) -> LifeSalary? {
        guard let canonical = NumberInput.committedText(amount, decimal: true, maxDigits: 12),
              let value = NumberInput.parse(canonical), value > 0 else { return nil }
        return LifeSalary(amount: value, cadence: cadence)
    }

    private var incomeDecline: LifeIncomeDecline? {
        guard let age = NumberInput.committedText(declineStartAge, decimal: false, maxDigits: 3).flatMap(Int.init),
              let percent = NumberInput.committedText(retirementIncomePercent, decimal: false, maxDigits: 3).flatMap(NumberInput.parse)
        else { return nil }
        let value = LifeIncomeDecline(startsAtAge: age, retirementRatio: percent / 100)
        return value.isValid ? value : nil
    }

    private func earliestStart(in periods: [LifeEmploymentPeriod]) -> PartialCivilDate? {
        periods.min {
            guard let left = $0.startsOn.calculationAnchor(in: preferences.recordsCalendar) else { return false }
            guard let right = $1.startsOn.calculationAnchor(in: preferences.recordsCalendar) else { return true }
            return left < right
        }?.startsOn
    }

    private var linkedEmploymentPeriods: [LifeEmploymentPeriod]? {
        guard let currentSalary = salary(amount: roughSalaryAmount, cadence: roughSalaryCadence),
              !employmentDrafts.isEmpty
        else { return nil }
        let periods = employmentDrafts.enumerated().compactMap { index, draft in
            draft.period(
                calendar: preferences.recordsCalendar,
                salary: index == 0 ? currentSalary : nil
            )
        }
        guard periods.count == employmentDrafts.count else { return nil }
        return LifeEmploymentTimeline.linkedPeriods(
            periods, calendar: preferences.recordsCalendar,
            linkingEndsFor: Set(employmentDrafts.filter(\.linksEndToNext).map(\.id))
        )
    }

    /// Load canonical text without locale grouping; validation above rejects
    /// malformed drafts without changing them into another value.
    private static func plain(_ value: Int) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func plain(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...1))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    private struct EmploymentDraft: Identifiable, Equatable {
        var id = UUID()
        var startDate: Date
        var salaryAmount = ""
        var salaryCadence: LifeSalaryCadence = .monthly
        var wasCurrent = false
        var endsOn: PartialCivilDate?
        var linksEndToNext = true

        init(startDate: Date, salary: LifeSalary? = nil) {
            self.startDate = startDate
            if let salary {
                salaryAmount = LifeProfileEditView.plain(salary.amount)
                salaryCadence = salary.cadence
            }
        }

        init?(_ period: LifeEmploymentPeriod, calendar: Calendar) {
            guard let startDate = period.startsOn.calculationAnchor(in: calendar) else { return nil }
            id = period.id
            self.startDate = startDate
            salaryAmount = LifeProfileEditView.plain(period.salary.amount)
            salaryCadence = period.salary.cadence
            wasCurrent = period.endsOn == nil
            endsOn = period.endsOn
        }

        func period(calendar: Calendar, salary: LifeSalary? = nil) -> LifeEmploymentPeriod? {
            let starts = calendar.dateComponents([.year, .month, .day], from: startDate)
            guard let year = starts.year, let month = starts.month, let day = starts.day,
                  let startsOn = PartialCivilDate.exact(year: year, month: month, day: day)
            else { return nil }
            let resolvedSalary: LifeSalary
            if let salary {
                resolvedSalary = salary
            } else {
                guard let canonical = NumberInput.committedText(salaryAmount, decimal: true, maxDigits: 12),
                      let amount = NumberInput.parse(canonical), amount > 0 else { return nil }
                resolvedSalary = LifeSalary(amount: amount, cadence: salaryCadence)
            }
            return LifeEmploymentPeriod(
                id: id,
                startsOn: startsOn,
                endsOn: endsOn,
                salary: resolvedSalary
            )
        }
    }
}

extension AppText {
    func lifeIncomeMethodText(decline: LifeIncomeDecline?) -> String {
        guard let decline else {
            return t("lifeIncomeMethod")
        }
        return t("lifeIncomeMethodDecline", values: [
            "age": formatCount(decline.startsAtAge),
            "percent": formatPercent(decline.retirementRatio * 100, fractionDigits: 0),
        ])
    }
}
