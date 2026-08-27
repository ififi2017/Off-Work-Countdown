import ActivityKit
import SwiftUI

struct ScheduleSettingsView: View {
    @Bindable var store: OffWorkStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var timeField: SetupTimeField?
    @State private var pendingMinutes: Int = 0
    /// Everything the user has changed and not yet saved. The page renders from
    /// this on top of the store, so an edit is visible immediately without
    /// having decided yet whether today counts.
    @State private var showSavePrompt = false
    @State private var savePromptFeedback = 0
    @State private var saveCommitFeedback = 0

    private var draft: ScheduleFieldChange {
        get { store.scheduleSettingsDraft }
        nonmutating set { store.scheduleSettingsDraft = newValue }
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
                OWCSectionHeader(title: store.t("scheduleHours"))
                    .padding(.top, 8)
                hoursCard
                    .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    modeRow(.classic, title: store.t("scheduleClassic"), subtitle: store.t("scheduleClassicDescription"))
                    modeRow(.alternating, title: store.t("scheduleAlternating"), subtitle: store.t("scheduleAlternatingDescription"))
                    modeRow(.rotation, title: store.t("scheduleRotation"), subtitle: store.t("scheduleRotationDescription"))
                    modeRow(.off, title: store.t("scheduleOff"), subtitle: store.t("scheduleOffDescription"), isLast: true)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                // Deliberately not animated — see OnboardingSchedulePage.
                scheduleDetails
                    .padding(.top, 22)

                Text(draftMode == .off ? store.t("scheduleOffSummaryNote") : store.t("scheduleSharedRulesNote"))
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
        .owcDetailBack(
            title: store.t("settings"),
            pageTitle: store.t("workSchedule"),
            hasUnsavedChanges: !draft.isEmpty,
            unsavedChangesTitle: store.t("unsavedChangesTitle"),
            keepEditingTitle: store.t("keepEditing"),
            discardChangesTitle: store.t("discardChanges"),
            onDiscardChanges: { draft = ScheduleFieldChange() }
        ) {
            ScheduleSaveButton(store: store, enabled: !draft.isEmpty, action: requestSave)
        }
        .sensoryFeedback(.selection, trigger: draftMode)
        .sensoryFeedback(.warning, trigger: savePromptFeedback)
        .sensoryFeedback(.success, trigger: saveCommitFeedback)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: $pendingMinutes
            )
            .presentationDetents([.medium])
            .onDisappear {
                if field == .start { edit { $0.startMinutes = pendingMinutes } }
                else { edit { $0.endMinutes = pendingMinutes } }
            }
        }
        .alert(store.t("applyScheduleTitle"), isPresented: $showSavePrompt) {
            Button(store.t("applyFromNextShift")) { commit(.nextShiftOnly) }
            Button(store.t("applyToToday")) { commit(.applyToToday) }
            // Cancel keeps the edits and the page. The user asked to save and
            // then thought better of the timing, not of the change.
            Button(store.t("cancelAction"), role: .cancel) {}
        } message: {
            Text(store.t("applyScheduleMessage"))
        }
    }

    private var hoursCard: some View {
        OWCGroupCard {
            Button {
                pendingMinutes = draftStart
                timeField = .start
            } label: {
                OWCRow(icon: "clock", title: store.t("startTime")) {
                    Text(store.timeString(draftStart))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
            Button {
                pendingMinutes = draftEnd
                timeField = .end
            } label: {
                OWCRow(icon: "clock", title: store.t("endTime"), isLast: true) {
                    Text(store.timeString(draftEnd))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
        }
    }

    // MARK: - Draft

    private var draftStart: Int { draft.startMinutes ?? store.startMinutes }
    private var draftEnd: Int { draft.endMinutes ?? store.endMinutes }
    private var draftWorkdays: Set<Int> { draft.workdays ?? store.workdays }
    private var draftMode: WorkScheduleMode { draft.scheduleMode ?? store.scheduleMode }
    private var draftRotationWorkDays: Int { draft.rotationWorkDays ?? store.rotationWorkDays }
    private var draftRotationRestDays: Int { draft.rotationRestDays ?? store.rotationRestDays }
    private var draftRotationCycleDay: Int { draft.rotationCycleDay ?? store.rotationCycleDay }
    private var draftRotationCycleLength: Int {
        max(2, draftRotationWorkDays + draftRotationRestDays)
    }

    private func edit(_ change: (inout ScheduleFieldChange) -> Void) {
        var next = draft
        change(&next)
        draft = next.settled(against: store)
    }

    /// A control's value, read through the draft and written back into it.
    private func binding<Value: Equatable>(
        _ field: WritableKeyPath<ScheduleFieldChange, Value?>,
        committed: Value
    ) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: field] ?? committed },
            set: { value in edit { $0[keyPath: field] = value } }
        )
    }

    private func commit(_ decision: ScheduleChangeDecision) {
        store.applyScheduleChange(draft, decision: decision)
        draft = ScheduleFieldChange()
        saveCommitFeedback += 1
    }

    private func requestSave() {
        guard !draft.isEmpty else { return }
        if store.shouldPromptApplyingToToday(draft, scope: .schedule) {
            savePromptFeedback += 1
            showSavePrompt = true
        } else {
            commit(.nextShiftOnly)
        }
    }


    @ViewBuilder
    private var scheduleDetails: some View {
        switch draftMode {
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
                        Picker(
                            store.t("alternatingCurrentWeek"),
                            selection: binding(\.alternatingWeekType, committed: store.alternatingWeekType)
                        ) {
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
                        Picker(
                            store.t("singleWeekWorkday"),
                            selection: binding(\.alternatingWeekendWorkday, committed: store.alternatingWeekendWorkday)
                        ) {
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
            // No re-anchoring here any more: the week type is a draft value
            // until Save, and `applyScheduleChange` anchors it at the moment it
            // commits. Anchoring on the picker moved the reference week for an
            // edit the user had not agreed to yet.
        case .rotation:
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("rotationPattern"))
                OWCGroupCard {
                    // Stepper puts its -/+ at the trailing edge of its own
                    // bounds, outside OWCRow's inset, so it needs the inset back
                    // or it sits flush against the card edge.
                    Stepper(value: binding(\.rotationWorkDays, committed: store.rotationWorkDays), in: 1...30) {
                        OWCRow(title: store.t("rotationWorkDays")) {
                            Text("\(draftRotationWorkDays)").monospacedDigit().foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()
                    Stepper(value: binding(\.rotationRestDays, committed: store.rotationRestDays), in: 1...30) {
                        OWCRow(title: store.t("rotationRestDays")) {
                            Text("\(draftRotationRestDays)").monospacedDigit().foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()

                    Menu {
                        // The cycle the user is looking at, not the saved one:
                        // shortening the work half has to shorten this list in
                        // the same breath, or it offers a day the pattern no
                        // longer has.
                        ForEach(1...draftRotationCycleLength, id: \.self) { day in
                            Button {
                                edit { $0.rotationCycleDay = day }
                            } label: {
                                Label(
                                    store.t(
                                        day <= draftRotationWorkDays ? "rotationWorkdayOption" : "rotationRestdayOption",
                                        values: ["day": "\(day)"]
                                    ),
                                    systemImage: day <= draftRotationWorkDays ? "briefcase" : "bed.double"
                                )
                            }
                        }
                    } label: {
                        OWCRow(
                            icon: "repeat",
                            title: store.t("rotationStartDay", values: ["day": "\(draftRotationCycleDay)"]),
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
                let selected = draftWorkdays.contains(day)
                let locked = selected && draftWorkdays.count == 1
                Button {
                    if locked { return }
                    var next = draftWorkdays
                    if selected { next.remove(day) } else { next.insert(day) }
                    edit { $0.workdays = next }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(label)
                            .font(.footnote.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 46)

                        if differentiateWithoutColor, selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(4)
                        }
                    }
                    .background(selected ? OWCDesign.accent : OWCDesign.control)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(locked ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(locked ? store.t("keepAtLeastOneWorkday") : "")
            }
        }
        .padding(12)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    private func modeRow(_ mode: WorkScheduleMode, title: String, subtitle: String, isLast: Bool = false) -> some View {
        Button {
            guard draftMode != mode else { return }
            edit { $0.scheduleMode = mode }
        } label: {
            OWCRow(
                title: title,
                subtitle: subtitle,
                isLast: isLast,
                centersVertically: true
            ) {
                ScheduleModeMark(selected: draftMode == mode)
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
    @State private var biometryStatus = BiometricGate.Status(biometry: .none, obstacle: nil)
    /// Bumped whenever the page reaches the background, so an authentication
    /// that resolves afterwards can tell it has been overtaken. This is
    /// `@State` rather than a phase read after `await`: an `@Environment` value
    /// is resolved into the view struct when `body` runs, and a suspended
    /// method holds that same struct. `@State` reads through its storage box,
    /// so it is current.
    @State private var lockGeneration = 0

    var body: some View {
        Group {
            if unlocked {
                content
            } else {
                locked
            }
        }
        .task { await unlock() }
        // Hide on UIKit's event, not on `scenePhase`.
        //
        // `scenePhase` is a derived value and it lags. Measured on device: for
        // a second or two after Face ID succeeds the page is visible and fully
        // interactive while SwiftUI still reports `.inactive` — it never
        // reported `.active` in between. Opening the app switcher in that
        // window therefore produced no phase change at all, nothing re-locked,
        // and the salary went into the thumbnail. Wait those two seconds first
        // and the same gesture hides it correctly, which is the tell: the
        // handler was fine, the signal was late.
        //
        // `willResignActive` fires on the gesture itself, whatever SwiftUI
        // currently believes the phase to be.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification
        )) { _ in
            unlocked = false
            focusedField = nil
        }
        // Backgrounding additionally voids an authentication still in flight:
        // its result can no longer be attributed to whoever holds the phone.
        // Kept separate from resigning active, because the biometric prompt
        // resigns active by itself and voiding there would retire the very
        // authentication the user is in the middle of passing.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )) { _ in
            unlocked = false
            focusedField = nil
            lockGeneration += 1
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
            if let obstacle = biometryStatus.obstacle {
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
                        Text(hintText(for: obstacle))
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

    /// Says which of the three obstacles it is, not just that there is one.
    ///
    /// This page used to print one generic "biometrics unavailable" line for
    /// all of them, while `canEvaluatePolicy` had handed us the exact reason
    /// and we threw it away. The three want different things: nothing enrolled
    /// is not a permission problem and no amount of visiting Settings > Privacy
    /// will fix it, and a lockout clears itself the moment the passcode is used
    /// once. Only the third is about permission, and only Face ID can reach it,
    /// because it is the only one that asks.
    private func hintText(for obstacle: BiometricGate.Obstacle) -> String {
        let biometry = store.biometryName(biometryStatus.biometry)
        return switch obstacle {
        case .notEnrolled: store.t("biometricsNotEnrolledHint", values: ["biometry": biometry])
        case .lockedOut: store.t("biometricsLockoutHint", values: ["biometry": biometry])
        case .notPermitted: store.t("biometricsUnavailableHint", values: ["app": OWCBrand.shortName])
        }
    }

    private func unlock() async {
        guard !unlocked else { return }
        biometryStatus = BiometricGate.status()
        let generation = lockGeneration
        let confirmed = await BiometricGate.confirmOwner(reason: store.t("unlockSalaryReason"))
        // Anything that voided this attempt while it was suspended wins: the
        // app went to the background with the prompt up, so the result can no
        // longer be said to belong to whoever is holding the phone now.
        // Deactivation alone does not count — see the phase handler above.
        guard generation == lockGeneration, confirmed else { return }

        // Apply the result immediately. Waiting for `.active` adds a visible
        // delay after Face ID because the successful policy evaluation often
        // finishes before SwiftUI reports the scene as active again. A Home
        // press while the policy is still being evaluated is a system
        // cancellation, so it cannot produce a success to apply here; a real
        // background transition is also rejected by the generation above.
        unlocked = true
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
    /// Sampled rather than read in `body` for the same reason `biometryStatus`
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
    @State private var showStartPicker = false
    @State private var pendingStartMinutes = 0
    /// The lunch window the user has changed and not yet saved. The two
    /// reminder switches below deliberately stay out of it: they decide whether
    /// a notification fires, not what shape the shift is, so there is no "does
    /// today count" question to ask about them.
    @State private var showSavePrompt = false
    @State private var savePromptFeedback = 0
    @State private var saveCommitFeedback = 0

    private var draft: ScheduleFieldChange {
        get { store.lunchSettingsDraft }
        nonmutating set { store.lunchSettingsDraft = newValue }
    }

    private var draftEnabled: Bool { draft.lunchEnabled ?? store.lunchEnabled }
    private var draftStartMinutes: Int { draft.lunchStartMinutes ?? store.lunchStartMinutes }
    private var draftDurationMinutes: Int { draft.lunchDurationMinutes ?? store.lunchDurationMinutes }

    private var lunchEnabledBinding: Binding<Bool> {
        Binding(
            get: { draftEnabled },
            set: { newValue in edit { $0.lunchEnabled = newValue } }
        )
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    OWCRow(title: store.t("lunchBreak"), isLast: !draftEnabled) {
                        Toggle(store.t("lunchBreak"), isOn: lunchEnabledBinding)
                            .labelsHidden()
                            .tint(OWCDesign.accent)
                    }

                    if draftEnabled {
                        OWCRow(title: store.t("lunchStartTime")) {
                            Button {
                                pendingStartMinutes = draftStartMinutes
                                showStartPicker = true
                            } label: {
                                OWCDetailAccessory(text: store.timeString(draftStartMinutes))
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .buttonStyle(.plain)
                        }

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
        .owcDetailBack(
            title: store.t("settings"),
            pageTitle: store.t("lunchBreak"),
            hasUnsavedChanges: hasUnsavedChanges,
            unsavedChangesTitle: store.t("unsavedChangesTitle"),
            keepEditingTitle: store.t("keepEditing"),
            discardChangesTitle: store.t("discardChanges"),
            onDiscardChanges: discardDraft
        ) {
            ScheduleSaveButton(store: store, enabled: hasUnsavedChanges, action: requestSave)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(store.t("done")) { durationFocused = false; clampDuration() }
            }
        }
        .onAppear { durationText = "\(draftDurationMinutes)" }
        .onChange(of: durationFocused) { _, focused in
            if !focused { clampDuration() }
        }
        .sensoryFeedback(.selection, trigger: draftEnabled)
        .sensoryFeedback(.selection, trigger: store.lunchStartReminderEnabled)
        .sensoryFeedback(.selection, trigger: store.lunchEndReminderEnabled)
        .sensoryFeedback(.warning, trigger: savePromptFeedback)
        .sensoryFeedback(.success, trigger: saveCommitFeedback)
        .sheet(isPresented: $showStartPicker) {
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t("lunchStartTime"),
                minutes: $pendingStartMinutes
            )
            .presentationDetents([.medium])
            .onDisappear { edit { $0.lunchStartMinutes = pendingStartMinutes } }
        }
        .alert(store.t("applyScheduleTitle"), isPresented: $showSavePrompt) {
            Button(store.t("applyFromNextShift")) { commit(.nextShiftOnly) }
            Button(store.t("applyToToday")) { commit(.applyToToday) }
            Button(store.t("cancelAction"), role: .cancel) {}
        } message: {
            Text(store.t("applyScheduleMessage"))
        }
    }

    private func edit(_ change: (inout ScheduleFieldChange) -> Void) {
        var next = draft
        change(&next)
        draft = next.settled(against: store)
    }

    private func commit(_ decision: ScheduleChangeDecision) {
        store.applyScheduleChange(draft, decision: decision)
        draft = ScheduleFieldChange()
        durationText = "\(store.lunchDurationMinutes)"
        saveCommitFeedback += 1
    }

    private func requestSave() {
        // The field commits on blur, so a value still being typed has not
        // reached the draft yet. Save is the last chance to settle it first.
        durationFocused = false
        clampDuration()
        guard !draft.isEmpty else { return }
        if store.shouldPromptApplyingToToday(draft, scope: .lunch) {
            savePromptFeedback += 1
            showSavePrompt = true
        } else {
            commit(.nextShiftOnly)
        }
    }

    private var hasUnsavedChanges: Bool {
        var leaving = draft
        let typed = Int(durationText) ?? draftDurationMinutes
        leaving.lunchDurationMinutes = min(180, max(10, typed))
        return !leaving.settled(against: store).isEmpty
    }

    private func discardDraft() {
        draft = ScheduleFieldChange()
        durationText = "\(store.lunchDurationMinutes)"
    }

    private func clampDuration() {
        let typed = Int(durationText) ?? draftDurationMinutes
        let clamped = min(180, max(10, typed))
        durationText = "\(clamped)"
        edit { $0.lunchDurationMinutes = clamped }
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

// MARK: - Editing a schedule without committing on every keystroke

extension ScheduleFieldChange {
    var isEmpty: Bool { self == ScheduleFieldChange() }

    /// Drops every field that already matches what the store holds.
    ///
    /// Without this, opening a picker and putting the value back would leave
    /// the page "dirty": Save lit up over nothing, and leaving asked whether a
    /// change that is not a change should include today.
    func settled(against store: OffWorkStore) -> ScheduleFieldChange {
        var next = self
        if next.startMinutes == store.startMinutes { next.startMinutes = nil }
        if next.endMinutes == store.endMinutes { next.endMinutes = nil }
        if next.workdays == store.workdays { next.workdays = nil }
        if next.scheduleMode == store.scheduleMode { next.scheduleMode = nil }
        if next.lunchEnabled == store.lunchEnabled { next.lunchEnabled = nil }
        if next.lunchStartMinutes == store.lunchStartMinutes { next.lunchStartMinutes = nil }
        if next.lunchDurationMinutes == store.lunchDurationMinutes { next.lunchDurationMinutes = nil }
        if next.alternatingWeekType == store.alternatingWeekType { next.alternatingWeekType = nil }
        if next.alternatingWeekendWorkday == store.alternatingWeekendWorkday {
            next.alternatingWeekendWorkday = nil
        }
        if next.rotationWorkDays == store.rotationWorkDays { next.rotationWorkDays = nil }
        if next.rotationRestDays == store.rotationRestDays { next.rotationRestDays = nil }
        if next.rotationCycleDay == store.rotationCycleDay { next.rotationCycleDay = nil }
        return next
    }
}

/// Trailing header control on a page that is saved rather than committed
/// field by field.
///
/// Matches the back chevron: a compact 30 pt glass control. The old capsule label
/// (`Enregistrer`, `Сохранить`, `जतन करा`) could crowd the compact header
/// and, with `.glassEffect` inside a `.plain` button, sometimes ate the tap
/// on device. The checkmark keeps the hit target and the VoiceOver name.
struct ScheduleSaveButton: View {
    let store: OffWorkStore
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(store.t("saveAction"), systemImage: "checkmark", action: action)
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .buttonStyle(.glass)
        .tint(enabled ? OWCDesign.accent : nil)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

private extension View {
    func owcDivider() -> some View {
        overlay(alignment: .bottomTrailing) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }
}
