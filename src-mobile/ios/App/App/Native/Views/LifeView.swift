import SwiftUI

struct LifeView: View {
    let store: OffWorkStore

    @State private var model: LifeViewModel?
    @State private var income: NativeLifetimeIncomeSummary?
    @State private var loaded = false
    @State private var editing = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let model, !model.cells.isEmpty {
                    summaryCard(model)
                    if let income { incomeCard(income) }
                    gridCard(model)
                    footnotes(model)
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("lifeTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            LifeProfileEditView(store: store)
        }
        .task { await reload() }
        .onChange(of: store.records.revision) { _, _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        let next = await store.prepareLifeViewModel()
        guard !Task.isCancelled else { return }
        model = next
        income = next?.income
        loaded = true
    }

    // MARK: - Summary

    /// The numbers come first. The profile form used to sit permanently above
    /// the grid, so the first screen was four text fields and the point of the
    /// page — the shape of a working life — started below the fold.
    private func summaryCard(_ model: LifeViewModel) -> some View {
        OWCGroupCard {
            VStack(spacing: 0) {
                Grid(horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        summaryItem(store.t("lifeWorkShare"), store.formatPercent(model.workShare * 100))
                        summaryItem(store.t("lifeOwnShare"), store.formatPercent(model.ownAwakeShare * 100))
                    }
                    GridRow {
                        summaryItem(store.t("lifeWeeksWorked"), weeksLabel(model.workedWeeks))
                    }
                }
                .padding(16)

                Button(action: openEditor) {
                    OWCRow(icon: "pencil", title: store.t("lifeEditProfile"), isLast: true) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
        }
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func incomeCard(_ income: NativeLifetimeIncomeSummary) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("lifeIncomeTitle"))
                    .font(.headline)
                    .foregroundStyle(OWCDesign.primary)
                summaryItem(store.t("lifeIncomeHistory"), store.moneyText(income.historicalGross))
                Divider()
                summaryItem(store.t("lifeIncomeFuture"), store.moneyText(income.projectedGross))
                Divider()
                summaryItem(store.t("lifeIncomeTotal"), store.moneyText(income.totalGross))
                Text(store.lifeIncomeMethodText())
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func weeksLabel(_ count: Int) -> String {
        store.t("lifeWeeksUnit", values: ["count": store.formatCount(count)])
    }

    // MARK: - Grid

    /// One row per year, 52-odd weeks across. The old twelve-column layout took
    /// four rows to draw a single year, so reaching retirement was dozens of
    /// screens of scrolling and no year read as a unit.
    private func gridCard(_ model: LifeViewModel) -> some View {
        let years = LifeYearRow.rows(from: model.cells)
        return OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                legend
                if differentiateWithoutColor {
                    breakdown(model)
                }
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(years.enumerated()), id: \.element.year) { index, row in
                        yearRow(row, position: index + 1, total: years.count)
                    }
                }
            }
            .padding(16)
        }
    }

    private func yearRow(_ row: LifeYearRow, position: Int, total: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Kept even when the year is hidden, so the rows stay on one grid
            // rather than shifting left by the width of a label.
            Text(store.hidesLifeAges ? "" : store.formatYear(row.year))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(OWCDesign.tertiary)
                .frame(width: 30, alignment: .trailing)
                .accessibilityHidden(true)

            HStack(spacing: 1.5) {
                ForEach(row.cells) { cell in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color(for: cell.kind))
                        .frame(height: 9)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if cell.kind == .workOverride || cell.outsidePeriodTimeZone {
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .stroke(OWCDesign.primary, lineWidth: 0.6)
                            }
                        }
                }
            }
        }
        // One element per year. Fifty-two 9pt rectangles are not fifty-two
        // things a screen reader should have to walk through, and none of them
        // is tappable.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            store.hidesLifeAges
                ? store.t("lifeRowPosition", values: ["count": store.formatCount(position), "total": store.formatCount(total)])
                : store.formatYear(row.year)
        )
        .accessibilityValue(weeksLabel(row.workingWeeks))
    }

    private var legend: some View {
        // Adaptive columns, because six labels in German do not fit on one line
        // and fixed columns truncated the long ones while the short ones sat in
        // empty space.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(LifeWeekKind.legendOrder, id: \.self) { kind in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: kind))
                        .frame(width: 10, height: 10)
                        .overlay {
                            if kind == .workOverride {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(OWCDesign.primary, lineWidth: 0.6)
                            }
                        }
                    Text(store.t(kind.legendKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Colour is the only thing separating the six kinds in the grid. When the
    /// system asks for a second channel, the same information arrives as counts.
    private func breakdown(_ model: LifeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(LifeWeekKind.legendOrder, id: \.self) { kind in
                let count = model.cells.count(where: { $0.kind == kind })
                if count > 0 {
                    HStack {
                        Text(store.t(kind.legendKey))
                            .foregroundStyle(OWCDesign.secondary)
                        Spacer(minLength: 8)
                        Text(weeksLabel(count))
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func footnotes(_ model: LifeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.t("lifeEstimatedPast"))
            Text(store.t("lifeProjectedFuture"))
            Text(store.t("lifeYouChanged"))
            if model.cells.contains(where: \.outsidePeriodTimeZone) {
                Text(store.t("lifeOutsideZone"))
            }
        }
        .font(.footnote)
        .foregroundStyle(OWCDesign.secondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
    }

    private var emptyCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("lifeEmptyTitle"))
                    .font(.body.weight(.medium))
                Text(store.t("lifeEmptyBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.t("lifeSetUp"), action: openEditor)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func openEditor() {
        if store.plus.isAuthorized {
            editing = true
        } else {
            store.paywallSheet = .life
        }
    }

    private func color(for kind: LifeWeekKind) -> Color {
        switch kind {
        case .childhood: OWCDesign.control
        case .study: OWCDesign.secondary.opacity(0.35)
        case .workEstimated: OWCDesign.accent.opacity(0.7)
        case .workProjected: OWCDesign.accent.opacity(0.28)
        case .workOverride: OWCDesign.orangeDeep
        case .retirement, .none: OWCDesign.control.opacity(0.4)
        }
    }
}

/// One year of the life grid.
struct LifeYearRow: Identifiable {
    var id: Int { year }
    let year: Int
    let cells: [LifeWeekCell]

    var workingWeeks: Int {
        cells.count(where: \.kind.isWork)
    }

    static func rows(from cells: [LifeWeekCell]) -> [LifeYearRow] {
        Dictionary(grouping: cells, by: \.year)
            .sorted { $0.key < $1.key }
            .map { LifeYearRow(year: $0.key, cells: $0.value.sorted { $0.start < $1.start }) }
    }
}

extension LifeWeekKind {
    /// Legend order, and the only place the six kinds are named for the user.
    static var legendOrder: [LifeWeekKind] {
        [.childhood, .study, .workEstimated, .workProjected, .workOverride, .retirement]
    }

    var legendKey: String {
        switch self {
        case .childhood: "lifeLegendChildhood"
        case .study: "lifeLegendStudy"
        case .workEstimated: "lifeLegendEstimated"
        case .workProjected: "lifeLegendProjected"
        case .workOverride: "lifeLegendOverride"
        case .retirement, .none: "lifeLegendRetirement"
        }
    }
}

/// Editing the profile, on its own surface.
struct LifeProfileEditView: View {
    let store: OffWorkStore

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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OWCGroupCard {
                        numberRow(store.t("lifeBirthYear"), text: $bornYear, placeholder: "1990", maxDigits: 4)
                        numberRow(
                            store.t("lifeSchoolStarted"),
                            text: $schoolYear,
                            placeholder: suggestedSchoolYear,
                            maxDigits: 4
                        )
                        numberRow(store.t("lifeRetirementAge"), text: $retirementAge, placeholder: "60", maxDigits: 3)
                        numberRow(
                            store.t("lifeSleepHours"),
                            text: $sleepHours,
                            placeholder: "8",
                            maxDigits: 4,
                            decimal: true,
                            isLast: true
                        )
                    }

                    workHistoryEditor
                        .environment(\.calendar, store.recordsCalendar)
                        .environment(\.timeZone, store.recordsCalendar.timeZone)

                    futureIncomeEditor

                    Text(store.t("lifeProfileFooter"))
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
            .navigationTitle(store.t("lifeProfileTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancelAction")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("saveAction"), action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sensoryFeedback(.success, trigger: savedFeedback)
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var futureIncomeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(store.t("lifeFutureIncomeMode"), selection: $futureIncomeMode) {
                Text(store.t("lifeFutureIncomeKeep")).tag(FutureIncomeMode.keepCurrent)
                Text(store.t("lifeFutureIncomeDecline")).tag(FutureIncomeMode.decline)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(store.t("lifeFutureIncomeMode"))

            if futureIncomeMode == .decline {
                OWCGroupCard {
                    numberRow(
                        store.t("lifeIncomeDeclineStartAge"),
                        text: $declineStartAge,
                        placeholder: "45",
                        maxDigits: 3
                    )
                    numberRow(
                        store.t("lifeIncomeRetirementRatio"),
                        text: $retirementIncomePercent,
                        placeholder: "60",
                        maxDigits: 3,
                        isLast: true
                    )
                }
                if let decline = incomeDecline {
                    Text(store.t("lifeIncomeDeclinePreview", values: [
                        "age": store.formatCount(decline.startsAtAge),
                        "percent": store.formatPercent(decline.retirementRatio * 100, fractionDigits: 0),
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
            Picker(store.t("lifeWorkHistoryMode"), selection: $workHistoryMode) {
                Text(store.t("lifeWorkHistoryRough")).tag(LifeWorkHistoryMode.rough)
                Text(store.t("lifeWorkHistoryDetailed")).tag(LifeWorkHistoryMode.detailed)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(store.t("lifeWorkHistoryMode"))

            if workHistoryMode == .rough {
                OWCGroupCard {
                    numberRow(
                        store.t("lifeWorkStarted"),
                        text: $workYear,
                        placeholder: suggestedWorkYear,
                        maxDigits: 4
                    )
                    salaryRow(
                        title: store.t("lifeCurrentSalary"),
                        amount: $roughSalaryAmount,
                        cadence: $roughSalaryCadence,
                        isLast: true
                    )
                }
                Text(store.t("lifeRoughIncomeHelp"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            } else {
                Text(store.t("lifeDetailedIncomeHelp"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
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
                        startDate: store.recordsCalendar.date(
                            byAdding: .year,
                            value: -1,
                            to: previousStart
                        ) ?? previousStart
                    ))
                } label: {
                    Label(store.t("lifeAddEmployment"), systemImage: "plus")
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
                if store.hideEarnings {
                    Text("••••")
                    OWCEarningsVisibilityButton(store: store)
                } else {
                    OWCNumberField(
                        placeholder: "0",
                        text: amount,
                        decimal: true,
                        maxDigits: 12,
                        width: 104,
                        onCommit: {}
                    )
                }
                Picker("", selection: cadence) {
                    Text(store.t("lifeSalaryMonthly")).tag(LifeSalaryCadence.monthly)
                    Text(store.t("lifeSalaryYearly")).tag(LifeSalaryCadence.yearly)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(store.t("lifeSalaryCadence"))
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
                Text(store.t("lifeEmploymentCurrent"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 20)
            }
            OWCGroupCard {
                VStack(spacing: 0) {
                    OWCRow(title: store.t("lifeEmploymentStart")) {
                        DatePicker(
                            "",
                            selection: draft.startDate,
                            in: employmentStartRange(for: draft.wrappedValue.id),
                            displayedComponents: .date
                        )
                            .labelsHidden()
                            .accessibilityLabel(store.t("lifeEmploymentStart"))
                    }
                    OWCRow(title: store.t("lifeEmploymentEnd")) {
                        if isCurrent {
                            Text(store.t("lifeStagePresent"))
                                .foregroundStyle(OWCDesign.secondary)
                        } else if let endDate {
                            Text(endDate, format: Date.FormatStyle(
                                date: .abbreviated, time: .omitted,
                                locale: store.locale, calendar: store.recordsCalendar,
                                timeZone: store.recordsCalendar.timeZone
                            ))
                            .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    salaryRow(
                        title: store.t("lifeEmploymentSalary"),
                        amount: isCurrent ? $roughSalaryAmount : draft.salaryAmount,
                        cadence: isCurrent ? $roughSalaryCadence : draft.salaryCadence,
                        isLast: isCurrent
                    )
                    if !isCurrent {
                        Button(role: .destructive) {
                            employmentDrafts.removeAll { $0.id == draft.wrappedValue.id }
                        } label: {
                            OWCRow(icon: "trash", title: store.t("lifeRemoveEmployment"), isLast: true) {
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
        guard let index = employmentDrafts.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return employmentDrafts[index - 1].startDate
    }

    private func employmentStartRange(for id: UUID) -> ClosedRange<Date> {
        guard let index = employmentDrafts.firstIndex(where: { $0.id == id }) else {
            return .distantPast ... store.recordsCalendar.startOfDay(for: .now)
        }
        let upper = index == 0
            ? store.recordsCalendar.startOfDay(for: .now)
            : store.recordsCalendar.date(
                byAdding: .day,
                value: -1,
                to: employmentDrafts[index - 1].startDate
            ) ?? employmentDrafts[index - 1].startDate
        guard index + 1 < employmentDrafts.count,
              let lower = store.recordsCalendar.date(
                byAdding: .day,
                value: 1,
                to: employmentDrafts[index + 1].startDate
              ),
              lower <= upper
        else { return .distantPast ... upper }
        return lower ... upper
    }

    private func load() {
        var profile = store.records.state.lifeProfile
        profile?.migrateLegacyFields(calendar: store.recordsCalendar)
        workHistoryMode = profile?.workHistoryMode ?? .rough
        if let year = profile?.bornOn?.year ?? profile?.birthYear { bornYear = Self.plain(year) }
        if let year = profile?.schoolStartedOn?.year { schoolYear = Self.plain(year) }
        if let year = profile?.workStartedPartial?.year
            ?? profile?.workStartedOn.map({ store.recordsCalendar.component(.year, from: $0) }) {
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
        } else if store.salaryEnabled,
                  let equivalent = try? CountdownRules.shared.salaryMonthlyEquivalent(
                    input: store.rulesInput(at: .now)
                  ),
                  let amount = equivalent.amount,
                  amount > 0 {
            roughSalaryAmount = Self.plain(amount)
            roughSalaryCadence = .monthly
        }
        employmentDrafts = (profile?.employmentPeriods ?? []).compactMap {
            EmploymentDraft($0, calendar: store.recordsCalendar)
        }
        if !employmentDrafts.contains(where: { $0.wasCurrent }) {
            employmentDrafts.append(EmploymentDraft(
                startDate: LifeEmploymentTimeline.inferredCurrentStart(
                    profile: profile,
                    calendar: store.recordsCalendar
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
        Task {
            guard await store.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else { return }
            let bornOn = Int(bornYear).map { PartialCivilDate.yearOnly($0) }
            let retirementOn = {
                guard let birthYear = bornOn?.year,
                      let age = Int(retirementAge) else { return nil as PartialCivilDate? }
                return .yearOnly(birthYear + age)
            }()
            let detailedPeriods = linkedEmploymentPeriods
            guard workHistoryMode == .rough || detailedPeriods != nil else { return }
            var profile = store.records.state.lifeProfile ?? LifeProfile(
                editedAt: .now,
                editCount: 0,
                editTieBreaker: UUID()
            )
            profile.bornOn = bornOn
            profile.schoolStartedOn = (Int(schoolYear) ?? bornOn.map { $0.year + 6 })
                .map { .yearOnly($0) }
            profile.workStartedPartial = workHistoryMode == .rough
                ? (Int(workYear) ?? bornOn.map { $0.year + 22 }).map { .yearOnly($0) }
                : earliestStart(in: detailedPeriods ?? [])
            profile.retirementOn = retirementOn
            profile.birthYear = bornOn?.year
            profile.workStartedOn = profile.workStartedPartial?.calculationAnchor(in: store.recordsCalendar)
            profile.retirementAge = Int(retirementAge)
            profile.averageSleepHours = Double(sleepHours)
            profile.averageSleepMinutes = Double(sleepHours).map { Int(($0 * 60).rounded()) }
            if profile.averageSleepMinutes != nil {
                profile.sleepSource = .manual
                profile.sleepSourceUpdatedAt = .now
            }
            profile.workHistoryMode = workHistoryMode
            profile.roughCurrentSalary = salary(amount: roughSalaryAmount, cadence: roughSalaryCadence)
            if workHistoryMode == .detailed, let detailedPeriods {
                profile.employmentPeriods = detailedPeriods
            }
            profile.futureIncomeDecline = futureIncomeMode == .decline ? incomeDecline : nil
            store.records.updateLifeProfile(profile)
            savedFeedback += 1
            dismiss()
        }
    }

    private var suggestedSchoolYear: String {
        Int(bornYear).map { Self.plain($0 + 6) } ?? store.t("lifeSuggestedYear")
    }

    private var suggestedWorkYear: String {
        Int(bornYear).map { Self.plain($0 + 22) } ?? store.t("lifeSuggestedYear")
    }

    private var canSave: Bool {
        guard Double(sleepHours) != nil,
              validOptionalYear(bornYear),
              validOptionalYear(schoolYear),
              validOptionalYear(workYear),
              Int(retirementAge).map({ (1...120).contains($0) }) == true
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
        value.isEmpty || Int(value).map { (1_000...9_999).contains($0) } == true
    }

    private func salary(amount: String, cadence: LifeSalaryCadence) -> LifeSalary? {
        guard let value = Double(amount), value.isFinite, value > 0 else { return nil }
        return LifeSalary(amount: value, cadence: cadence)
    }

    private var incomeDecline: LifeIncomeDecline? {
        guard let age = Int(declineStartAge),
              let percent = Double(retirementIncomePercent)
        else { return nil }
        let value = LifeIncomeDecline(startsAtAge: age, retirementRatio: percent / 100)
        return value.isValid ? value : nil
    }

    private func earliestStart(in periods: [LifeEmploymentPeriod]) -> PartialCivilDate? {
        periods.min {
            guard let left = $0.startsOn.calculationAnchor(in: store.recordsCalendar) else { return false }
            guard let right = $1.startsOn.calculationAnchor(in: store.recordsCalendar) else { return true }
            return left < right
        }?.startsOn
    }

    private var linkedEmploymentPeriods: [LifeEmploymentPeriod]? {
        guard let currentSalary = salary(amount: roughSalaryAmount, cadence: roughSalaryCadence),
              !employmentDrafts.isEmpty
        else { return nil }
        let periods = employmentDrafts.enumerated().compactMap { index, draft in
            draft.period(
                calendar: store.recordsCalendar,
                salary: index == 0 ? currentSalary : nil
            )
        }
        guard periods.count == employmentDrafts.count else { return nil }
        return LifeEmploymentTimeline.linkedPeriods(periods, calendar: store.recordsCalendar)
    }

    /// `OWCNumberField` holds ASCII digits with "." as the separator, whatever
    /// the keyboard produced — that is what makes `Int(_:)` and `Double(_:)`
    /// safe above. Loading through the user's locale broke the contract from the
    /// other side: German rendered 7.5 as "7,5", and saving parsed it as nil.
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
                guard let amount = Double(salaryAmount), amount.isFinite, amount > 0 else { return nil }
                resolvedSalary = LifeSalary(amount: amount, cadence: salaryCadence)
            }
            return LifeEmploymentPeriod(
                id: id,
                startsOn: startsOn,
                endsOn: nil,
                salary: resolvedSalary
            )
        }
    }
}

extension OffWorkStore {
    func lifeIncomeMethodText() -> String {
        guard let decline = records.state.lifeProfile?.futureIncomeDecline else {
            return t("lifeIncomeMethod")
        }
        return t("lifeIncomeMethodDecline", values: [
            "age": formatCount(decline.startsAtAge),
            "percent": formatPercent(decline.retirementRatio * 100, fractionDigits: 0),
        ])
    }
}
