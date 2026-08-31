import SwiftUI

struct LifeView: View {
    let store: OffWorkStore
    @State private var birthYear = ""
    @State private var workStartedYear = ""
    @State private var retirementAge = "60"
    @State private var sleepHours = "8"
    @State private var hidesAges = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(store.t("lifeBirthYear"), text: $birthYear)
                        labeledField(store.t("lifeWorkStarted"), text: $workStartedYear)
                        labeledField(store.t("lifeRetirementAge"), text: $retirementAge)
                        labeledField(store.t("lifeSleepHours"), text: $sleepHours)
                        Toggle(store.t("lifeHideAges"), isOn: $hidesAges)
                        Button(store.t("lifeSave"), action: save)
                            .buttonStyle(OWCPrimaryButtonStyle())
                    }
                    .padding(16)
                }

                if let model = store.lifeViewModel() {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 10) {
                            legend
                            weekGrid(model)
                            Text(store.t("lifeEstimatedPast"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                            Text(store.t("lifeProjectedFuture"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                            if model.cells.contains(where: \.outsidePeriodTimeZone) {
                                Text(store.t("lifeOutsideZone"))
                                    .font(.footnote)
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("lifeTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.t("lifeYouChanged"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
    }

    private func weekGrid(_ model: LifeViewModel) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 12)
        let years = Dictionary(grouping: model.cells, by: \.year)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(years.keys.sorted(), id: \.self) { year in
                if !hidesAges {
                    Text(String(year))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                }
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(years[year] ?? []) { cell in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(color(for: cell.kind))
                            .frame(height: 8)
                            .overlay {
                                if cell.outsidePeriodTimeZone {
                                    Circle().stroke(OWCDesign.primary, lineWidth: 0.6)
                                }
                            }
                    }
                }
            }
        }
    }

    private func color(for kind: LifeWeekKind) -> Color {
        switch kind {
        case .childhood: OWCDesign.control
        case .study: OWCDesign.secondary.opacity(0.35)
        case .workEstimated: OWCDesign.accent.opacity(0.7)
        case .workProjected: OWCDesign.accent.opacity(0.28)
        case .workOverride: OWCDesign.orangeDeep
        case .retirement, .none: OWCDesign.page
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func load() {
        let profile = store.records.state.lifeProfile
        if let year = profile?.birthYear { birthYear = "\(year)" }
        if let started = profile?.workStartedOn {
            workStartedYear = "\(store.recordsCalendar.component(.year, from: started))"
        }
        if let age = profile?.retirementAge { retirementAge = "\(age)" }
        if let sleep = profile?.averageSleepHours {
            sleepHours = sleep.formatted(.number.precision(.fractionLength(0...1)))
        }
        hidesAges = profile?.hidesExactAges ?? false
    }

    private func save() {
        store.saveLifeProfile(
            birthYear: Int(birthYear),
            workStartedYear: Int(workStartedYear),
            retirementAge: Int(retirementAge),
            sleepHours: Double(sleepHours),
            hidesExactAges: hidesAges
        )
    }
}
