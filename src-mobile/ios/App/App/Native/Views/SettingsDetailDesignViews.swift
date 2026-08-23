import SwiftUI

struct ScheduleSettingsView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
                OWCGroupCard {
                    modeRow(.classic, title: store.t("scheduleClassic"), subtitle: store.t("scheduleClassicDescription"))
                    modeRow(.alternating, title: store.t("scheduleAlternating"), subtitle: store.t("scheduleAlternatingDescription"))
                    modeRow(.rotation, title: store.t("scheduleRotation"), subtitle: store.t("scheduleRotationDescription"))
                    modeRow(.off, title: store.t("scheduleOff"), subtitle: store.t("scheduleOffDescription"), isLast: true)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                scheduleDetails
                    .padding(.top, 22)

                Text(store.scheduleMode == .off ? store.t("scheduleOffSummaryNote") : store.t("scheduleSharedRulesNote"))
                    .font(.system(size: 13))
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 9)
            }
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("workSchedule"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("workSchedule"))
        .sensoryFeedback(.selection, trigger: store.scheduleMode)
    }

    @ViewBuilder
    private var scheduleDetails: some View {
        switch store.scheduleMode {
        case .classic:
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("workdaysLabel"))
                weekdayGrid
            }
            .padding(.horizontal, OWCDesign.pageInset)
        case .alternating:
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("alternatingCurrentWeek"))
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(store.t("alternatingCurrentWeek"))
                            .font(.system(size: 15, weight: .semibold))
                        Picker(store.t("alternatingCurrentWeek"), selection: $store.alternatingWeekType) {
                            Text(store.t("singleRestWeek")).tag(AlternatingWeekType.single)
                            Text(store.t("doubleRestWeek")).tag(AlternatingWeekType.double)
                        }
                        .pickerStyle(.segmented)
                        Text(store.t("alternatingCurrentWeekDescription"))
                            .font(.system(size: 13))
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .owcPlainDivider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(store.t("singleWeekWorkday"))
                            .font(.system(size: 15, weight: .semibold))
                        Picker(store.t("singleWeekWorkday"), selection: $store.alternatingWeekendWorkday) {
                            Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[5]])).tag(6)
                            Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[6]])).tag(0)
                        }
                        .pickerStyle(.segmented)
                        Text(store.t("singleWeekWorkdayDescription"))
                            .font(.system(size: 13))
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .onChange(of: store.alternatingWeekType) { store.anchorAlternatingWeekToToday() }
        case .rotation:
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("rotationPattern"))
                OWCGroupCard {
                    // Stepper puts its -/+ at the trailing edge of its own
                    // bounds, outside OWCRow's inset, so it needs the inset back
                    // or it sits flush against the card edge.
                    Stepper(value: $store.rotationWorkDays, in: 1...30) {
                        OWCRow(title: store.t("rotationWorkDays")) {
                            Text("\(store.rotationWorkDays)").monospacedDigit().foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()
                    Stepper(value: $store.rotationRestDays, in: 1...30) {
                        OWCRow(title: store.t("rotationRestDays")) {
                            Text("\(store.rotationRestDays)").monospacedDigit().foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()

                    Menu {
                        ForEach(1...store.rotationCycleLength, id: \.self) { day in
                            Button {
                                store.setRotationCycleDay(day)
                            } label: {
                                Label(
                                    store.t(
                                        day <= store.rotationWorkDays ? "rotationWorkdayOption" : "rotationRestdayOption",
                                        values: ["day": "\(day)"]
                                    ),
                                    systemImage: day <= store.rotationWorkDays ? "briefcase" : "bed.double"
                                )
                            }
                        }
                    } label: {
                        OWCRow(
                            icon: "repeat",
                            title: store.t("rotationStartDay", values: ["day": "\(store.rotationCycleDay)"]),
                            isLast: true
                        ) {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
        case .off:
            OWCGroupCard {
                OWCRow(icon: "calendar.badge.minus", title: store.t("scheduleOffManualStart"), isLast: true) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OWCDesign.accent)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
        }
    }

    private var weekdayGrid: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels())), id: \.0) { day, label in
                Button { store.toggleWorkday(day) } label: {
                    Text(label)
                        .font(.system(size: 13, weight: store.workdays.contains(day) ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(store.workdays.contains(day) ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(store.workdays.contains(day) ? OWCDesign.accent : OWCDesign.control)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    private func modeRow(_ mode: WorkScheduleMode, title: String, subtitle: String, isLast: Bool = false) -> some View {
        Button {
            store.scheduleMode = mode
            if mode == .alternating { store.anchorAlternatingWeekToToday() }
            if mode == .rotation { store.anchorRotationToToday() }
        } label: {
            OWCRow(title: title, subtitle: subtitle, isLast: isLast) {
                Image(systemName: store.scheduleMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(store.scheduleMode == mode ? OWCDesign.accent : OWCDesign.tertiary)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}

struct SalaryDesignView: View {
    @ObservedObject var store: OffWorkStore
    private enum Field { case amount, bonus }
    @FocusState private var focusedField: Field?
    @State private var amountText = ""

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
            OWCGroupCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.t("enableSalary")).font(.system(size: 17))
                        Text(store.t("enableSalaryDescription")).font(.system(size: 13)).foregroundStyle(OWCDesign.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $store.salaryEnabled).labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)

            if store.salaryEnabled {
            Picker(store.t("salaryType"), selection: $store.salaryType) {
                Text(store.t("monthly")).tag(SalaryType.monthly)
                Text(store.t("daily")).tag(SalaryType.daily)
            }
            .pickerStyle(.segmented)
            .frame(height: 44)
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 18)

            OWCGroupCard {
                HStack {
                    Text(store.t("amount"))
                        .font(.system(size: 17))
                    Spacer()
                    OWCNumberField(
                        placeholder: "0",
                        text: $amountText,
                        decimal: true,
                        maxDigits: 9,
                        emphasized: true,
                        onCommit: commitAmount
                    )
                    .focused($focusedField, equals: .amount)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcPlainDivider()

                if store.salaryType == .monthly {
                    Menu {
                        ForEach(15...31, id: \.self) { value in
                            Button("\(value)") { store.monthlyWorkingDays = Double(value) }
                        }
                    } label: {
                        HStack {
                            Text(store.t("monthlyWorkingDays"))
                                .font(.system(size: 17))
                                .foregroundStyle(OWCDesign.primary)
                            Spacer()
                            Text(Int(store.monthlyWorkingDays).formatted())
                                .font(.system(size: 17).monospacedDigit())
                                .foregroundStyle(OWCDesign.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()
                }

                HStack {
                    Text(store.t("annualBonus"))
                        .font(.system(size: 17))
                    Spacer()
                    Toggle("", isOn: $store.annualBonusEnabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcPlainDivider()

                if store.annualBonusEnabled {
                    HStack {
                        Text(store.t("annualBonusMonths")).font(.system(size: 17))
                        Spacer()
                        TextField("0", value: $store.annualBonusMonths, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .bonus)
                            .frame(maxWidth: 120)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .owcPlainDivider()
                }

                HStack {
                    Text(store.t("hideSalary"))
                        .font(.system(size: 17))
                    Spacer()
                    Toggle("", isOn: $store.hideEarnings)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)

            detailFooter(store.t("salaryPrivacyNote"))

            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("moneyEarned"))
                    .font(.system(size: 13))
                    .foregroundStyle(OWCDesign.secondary)
                Text(store.hideEarnings ? "••••" : store.formatMoney(earnedNow))
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .tracking(-0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("derivedFromThis"))
                OWCGroupCard {
                    OWCRow(title: store.t("perWorkday")) {
                        Text(store.hideEarnings ? "••••" : store.formatMoney(dailySalary))
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(title: store.t("perEffectiveHour"), isLast: true) {
                        Text(store.hideEarnings ? "••••" : store.formatMoney(hourlySalary))
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 20)

            detailFooter(effectiveTimeNote)
            }
                Spacer(minLength: 8)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OWCDesign.page)
        .navigationTitle(store.t("salarySettings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("salarySettings"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(store.t("done")) {
                    store.annualBonusMonths = max(0, store.annualBonusMonths)
                    commitAmount()
                    focusedField = nil
                }
            }
        }
        .onAppear { amountText = store.salaryAmount }
        .onDisappear { commitAmount() }
        .sensoryFeedback(.selection, trigger: store.salaryType)
        .sensoryFeedback(.selection, trigger: store.salaryEnabled)
        .sensoryFeedback(.selection, trigger: store.annualBonusEnabled)
        .sensoryFeedback(.selection, trigger: store.hideEarnings)
    }

    private var snapshot: NativeShiftSnapshot? { store.snapshot() }
    private var dailySalary: Double? { snapshot?.dailySalary }
    private var earnedNow: Double? {
        guard let snapshot, let dailySalary = snapshot.dailySalary else { return nil }
        return dailySalary * snapshot.payRatio
    }
    private var hourlySalary: Double? {
        guard let snapshot, let dailySalary = snapshot.dailySalary, snapshot.plannedDurationMs > 0 else { return nil }
        return dailySalary / (snapshot.plannedDurationMs / 3_600_000)
    }
    private func commitAmount() {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        if store.salaryAmount != trimmed { store.salaryAmount = trimmed }
    }

    private var effectiveTimeNote: String {
        guard let snapshot else { return store.t("lunchPauseNoteNoSalary") }
        return "\(store.formatDuration(snapshot.plannedDurationMs, includeSeconds: false)) · \(store.t("lunchPauseNoteNoSalary"))"
    }

    private func detailFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 8)
    }
}

struct NotificationDesignView: View {
    @ObservedObject var store: OffWorkStore
    @StateObject private var notifications = NotificationService()

    var body: some View {
        Group {
            if notifications.status == .denied {
                deniedContent
            } else {
                settingsContent
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("offWorkReminder"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("offWorkReminder"))
        .task { await notifications.refresh() }
        .sensoryFeedback(.selection, trigger: store.notificationMode)
        .sensoryFeedback(.selection, trigger: store.liveActivityEnabled)
        .sensoryFeedback(.selection, trigger: store.liveActivityLeadMinutes)
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            OWCGroupCard {
                modeRow(.off, title: store.t("notificationModeOff"))
                modeRow(.simple, title: store.t("notificationModeSimple"))
                modeRow(.milestones, title: store.t("notificationModeMilestones"), isLast: true)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("liveActivity"))
                OWCGroupCard {
                    HStack {
                        Text(store.t("lockScreenLiveActivity"))
                            .font(.system(size: 17))
                        Spacer()
                        Toggle("", isOn: $store.liveActivityEnabled)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .owcPlainDivider()

                    Picker(store.t("liveActivityStartTime"), selection: $store.liveActivityLeadMinutes) {
                        ForEach(OffWorkStore.allowedLiveActivityLeadMinutes, id: \.self) { minutes in
                            Text(store.t("liveActivityLead", values: ["count": "\(minutes)"]))
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)

            detailFooter(store.t("liveActivityScheduleNote"))

            detailFooter(store.t("notificationPrivacyNote"))
            Spacer(minLength: 8)
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(OWCDesign.orangeDeep)
                        .frame(width: 38, height: 38)
                        .background(OWCDesign.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("notificationDeniedTitle"))
                            .font(.system(size: 17, weight: .semibold))
                        Text(store.t("notificationDeniedBody"))
                            .font(.system(size: 15))
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }

                Button(store.t("notificationOpenSettings")) {
                    notifications.openSystemSettings()
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                .frame(height: 44)
            }
            .padding(16)
            .background(OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("notificationCapability"))
                OWCGroupCard {
                    OWCRow(title: store.t("notificationLocal")) {
                        Text(store.t("notificationDeniedStatus"))
                            .font(.system(size: 17))
                            .foregroundStyle(OWCDesign.orangeDeep)
                    }
                    OWCRow(title: store.t("liveActivity")) {
                        Text(store.t("notificationAllowedStatus"))
                            .font(.system(size: 17))
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(title: store.t("notificationScheduledForShift"), isLast: true) {
                        Text("0 / 0")
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 24)

            detailFooter(store.t("notificationCapabilityNote"))

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("notificationStillWorks"))
                OWCGroupCard {
                    OWCRow(icon: "rectangle.inset.filled", title: store.t("lockScreenLiveActivity")) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(OWCDesign.orange)
                    }
                    OWCRow(icon: "square.grid.2x2", title: store.t("notificationHomeWidget"), isLast: true) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(OWCDesign.orange)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)

            Spacer(minLength: 8)
        }
    }

    private func modeRow(_ mode: OffWorkNotificationMode, title: String, isLast: Bool = false) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { store.notificationMode = mode }
            if mode != .off, notifications.status == .notDetermined {
                Task { _ = await notifications.request() }
            }
        } label: {
            OWCRow(title: title, isLast: isLast) {
                if store.notificationMode == mode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OWCDesign.orange)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private func detailFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 8)
    }
}

private extension View {
    func owcPlainDivider() -> some View {
        overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(OWCDesign.separator)
                .frame(height: 0.5)
                .padding(.leading, 16)
        }
    }
}

struct LunchSettingsView: View {
    @ObservedObject var store: OffWorkStore
    @FocusState private var durationFocused: Bool
    @State private var durationText = ""

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack {
                        Text(store.t("lunchBreak")).font(.system(size: 17))
                        Spacer()
                        Toggle("", isOn: $store.lunchEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .owcDivider()

                    if store.lunchEnabled {
                        DatePicker(
                            store.t("lunchStartTime"),
                            selection: lunchBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .font(.system(size: 17))
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .owcDivider()

                        HStack {
                            Text(store.t("lunchDuration")).font(.system(size: 17))
                            Spacer()
                            OWCNumberField(
                                placeholder: "60",
                                text: $durationText,
                                width: 72,
                                onCommit: clampDuration
                            )
                            .focused($durationFocused)
                            Text(store.t("minutesUnit"))
                                .font(.system(size: 16))
                                .foregroundStyle(OWCDesign.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                OWCSectionHeader(title: store.t("remindersSection"))
                    .padding(.top, 20)
                OWCGroupCard {
                    HStack {
                        Text(store.t("lunchStartReminder")).font(.system(size: 17))
                        Spacer()
                        Toggle("", isOn: $store.lunchStartReminderEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .owcDivider()

                    HStack {
                        Text(store.t("lunchEndReminder")).font(.system(size: 17))
                        Spacer()
                        Toggle("", isOn: $store.lunchEndReminderEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                }
                .padding(.horizontal, OWCDesign.pageInset)

                settingsDetailFooter(
                    store.salaryEnabled
                        ? store.t("lunchPauseNote")
                        : store.t("lunchPauseNoteNoSalary")
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OWCDesign.page)
        .navigationTitle(store.t("lunchBreak"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("lunchBreak"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(store.t("done")) { durationFocused = false; clampDuration() }
            }
        }
        .onAppear { durationText = "\(store.lunchDurationMinutes)" }
        .onDisappear { clampDuration() }
        .sensoryFeedback(.selection, trigger: store.lunchEnabled)
        .sensoryFeedback(.selection, trigger: store.lunchStartReminderEnabled)
        .sensoryFeedback(.selection, trigger: store.lunchEndReminderEnabled)
    }

    private var lunchBinding: Binding<Date> {
        Binding(
            get: { store.dateForMinutes(store.lunchStartMinutes) },
            set: { store.lunchStartMinutes = store.minutes(from: $0) }
        )
    }

    private func clampDuration() {
        let typed = Int(durationText) ?? store.lunchDurationMinutes
        let clamped = min(180, max(10, typed))
        if store.lunchDurationMinutes != clamped {
            store.lunchDurationMinutes = clamped
        }
        durationText = "\(clamped)"
    }
}

struct HealthReminderSettingsView: View {
    @ObservedObject var store: OffWorkStore
    @FocusState private var intervalFocused: Bool
    @State private var intervalText = ""

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack {
                        Text(store.t("microBreakReminder")).font(.system(size: 17))
                        Spacer()
                        Toggle("", isOn: $store.microBreakEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)

                    if store.microBreakEnabled {
                        HStack {
                            Text(store.t("microBreakInterval")).font(.system(size: 17))
                            Spacer()
                            OWCNumberField(
                                placeholder: "60",
                                text: $intervalText,
                                width: 72,
                                onCommit: clampInterval
                            )
                            .focused($intervalFocused)
                            Text(store.t("minutesUnit"))
                                .font(.system(size: 16))
                                .foregroundStyle(OWCDesign.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .overlay(alignment: .topTrailing) {
                            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
                        }
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                settingsDetailFooter(store.t("microBreakEffectiveTimeNote"))
            }
        }
        .scrollDismissesKeyboard(.never)
        .background(OWCDesign.page)
        .navigationTitle(store.t("microBreakReminder"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("microBreakReminder"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(store.t("done")) { intervalFocused = false; clampInterval() }
            }
        }
        .onAppear { intervalText = "\(store.microBreakIntervalMinutes)" }
        .onDisappear { clampInterval() }
        .sensoryFeedback(.selection, trigger: store.microBreakEnabled)
    }

    private func clampInterval() {
        let typed = Int(intervalText) ?? store.microBreakIntervalMinutes
        let clamped = min(120, max(20, typed))
        if store.microBreakIntervalMinutes != clamped {
            store.microBreakIntervalMinutes = clamped
        }
        intervalText = "\(clamped)"
    }
}

struct ThemeSettingsView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                themeRow(.auto, title: store.t("auto"), icon: nil, textIcon: "A")
                themeRow(.light, title: store.t("light"), icon: "sun.max")
                themeRow(.dark, title: store.t("dark"), icon: "moon", isLast: true)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("theme"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("theme"))
        .sensoryFeedback(.selection, trigger: store.theme)
    }

    private func themeRow(
        _ theme: AppTheme,
        title: String,
        icon: String?,
        textIcon: String? = nil,
        isLast: Bool = false
    ) -> some View {
        Button { store.theme = theme } label: {
            OWCRow(icon: icon, textIcon: textIcon, title: title, isLast: isLast) {
                if store.theme == theme {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OWCDesign.accent)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}


private func settingsDetailFooter(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 13))
        .foregroundStyle(OWCDesign.secondary)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 8)
}

private extension View {
    func owcDivider() -> some View {
        overlay(alignment: .bottomTrailing) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }
}
