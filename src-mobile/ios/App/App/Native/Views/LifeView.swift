import SwiftUI

struct LifeView: View {
    let store: OffWorkStore

    @State private var model: LifeViewModel?
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

    @State private var bornYear = ""
    @State private var schoolYear = ""
    @State private var workYear = ""
    @State private var retirementAge = ""
    @State private var sleepHours = ""
    @State private var savedFeedback = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OWCGroupCard {
                        numberRow(store.t("lifeBirthYear"), text: $bornYear, placeholder: "1990", maxDigits: 4)
                        numberRow(store.t("lifeSchoolStarted"), text: $schoolYear, placeholder: "1996", maxDigits: 4)
                        numberRow(store.t("lifeWorkStarted"), text: $workYear, placeholder: "2012", maxDigits: 4)
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
                        .disabled(Double(sleepHours) == nil)
                }
            }
            .sensoryFeedback(.success, trigger: savedFeedback)
            .onAppear(perform: load)
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

    private func load() {
        var profile = store.records.state.lifeProfile
        profile?.migrateLegacyFields(calendar: store.recordsCalendar)
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
        }
        if let sleep = profile?.averageSleepHours { sleepHours = Self.plain(sleep) }
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
            store.saveLifeProfileV2(
                bornOn: bornOn,
                schoolStartedOn: Int(schoolYear).map { .yearOnly($0) },
                workStartedOn: Int(workYear).map { .yearOnly($0) },
                retirementOn: retirementOn,
                sleepHours: Double(sleepHours)
            )
            savedFeedback += 1
            dismiss()
        }
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
}
