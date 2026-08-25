import ActivityKit
import SwiftUI

struct ScheduleSettingsView: View {
    @Bindable var store: OffWorkStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

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
                    .font(.footnote)
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
                            .font(.subheadline.weight(.semibold))
                        Picker(store.t("alternatingCurrentWeek"), selection: $store.alternatingWeekType) {
                            Text(store.t("singleRestWeek")).tag(AlternatingWeekType.single)
                            Text(store.t("doubleRestWeek")).tag(AlternatingWeekType.double)
                        }
                        .pickerStyle(.segmented)
                        Text(store.t("alternatingCurrentWeekDescription"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .owcPlainDivider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(store.t("singleWeekWorkday"))
                            .font(.subheadline.weight(.semibold))
                        Picker(store.t("singleWeekWorkday"), selection: $store.alternatingWeekendWorkday) {
                            Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[5]])).tag(6)
                            Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[6]])).tag(0)
                        }
                        .pickerStyle(.segmented)
                        Text(store.t("singleWeekWorkdayDescription"))
                            .font(.footnote)
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
                                .font(.footnote.weight(.semibold))
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
                    ZStack(alignment: .topTrailing) {
                        Text(label)
                            .font(.footnote.weight(store.workdays.contains(day) ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(store.workdays.contains(day) ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 46)

                        if differentiateWithoutColor, store.workdays.contains(day) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(4)
                        }
                    }
                    .background(store.workdays.contains(day) ? OWCDesign.accent : OWCDesign.control)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.workdays.contains(day) ? .isSelected : [])
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
                    .font(.title3)
                    .foregroundStyle(store.scheduleMode == mode ? OWCDesign.accent : OWCDesign.tertiary)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}

struct SalaryDesignView: View {
    @Bindable var store: OffWorkStore
    private enum Field { case amount, bonus }
    @FocusState private var focusedField: Field?
    @State private var amountText = ""
    /// Salary is the one thing in here worth shoulder-surfing, so the page does
    /// not render it until the device owner has confirmed it is them. Devices
    /// with no passcode pass straight through — see `BiometricGate`.
    @State private var unlocked = false
    /// Sampled alongside each unlock attempt rather than read in `body`, which
    /// would build an `LAContext` on every render.
    @State private var biometryBlocked = false
    /// Bumped by every re-lock, so an authentication that resolves afterwards
    /// can tell it has been overtaken. `@State` and not `scenePhase`: an
    /// `@Environment` value is resolved into the view struct when `body` runs,
    /// and an `async` method that suspends holds that same struct — reading
    /// `scenePhase` after an `await` reads the phase from before it. `@State`
    /// reads through its storage box, so it is current.
    @State private var lockGeneration = 0
    /// The scene phase, mirrored into `@State` so `unlock()` can read it after
    /// its `await`. The `@Environment` value below cannot answer that question:
    /// it is resolved into the view struct when `body` runs, and a suspended
    /// `async` method still holds that struct, so it reports the phase from
    /// before the suspension.
    @State private var livePhase: ScenePhase = .active
    /// A successful authentication that landed while the scene was away.
    ///
    /// Held rather than applied, because applying it would draw the salary
    /// while the app is inactive — which is the state the app switcher shows
    /// live, before the snapshot. Locking again at `.background` would be too
    /// late; the figures would already be on screen and in the thumbnail.
    @State private var pendingUnlock = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if unlocked {
                content
            } else {
                locked
            }
        }
        .task { await unlock() }
        // Re-lock whenever the app stops being frontmost. The page used to stay
        // unlocked for as long as it sat on the navigation stack — `unlocked`
        // only ever moved to `true` — so coming back from the app switcher, or
        // handing the phone over, showed the salary with no second look at who
        // was holding it.
        // `initial: true` seeds `livePhase`, which otherwise would not learn the
        // truth until the first change.
        .onChange(of: scenePhase, initial: true) { _, phase in
            livePhase = phase

            guard phase != .active else {
                // Back in front, and nothing voided the attempt while we were
                // away: show what it earned.
                if pendingUnlock {
                    pendingUnlock = false
                    unlocked = true
                }
                return
            }

            // Hiding, voiding and deferring are three decisions. Making them
            // with one line is what locked this page out of its own key.

            // Hide on either non-active phase: the app switcher shows the scene
            // live at `.inactive`, before any snapshot is taken.
            unlocked = false
            focusedField = nil

            // Void only on `.background`. The biometric prompt deactivates the
            // scene by itself, so voiding at `.inactive` retired the very
            // authentication the user was in the middle of passing. Background
            // is the one phase the prompt does not cause, and the one where its
            // result can no longer be attributed to whoever holds the phone.
            if phase == .background {
                lockGeneration += 1
                pendingUnlock = false
            }
        }
    }

    /// Laid out by hand rather than with `ContentUnavailableView`: that view
    /// sizes its action to the button's own width, which squeezed a full-width
    /// primary button into a stubby blob. The unlock button belongs at the
    /// bottom edge, the same shape and place as every other primary action.
    private var locked: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(OWCDesign.secondary)
            Text(store.t("salaryLocked"))
                .font(.title3.weight(.semibold))
                .padding(.top, 16)
            Text(store.t("unlockSalaryReason"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()

            Button(store.t("unlockSalary")) {
                Task { await unlock() }
            }
            .buttonStyle(OWCPrimaryButtonStyle())

            // Only when the hardware exists but the app cannot reach it. iOS
            // asks for biometric permission once and never again, so without
            // this the page would go on quietly demanding a passcode with no
            // hint that Face ID could be switched back on, and nothing in the
            // app could ever bring the prompt back.
            if biometryBlocked {
                Link(destination: OWCSystemSettings.applicationURL) {
                    HStack(spacing: 5) {
                        // Names the app, because `app-settings:` cannot be
                        // trusted to land on its page: since iOS 18 reorganised
                        // Settings the link drops the user at the root, where
                        // third-party apps sit inside a list rather than at the
                        // top level. The copy stops at "the app list" instead of
                        // naming Apple's own section — that label is localised
                        // by iOS, and guessing it in nineteen languages would be
                        // worse than leaving it out.
                        Text(store.t(
                            "biometricsUnavailableHint",
                            values: ["app": store.t("appShortName")]
                        ))
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(.bottom, 24)
        .padding(.horizontal, OWCDesign.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OWCDesign.page)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("salarySettings"))
    }

    private func unlock() async {
        guard !unlocked else { return }
        biometryBlocked = BiometricGate.isBiometryBlocked
        let generation = lockGeneration
        let confirmed = await BiometricGate.confirmOwner(reason: store.t("unlockSalaryReason"))
        // Anything that voided this attempt while it was suspended wins: the
        // app went to the background with the prompt up, so the result can no
        // longer be said to belong to whoever is holding the phone now.
        // Deactivation alone does not count — see the phase handler above.
        guard generation == lockGeneration, confirmed else { return }

        // Nothing says `evaluatePolicy` resolves only once the scene is active
        // again, and the phase it resolves in is frequently `.inactive` — the
        // prompt put it there. Revealing the salary then would paint it into
        // whatever the app switcher is about to capture, and re-locking at
        // `.background` would arrive after the fact. Hold it for `.active`.
        if livePhase == .active {
            unlocked = true
        } else {
            pendingUnlock = true
        }
    }

    private var content: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
            OWCGroupCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.t("enableSalary")).font(.body)
                        Text(store.t("enableSalaryDescription")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                    }
                    Spacer()
                    Toggle(store.t("enableSalary"), isOn: $store.salaryEnabled).labelsHidden()
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
                        .font(.body)
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
                                .font(.body)
                                .foregroundStyle(OWCDesign.primary)
                            Spacer()
                            Text(Int(store.monthlyWorkingDays).formatted())
                                .font(.body.monospacedDigit())
                                .foregroundStyle(OWCDesign.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
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
                        .font(.body)
                    Spacer()
                    Toggle(store.t("annualBonus"), isOn: $store.annualBonusEnabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcPlainDivider()

                if store.annualBonusEnabled {
                    HStack {
                        Text(store.t("annualBonusMonths")).font(.body)
                        Spacer()
                        TextField("0", value: $store.annualBonusMonths, format: .number.precision(.fractionLength(0...2)))
                            .font(.body.weight(.semibold).monospacedDigit())
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
                        .font(.body)
                    Spacer()
                    Toggle(store.t("hideSalary"), isOn: $store.hideEarnings)
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
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(store.hideEarnings ? "••••" : store.formatMoney(earnedNow))
                    .font(.largeTitle.bold().monospacedDigit())
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
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(title: store.t("perEffectiveHour"), isLast: true) {
                        Text(store.hideEarnings ? "••••" : store.formatMoney(hourlySalary))
                            .font(.body.monospacedDigit())
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
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 8)
    }
}

struct NotificationDesignView: View {
    @Bindable var store: OffWorkStore
    @Environment(NotificationService.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The system's own Live Activities switch, which is not the notification
    /// permission and can be turned off on its own.
    ///
    /// Sampled rather than read in `body` for the same reason `biometryBlocked`
    /// is, and refreshed on the way back from Settings, which is where it
    /// changes. The page used to state "allowed" and draw a checkmark
    /// unconditionally while `LiveActivityService` quietly bailed out on the
    /// real value — so the toggle moved and nothing ever appeared.
    @State private var activitiesEnabled = true

    var body: some View {
        Group {
            if notifications.status == .denied {
                deniedContent
            } else {
                settingsContent
            }
        }
        .background(OWCDesign.page)
        .task { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
        // Coming back from Settings is exactly when this changes.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
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

            liveActivitySection

            detailFooter(store.t("liveActivityScheduleNote"))

            detailFooter(store.t("notificationPrivacyNote"))
            Spacer(minLength: 8)
        }
    }

    /// The Live Activity controls, shown whether or not local notifications
    /// were allowed.
    ///
    /// These are two different permissions. Local notifications are governed by
    /// `UNUserNotificationCenter`; Live Activities have their own switch and
    /// their own `ActivityAuthorizationInfo.areActivitiesEnabled`. The denied
    /// page used to replace the whole screen, which left the user unable to
    /// turn the Live Activity on or off or change its lead time — while that
    /// same page told them, correctly, that Live Activities still worked.
    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: store.t("liveActivity"))
            OWCGroupCard {
                HStack {
                    Text(store.t("lockScreenLiveActivity"))
                        .font(.body)
                    Spacer()
                    Toggle(store.t("lockScreenLiveActivity"), isOn: $store.liveActivityEnabled)
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
                .font(.body)
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 16)
    }

    private var deniedContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(OWCDesign.orangeDeep)
                        .frame(width: 38, height: 38)
                        .background(OWCDesign.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("notificationDeniedTitle"))
                            .font(.body.weight(.semibold))
                        Text(store.t("notificationDeniedBody"))
                            .font(.subheadline)
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

            liveActivitySection

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("notificationCapability"))
                OWCGroupCard {
                    OWCRow(title: store.t("notificationLocal")) {
                        Text(store.t("notificationDeniedStatus"))
                            .font(.body)
                            .foregroundStyle(OWCDesign.orangeDeep)
                    }
                    OWCRow(title: store.t("liveActivity")) {
                        Text(store.t(activitiesEnabled
                                     ? "notificationAllowedStatus"
                                     : "notificationDeniedStatus"))
                            .font(.body)
                            .foregroundStyle(activitiesEnabled ? OWCDesign.secondary : OWCDesign.orangeDeep)
                    }
                    OWCRow(title: store.t("notificationScheduledForShift"), isLast: true) {
                        Text("0 / 0")
                            .font(.body.monospacedDigit())
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
                        Image(systemName: activitiesEnabled ? "checkmark" : "xmark")
                            .font(.headline)
                            .foregroundStyle(activitiesEnabled ? OWCDesign.orange : OWCDesign.secondary)
                    }
                    OWCRow(icon: "square.grid.2x2", title: store.t("notificationHomeWidget"), isLast: true) {
                        Image(systemName: "checkmark")
                            .font(.headline)
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
            store.notificationMode = mode
            if mode != .off, notifications.status == .notDetermined {
                Task { @MainActor in
                    let granted = await notifications.request()
                    if granted {
                        await notifications.reschedule(store: store)
                    } else {
                        store.notificationMode = .off
                    }
                }
            }
        } label: {
            OWCRow(title: title, isLast: isLast) {
                if store.notificationMode == mode {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(OWCDesign.orange)
                        .transition(notificationModeTransition)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .animation(notificationModeAnimation, value: store.notificationMode)
    }

    private var notificationModeAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.selection
    }

    private var notificationModeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95))
    }

    private func detailFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
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
    @Bindable var store: OffWorkStore
    @FocusState private var durationFocused: Bool
    @State private var durationText = ""

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack {
                        Text(store.t("lunchBreak")).font(.body)
                        Spacer()
                        Toggle(store.t("lunchBreak"), isOn: $store.lunchEnabled).labelsHidden()
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
                        .font(.body)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .owcDivider()

                        HStack {
                            Text(store.t("lunchDuration")).font(.body)
                            Spacer()
                            OWCNumberField(
                                placeholder: "60",
                                text: $durationText,
                                width: 72,
                                onCommit: clampDuration
                            )
                            .focused($durationFocused)
                            Text(store.t("minutesUnit"))
                                .font(.callout)
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
                        Text(store.t("lunchStartReminder")).font(.body)
                        Spacer()
                        Toggle(store.t("lunchStartReminder"), isOn: $store.lunchStartReminderEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .owcDivider()

                    HStack {
                        Text(store.t("lunchEndReminder")).font(.body)
                        Spacer()
                        Toggle(store.t("lunchEndReminder"), isOn: $store.lunchEndReminderEnabled).labelsHidden()
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
    @Bindable var store: OffWorkStore
    @FocusState private var intervalFocused: Bool
    @State private var intervalText = ""

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack {
                        Text(store.t("microBreakReminder")).font(.body)
                        Spacer()
                        Toggle(store.t("microBreakReminder"), isOn: $store.microBreakEnabled).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)

                    if store.microBreakEnabled {
                        HStack {
                            Text(store.t("microBreakInterval")).font(.body)
                            Spacer()
                            OWCNumberField(
                                placeholder: "60",
                                text: $intervalText,
                                width: 72,
                                onCommit: clampInterval
                            )
                            .focused($intervalFocused)
                            Text(store.t("minutesUnit"))
                                .font(.callout)
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
    @Bindable var store: OffWorkStore

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
                        .font(.headline)
                        .foregroundStyle(OWCDesign.accent)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}


/// The language list, mirroring the theme page: "System" first, then every
/// language this build ships, each written in itself.
///
/// This page exists because the system route did not work. `chooselanguage`
/// used to jump to `UIApplication.openSettingsURLString`, which since iOS 18
/// drops the user at the Settings root rather than on the app's own page — and
/// third-party apps now live two levels down under "Apps", so nobody found the
/// language row. Nothing was wrong with the bundle: all nineteen localizations
/// ship and iOS does offer the choice, on a page we could not navigate to.
struct LanguageSettingsView: View {
    @Bindable var store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                languageRow(nil, title: store.t("auto"))
                ForEach(Array(NativeLocalizer.supportedLanguages.enumerated()), id: \.element.id) { index, language in
                    languageRow(
                        language.id,
                        // Each language names itself, so somebody stranded in a
                        // language they cannot read can still find their way out.
                        title: language.name,
                        isLast: index == NativeLocalizer.supportedLanguages.count - 1
                    )
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)

            settingsDetailFooter(store.t("languageFooter"))
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("chooselanguage"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("chooselanguage"))
        .sensoryFeedback(.selection, trigger: store.languageOverride)
    }

    private func languageRow(_ code: String?, title: String, isLast: Bool = false) -> some View {
        Button { store.languageOverride = code } label: {
            OWCRow(icon: nil, title: title, isLast: isLast) {
                if store.languageOverride == code {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(OWCDesign.accent)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}


private func settingsDetailFooter(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
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
