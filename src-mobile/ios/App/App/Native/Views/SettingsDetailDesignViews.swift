import ActivityKit
import SwiftUI

struct ScheduleSettingsView: View {
    @Environment(SceneState.self) private var scene
    @Bindable var shifts: ShiftSessionStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var timeField: SetupTimeField?
    @State private var pendingMinutes: Int = 0
    /// Everything the user has changed and not yet saved. The page renders from
    /// this on top of the shifts, so an edit is visible immediately without
    /// having decided yet whether today counts.
    @State private var showSavePrompt = false
    @State private var savePromptFeedback = 0
    @State private var saveCommitFeedback = 0
    @FocusState private var lunchDurationFocused: Bool
    @State private var lunchDurationText = ""
    @State private var showLunchStartPicker = false
    @State private var pendingLunchStartMinutes = 0

    private var draft: ScheduleFieldChange {
        get { scene.scheduleSettingsDraft }
        nonmutating set { scene.scheduleSettingsDraft = newValue }
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
                OWCSectionHeader(title: shifts.text.t("scheduleHours"))
                    .padding(.top, 8)
                hoursCard
                    .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    modeRow(.classic, title: shifts.text.t("scheduleClassic"), subtitle: shifts.text.t("scheduleClassicDescription"))
                    modeRow(.alternating, title: shifts.text.t("scheduleAlternating"), subtitle: shifts.text.t("scheduleAlternatingDescription"))
                    modeRow(.rotation, title: shifts.text.t("scheduleRotation"), subtitle: shifts.text.t("scheduleRotationDescription"))
                    modeRow(.off, title: shifts.text.t("scheduleOff"), subtitle: shifts.text.t("scheduleOffDescription"), isLast: true)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                // Deliberately not animated — see OnboardingSchedulePage.
                scheduleDetails
                    .padding(.top, 22)

                Text(draftMode == .off ? shifts.text.t("scheduleOffSummaryNote") : shifts.text.t("scheduleSharedRulesNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 9)

                // Lunch is part of the shift's shape, so it is edited and saved
                // with the hours rather than on a page of its own.
                OWCSectionHeader(title: shifts.text.t("lunchBreak"))
                    .padding(.top, 20)
                lunchCard
                    .padding(.horizontal, OWCDesign.pageInset)
                settingsDetailFooter(
                    shifts.preferences.salaryEnabled
                        ? shifts.text.t("lunchPauseNote")
                        : shifts.text.t("lunchPauseNoteNoSalary")
                )
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OWCDesign.page)
        .navigationTitle(shifts.text.t("workSchedule"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(
            title: shifts.text.t("settings"),
            pageTitle: shifts.text.t("workSchedule"),
            hasUnsavedChanges: hasUnsavedChanges,
            unsavedChangesTitle: shifts.text.t("unsavedChangesTitle"),
            keepEditingTitle: shifts.text.t("keepEditing"),
            discardChangesTitle: shifts.text.t("discardChanges"),
            onDiscardChanges: discardDraft
        ) {
            ScheduleSaveButton(text: shifts.text, enabled: hasUnsavedChanges, action: requestSave)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(shifts.text.t("done")) { lunchDurationFocused = false; clampLunchDuration() }
            }
        }
        .onAppear { lunchDurationText = "\(draftLunchDurationMinutes)" }
        .onChange(of: lunchDurationFocused) { _, focused in
            if !focused { clampLunchDuration() }
        }
        .sensoryFeedback(.selection, trigger: draftMode)
        .sensoryFeedback(.selection, trigger: draftLunchEnabled)
        .sensoryFeedback(.warning, trigger: savePromptFeedback)
        .sensoryFeedback(.success, trigger: saveCommitFeedback)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                session: shifts.session,
                text: shifts.text,
                title: shifts.text.t(field == .start ? "startTime" : "endTime"),
                minutes: $pendingMinutes
            )
            .presentationDetents([.medium])
            .onDisappear {
                if field == .start { edit { $0.startMinutes = pendingMinutes } }
                else { edit { $0.endMinutes = pendingMinutes } }
            }
        }
        .alert(shifts.text.t("applyScheduleTitle"), isPresented: $showSavePrompt) {
            Button(shifts.text.t("applyFromNextShift")) { commit(.nextShiftOnly) }
            Button(shifts.text.t("applyToToday")) { commit(.applyToToday) }
            // Cancel keeps the edits and the page. The user asked to save and
            // then thought better of the timing, not of the change.
            Button(shifts.text.t("cancelAction"), role: .cancel) {}
        } message: {
            Text(shifts.text.t("applyScheduleMessage"))
        }
    }

    private var hoursCard: some View {
        OWCGroupCard {
            Button {
                pendingMinutes = draftStart
                timeField = .start
            } label: {
                OWCRow(icon: "clock", title: shifts.text.t("startTime")) {
                    Text(shifts.session.timeString(draftStart))
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
                OWCRow(icon: "clock", title: shifts.text.t("endTime"), isLast: true) {
                    Text(shifts.session.timeString(draftEnd))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
        }
    }

    private var lunchCard: some View {
        OWCGroupCard {
            OWCRow(title: shifts.text.t("lunchBreak"), isLast: !draftLunchEnabled) {
                Toggle(shifts.text.t("lunchBreak"), isOn: binding(\.lunchEnabled, committed: shifts.preferences.lunchEnabled))
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }

            if draftLunchEnabled {
                OWCRow(title: shifts.text.t("lunchStartTime")) {
                    Button {
                        pendingLunchStartMinutes = draftLunchStartMinutes
                        showLunchStartPicker = true
                    } label: {
                        OWCDetailAccessory(text: shifts.session.timeString(draftLunchStartMinutes))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text(shifts.text.t("lunchDuration")).font(.body)
                    Spacer()
                    OWCNumberField(
                        placeholder: "60",
                        text: $lunchDurationText,
                        width: 72,
                        onCommit: clampLunchDuration
                    )
                    .focused($lunchDurationFocused)
                    Text(shifts.text.t("minutesUnit"))
                        .font(.callout)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
        }
        // Its own sheet, so it does not share the hours picker's item binding.
        .sheet(isPresented: $showLunchStartPicker) {
            OWCSetupTimePickerSheet(
                session: shifts.session,
                text: shifts.text,
                title: shifts.text.t("lunchStartTime"),
                minutes: $pendingLunchStartMinutes
            )
            .presentationDetents([.medium])
            .onDisappear { edit { $0.lunchStartMinutes = pendingLunchStartMinutes } }
        }
    }

    // MARK: - Draft

    private var draftLunchEnabled: Bool { draft.lunchEnabled ?? shifts.preferences.lunchEnabled }
    private var draftLunchStartMinutes: Int { draft.lunchStartMinutes ?? shifts.preferences.lunchStartMinutes }
    private var draftLunchDurationMinutes: Int { draft.lunchDurationMinutes ?? shifts.preferences.lunchDurationMinutes }

    /// A duration still being typed has not reached the draft; leaving or
    /// saving must count it all the same.
    private var hasUnsavedChanges: Bool {
        var leaving = draft
        let typed = Int(lunchDurationText) ?? draftLunchDurationMinutes
        leaving.lunchDurationMinutes = min(180, max(10, typed))
        return !leaving.settled(against: shifts.preferences).isEmpty
    }

    private func discardDraft() {
        draft = ScheduleFieldChange()
        lunchDurationText = "\(shifts.preferences.lunchDurationMinutes)"
    }

    private func clampLunchDuration() {
        let typed = Int(lunchDurationText) ?? draftLunchDurationMinutes
        let clamped = min(180, max(10, typed))
        lunchDurationText = "\(clamped)"
        edit { $0.lunchDurationMinutes = clamped }
    }

    private var draftStart: Int { draft.startMinutes ?? shifts.preferences.startMinutes }
    private var draftEnd: Int { draft.endMinutes ?? shifts.preferences.endMinutes }
    private var draftWorkdays: Set<Int> { draft.workdays ?? shifts.preferences.workdays }
    private var draftMode: WorkScheduleMode { draft.scheduleMode ?? shifts.preferences.scheduleMode }
    private var draftRotationWorkDays: Int { draft.rotationWorkDays ?? shifts.preferences.rotationWorkDays }
    private var draftRotationRestDays: Int { draft.rotationRestDays ?? shifts.preferences.rotationRestDays }
    private var draftRotationCycleDay: Int { draft.rotationCycleDay ?? shifts.preferences.rotationCycleDay }
    private var draftRotationCycleLength: Int {
        max(2, draftRotationWorkDays + draftRotationRestDays)
    }

    private func edit(_ change: (inout ScheduleFieldChange) -> Void) {
        var next = draft
        change(&next)
        draft = next.settled(against: shifts.preferences)
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
        let command = scene.commitScheduleDraft(decision: decision, using: shifts)
        Task {
            guard await command.value else { return }
            if draft.isEmpty { lunchDurationText = "\(shifts.preferences.lunchDurationMinutes)" }
            saveCommitFeedback += 1
        }
    }

    private func requestSave() {
        // The field commits on blur, so settle a value still being typed first.
        lunchDurationFocused = false
        clampLunchDuration()
        guard !draft.isEmpty else { return }
        // The shared rules give hours and lunch the same answer about today,
        // so one question covers the whole page.
        if shifts.session.shouldPromptApplyingToToday(draft, scope: .schedule) {
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
                OWCSectionHeader(title: shifts.text.t("workdaysLabel"))
                weekdayGrid
            }
            .padding(.horizontal, OWCDesign.pageInset)
        case .alternating:
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: shifts.text.t("alternatingCurrentWeek"))
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(shifts.text.t("alternatingCurrentWeek"))
                            .font(.subheadline.weight(.semibold))
                        Picker(
                            shifts.text.t("alternatingCurrentWeek"),
                            selection: binding(\.alternatingWeekType, committed: shifts.preferences.alternatingWeekType)
                        ) {
                            Text(shifts.text.t("singleRestWeek")).tag(AlternatingWeekType.single)
                            Text(shifts.text.t("doubleRestWeek")).tag(AlternatingWeekType.double)
                        }
                        .pickerStyle(.segmented)
                        Text(shifts.text.t("alternatingCurrentWeekDescription"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .owcPlainDivider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(shifts.text.t("singleWeekWorkday"))
                            .font(.subheadline.weight(.semibold))
                        Picker(
                            shifts.text.t("singleWeekWorkday"),
                            selection: binding(\.alternatingWeekendWorkday, committed: shifts.preferences.alternatingWeekendWorkday)
                        ) {
                            Text(shifts.text.t("workOnWeekday", values: ["day": shifts.text.weekdayLabels()[5]])).tag(6)
                            Text(shifts.text.t("workOnWeekday", values: ["day": shifts.text.weekdayLabels()[6]])).tag(0)
                        }
                        .pickerStyle(.segmented)
                        Text(shifts.text.t("singleWeekWorkdayDescription"))
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
                OWCSectionHeader(title: shifts.text.t("rotationPattern"))
                OWCGroupCard {
                    // Stepper puts its -/+ at the trailing edge of its own
                    // bounds, outside OWCRow's inset, so it needs the inset back
                    // or it sits flush against the card edge.
                    Stepper(value: binding(\.rotationWorkDays, committed: shifts.preferences.rotationWorkDays), in: 1...30) {
                        OWCRow(title: shifts.text.t("rotationWorkDays")) {
                            Text("\(draftRotationWorkDays)").monospacedDigit().foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .buttonStyle(OWCRowButtonStyle())
                    .owcPlainDivider()
                    Stepper(value: binding(\.rotationRestDays, committed: shifts.preferences.rotationRestDays), in: 1...30) {
                        OWCRow(title: shifts.text.t("rotationRestDays")) {
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
                                    shifts.text.t(
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
                            title: shifts.text.t("rotationStartDay", values: ["day": "\(draftRotationCycleDay)"]),
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
                OWCRow(icon: "calendar.badge.minus", title: shifts.text.t("scheduleOffManualStart"), isLast: true) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OWCDesign.accent)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
        }
    }

    private var weekdayGrid: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], shifts.text.weekdayLabels())), id: \.0) { day, label in
                let selected = draftWorkdays.contains(day)
                let locked = selected && draftWorkdays.count == 1
                OWCWeekdayButton(
                    label: label, selected: selected, locked: locked,
                    differentiateWithoutColor: differentiateWithoutColor,
                    lockedHint: shifts.text.t("keepAtLeastOneWorkday")
                ) {
                    var next = draftWorkdays
                    if selected { next.remove(day) } else { next.insert(day) }
                    edit { $0.workdays = next }
                }
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
    @Bindable var shifts: ShiftSessionStore
    private enum Field { case amount, bonus }
    @FocusState private var focusedField: Field?
    @State private var amountDraft = SettingsFieldDraft("")
    @State private var bonusDraft = SettingsFieldDraft(0.0)
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
            Text(shifts.text.t("salaryLocked"))
                .font(.title3.weight(.semibold))
                .padding(.top, 16)
            Text(shifts.text.t("unlockSalaryReason"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()

            Button(shifts.text.t("unlockSalary")) {
                Task { await unlock() }
            }
            .buttonStyle(OWCPrimaryButtonStyle())

            // Only when the hardware exists but the app cannot reach it. iOS
            // asks for biometric permission once and never again, so without
            // this the page would go on quietly demanding a passcode with no
            // hint that Face ID could be switched back on, and nothing in the
            // app could ever bring the prompt back.
            if let obstacle = biometryStatus.obstacle {
                Link(destination: BiometricGate.applicationSettingsURL) {
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
        .owcDetailBack(title: shifts.text.t("settings"), pageTitle: shifts.text.t("salarySettings"))
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
        let biometry = shifts.text.biometryName(biometryStatus.biometry)
        return switch obstacle {
        case .notEnrolled: shifts.text.t("biometricsNotEnrolledHint", values: ["biometry": biometry])
        case .lockedOut: shifts.text.t("biometricsLockoutHint", values: ["biometry": biometry])
        case .notPermitted: shifts.text.t("biometricsUnavailableHint", values: ["app": OWCBrand.shortName])
        }
    }

    private func unlock() async {
        guard !unlocked else { return }
        biometryStatus = BiometricGate.status()
        let generation = lockGeneration
        let confirmed = await BiometricGate.confirmOwner(reason: shifts.text.t("unlockSalaryReason"))
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
        // Focus changes rebuild this view while the keyboard is animating, so
        // take one snapshot and derive every salary value from that same
        // result instead of resolving the shift separately for each row.
        let preview = salaryPreview(from: shifts.session.snapshot())

        return OWCContentSizedScrollView {
            VStack(spacing: 0) {
            OWCGroupCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shifts.text.t("enableSalary")).font(.body)
                        Text(shifts.text.t("enableSalaryDescription")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                    }
                    Spacer()
                    Toggle(shifts.text.t("enableSalary"), isOn: shifts.preferences.preferenceBinding(\.salaryEnabled)).labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)

            if shifts.preferences.salaryEnabled {
            Picker(shifts.text.t("salaryType"), selection: shifts.preferences.preferenceBinding(\.salaryType)) {
                Text(shifts.text.t("monthly")).tag(SalaryType.monthly)
                Text(shifts.text.t("daily")).tag(SalaryType.daily)
            }
            .pickerStyle(.segmented)
            .frame(height: 44)
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 18)

            OWCGroupCard {
                HStack {
                    Text(shifts.text.t("amount"))
                        .font(.body)
                    Spacer()
                    if shifts.preferences.hideEarnings {
                        Text("••••")
                        // This page has already authenticated the owner. A
                        // second prompt resigns active and re-locks the page,
                        // while the generic eye only restores hideEarnings.
                        // Match the visibility toggle inside this same gate.
                        Button { shifts.preferences.hideEarnings = false } label: {
                            Image(systemName: "eye")
                        }
                        .accessibilityLabel(shifts.text.t("unlockSalary"))
                    } else {
                        OWCNumberField(
                            placeholder: "0",
                            text: $amountDraft.value,
                            decimal: true,
                            maxDigits: 9,
                            emphasized: true,
                            onCommit: commitSalaryFields
                        )
                        .focused($focusedField, equals: .amount)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcPlainDivider()

                if shifts.preferences.salaryType == .monthly {
                    Menu {
                        ForEach(15...31, id: \.self) { value in
                            Button("\(value)") { shifts.preferences.applyPreferences { $0.monthlyWorkingDays = Double(value) } }
                        }
                    } label: {
                        HStack {
                            Text(shifts.text.t("monthlyWorkingDays"))
                                .font(.body)
                                .foregroundStyle(OWCDesign.primary)
                            Spacer()
                            Text(Int(shifts.preferences.monthlyWorkingDays).formatted())
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
                    Text(shifts.text.t("annualBonus"))
                        .font(.body)
                    Spacer()
                    Toggle(shifts.text.t("annualBonus"), isOn: shifts.preferences.preferenceBinding(\.annualBonusEnabled))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcPlainDivider()

                if shifts.preferences.annualBonusEnabled {
                    HStack {
                        Text(shifts.text.t("annualBonusMonths")).font(.body)
                        Spacer()
                        TextField("0", value: $bonusDraft.value, format: .number.precision(.fractionLength(0...2)))
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
                    Text(shifts.text.t("hideSalary"))
                        .font(.body)
                    Spacer()
                    Toggle(shifts.text.t("hideSalary"), isOn: Binding(get: { shifts.preferences.hideEarnings }, set: { shifts.preferences.hideEarnings = $0 }))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)

            detailFooter(shifts.text.t("salaryPrivacyNote"))

            VStack(alignment: .leading, spacing: 6) {
                Text(shifts.text.t("moneyEarned"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(shifts.text.moneyText(preview.earnedNow))
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
                OWCSectionHeader(title: shifts.text.t("derivedFromThis"))
                OWCGroupCard {
                    OWCRow(title: shifts.text.t("perWorkday")) {
                        Text(shifts.text.moneyText(preview.dailySalary))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(title: shifts.text.t("perEffectiveHour"), isLast: true) {
                        Text(shifts.text.moneyText(preview.hourlySalary))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 20)

            detailFooter(preview.effectiveTimeNote)
            }
                Spacer(minLength: 8)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OWCDesign.page)
        .navigationTitle(shifts.text.t("salarySettings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .owcDetailBack(title: shifts.text.t("settings"), pageTitle: shifts.text.t("salarySettings"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(shifts.text.t("done")) {
                    commitSalaryFields()
                    focusedField = nil
                }
            }
        }
        .onAppear {
            amountDraft.receive(shifts.preferences.salaryAmount)
            bonusDraft.receive(shifts.preferences.annualBonusMonths)
        }
        .onChange(of: shifts.preferences.salaryAmount) { _, amount in amountDraft.receive(amount) }
        .onChange(of: shifts.preferences.annualBonusMonths) { _, months in bonusDraft.receive(months) }
        .onChange(of: focusedField) { old, _ in
            if old != nil { commitSalaryFields() }
        }
        .onDisappear { commitSalaryFields() }
        .sensoryFeedback(.selection, trigger: shifts.preferences.salaryType)
        .sensoryFeedback(.selection, trigger: shifts.preferences.salaryEnabled)
        .sensoryFeedback(.selection, trigger: shifts.preferences.annualBonusEnabled)
        .sensoryFeedback(.selection, trigger: shifts.preferences.hideEarnings)
    }

    private func salaryPreview(
        from snapshot: NativeShiftSnapshot?
    ) -> (
        dailySalary: Double?,
        earnedNow: Double?,
        hourlySalary: Double?,
        effectiveTimeNote: String
    ) {
        let dailySalary = snapshot?.dailySalary
        let earnedNow: Double? = if let snapshot, let dailySalary {
            dailySalary * snapshot.payRatio
        } else {
            nil
        }
        let hourlySalary: Double? = if let snapshot,
                                       let dailySalary,
                                       snapshot.plannedDurationMs > 0 {
            dailySalary / (snapshot.plannedDurationMs / 3_600_000)
        } else {
            nil
        }
        let effectiveTimeNote = snapshot.map {
            "\(shifts.text.formatDuration($0.plannedDurationMs, includeSeconds: false)) · \(shifts.text.t("lunchPauseNoteNoSalary"))"
        } ?? shifts.text.t("lunchPauseNoteNoSalary")
        return (dailySalary, earnedNow, hourlySalary, effectiveTimeNote)
    }

    private func commitSalaryFields() {
        let amount = amountDraft.hasChanges
            ? amountDraft.value.trimmingCharacters(in: .whitespaces) : nil
        let months = bonusDraft.hasChanges ? max(0, bonusDraft.value) : nil
        guard amount != nil || months != nil else { return }
        let amountGeneration = amount.map { _ in amountDraft.editGeneration }
        let bonusGeneration = months.map { _ in bonusDraft.editGeneration }
        let command = shifts.preferences.applyPreferences {
            if let amount { $0.salaryAmount = amount }
            if let months { $0.annualBonusMonths = months }
        }
        if command.immediateResult == true {
            acceptSalaryFields(amountGeneration: amountGeneration, bonusGeneration: bonusGeneration)
        } else if command.immediateResult == nil {
            Task {
                guard await command.value else { return }
                acceptSalaryFields(amountGeneration: amountGeneration, bonusGeneration: bonusGeneration)
            }
        }
    }

    private func acceptSalaryFields(amountGeneration: UInt64?, bonusGeneration: UInt64?) {
        if let amountGeneration {
            amountDraft.accept(shifts.preferences.salaryAmount, ifUnchangedSince: amountGeneration)
        }
        if let bonusGeneration {
            bonusDraft.accept(shifts.preferences.annualBonusMonths, ifUnchangedSince: bonusGeneration)
        }
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
    @Environment(SceneState.self) private var scene
    @Bindable var shifts: ShiftSessionStore
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
        .navigationTitle(shifts.text.t("shiftReminders"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .owcDetailBack(title: shifts.text.t("settings"), pageTitle: shifts.text.t("shiftReminders"))
        .task { await notifications.refresh() }
        .sensoryFeedback(.selection, trigger: shifts.preferences.notificationMode)
        .sensoryFeedback(.selection, trigger: shifts.preferences.liveActivityEnabled)
        .sensoryFeedback(.selection, trigger: shifts.preferences.liveActivityLeadMinutes)
        .sensoryFeedback(.selection, trigger: shifts.preferences.cycleEndSummaryNotificationEnabled)
        .sensoryFeedback(.selection, trigger: shifts.preferences.lunchStartReminderEnabled)
        .sensoryFeedback(.selection, trigger: shifts.preferences.lunchEndReminderEnabled)
        .onChange(of: shifts.preferences.cycleEndSummaryNotificationEnabled) { _, enabled in
            guard enabled, notifications.status == .notDetermined else { return }
            Task { @MainActor in
                let granted = await notifications.request()
                if granted {
                    await notifications.reschedule(shifts: shifts)
                } else {
                    shifts.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = false }
                }
            }
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            OWCGroupCard {
                modeRow(.off, title: shifts.text.t("notificationModeOff"))
                modeRow(.simple, title: shifts.text.t("notificationModeSimple"))
                modeRow(.milestones, title: shifts.text.t("notificationModeMilestones"), isLast: true)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 26)

            // Moved here from the lunch page: these decide whether something
            // is announced, not what shape the shift is.
            if shifts.preferences.lunchEnabled {
                lunchReminderSection
            }

            liveActivitySection

            cycleEndSummarySection

            detailFooter(shifts.text.t("cycleEndSummaryNotificationNote"))
            detailFooter(shifts.text.t("liveActivityScheduleNote"))

            detailFooter(shifts.text.t("notificationPrivacyNote"))
            Spacer(minLength: 8)
        }
    }

    private var lunchReminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: shifts.text.t("lunchBreak"))
            OWCGroupCard {
                HStack {
                    Text(shifts.text.t("lunchStartReminder")).font(.body)
                    Spacer()
                    Toggle(shifts.text.t("lunchStartReminder"), isOn: shifts.preferences.preferenceBinding(\.lunchStartReminderEnabled)).labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .owcDivider()

                HStack {
                    Text(shifts.text.t("lunchEndReminder")).font(.body)
                    Spacer()
                    Toggle(shifts.text.t("lunchEndReminder"), isOn: shifts.preferences.preferenceBinding(\.lunchEndReminderEnabled)).labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 16)
    }

    private var cycleEndSummarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: shifts.text.t("cycleEndSummaryNotificationTitle"))
            OWCGroupCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shifts.text.t("cycleEndSummaryNotificationTitle"))
                            .font(.body)
                        if !shifts.plus.isAuthorized {
                            Text(shifts.text.t("plusStatusSubscribed"))
                                .font(.caption2.bold())
                                .foregroundStyle(OWCDesign.accent)
                        }
                    }
                    Spacer()
                    Toggle(
                        shifts.text.t("cycleEndSummaryNotificationTitle"),
                        isOn: Binding(
                            get: { shifts.cycleEndSummaryNotificationsAreActive },
                            set: { enabled in
                                scene.setCycleEndSummaryNotifications(
                                    enabled,
                                    preferences: shifts.preferences,
                                    plus: shifts.plus
                                )
                            }
                        )
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 58)
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 16)
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
            OWCSectionHeader(title: shifts.text.t("liveActivity"))
            OWCGroupCard {
                HStack {
                    Text(shifts.text.t("lockScreenLiveActivity"))
                        .font(.body)
                    Spacer()
                    Toggle(shifts.text.t("lockScreenLiveActivity"), isOn: Binding(get: { shifts.preferences.liveActivityEnabled }, set: { shifts.preferences.liveActivityEnabled = $0 }))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .owcPlainDivider()

                Picker(shifts.text.t("liveActivityStartTime"), selection: Binding(get: { shifts.preferences.liveActivityLeadMinutes }, set: { shifts.preferences.liveActivityLeadMinutes = $0 })) {
                    ForEach(PreferencesStore.allowedLiveActivityLeadMinutes, id: \.self) { minutes in
                        Text(shifts.text.t("liveActivityLead", values: ["count": "\(minutes)"]))
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
                        Text(shifts.text.t("notificationDeniedTitle"))
                            .font(.body.weight(.semibold))
                        Text(shifts.text.t("notificationDeniedBody"))
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }

                Button(shifts.text.t("notificationOpenSettings")) {
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
                OWCSectionHeader(title: shifts.text.t("notificationCapability"))
                OWCGroupCard {
                    OWCRow(title: shifts.text.t("notificationLocal")) {
                        Text(shifts.text.t("notificationDeniedStatus"))
                            .font(.body)
                            .foregroundStyle(OWCDesign.orangeDeep)
                    }
                    OWCRow(title: shifts.text.t("liveActivity")) {
                        Text(shifts.text.t(activitiesEnabled
                                     ? "notificationAllowedStatus"
                                     : "notificationDeniedStatus"))
                            .font(.body)
                            .foregroundStyle(activitiesEnabled ? OWCDesign.secondary : OWCDesign.orangeDeep)
                    }
                    OWCRow(title: shifts.text.t("notificationScheduledForShift"), isLast: true) {
                        Text("0 / 0")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 24)

            detailFooter(shifts.text.t("notificationCapabilityNote"))

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: shifts.text.t("notificationStillWorks"))
                OWCGroupCard {
                    OWCRow(icon: "rectangle.inset.filled", title: shifts.text.t("lockScreenLiveActivity")) {
                        Image(systemName: activitiesEnabled ? "checkmark" : "xmark")
                            .font(.headline)
                            .foregroundStyle(activitiesEnabled ? OWCDesign.orange : OWCDesign.secondary)
                    }
                    OWCRow(icon: "square.grid.2x2", title: shifts.text.t("notificationHomeWidget"), isLast: true) {
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
            let command = shifts.preferences.applyPreferences { $0.notificationMode = mode }
            if mode != .off, notifications.status == .notDetermined {
                Task { @MainActor in
                    guard await command.value else { return }
                    let granted = await notifications.request()
                    if granted {
                        await notifications.reschedule(shifts: shifts)
                    } else {
                        _ = await shifts.preferences.applyPreferences {
                            $0.notificationMode = .off
                        }.value
                    }
                }
            }
        } label: {
            OWCRow(title: title, isLast: isLast) {
                if shifts.preferences.notificationMode == mode {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(OWCDesign.orange)
                        .transition(notificationModeTransition)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .animation(notificationModeAnimation, value: shifts.preferences.notificationMode)
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

struct HealthReminderSettingsView: View {
    @Bindable var shifts: ShiftSessionStore
    @FocusState private var intervalFocused: Bool
    @State private var intervalDraft = SettingsFieldDraft("")

    /// The pomodoro's breaks stand in for the fixed interval on a shift that
    /// has a plan, so the two do not fire on separate clocks.
    private var takenOverByFocus: Bool { shifts.preferences.microBreakEnabled && shifts.focus.focusOwnsBreaks() }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack {
                        Text(shifts.text.t("microBreakReminder")).font(.body)
                        Spacer()
                        Toggle(shifts.text.t("microBreakReminder"), isOn: shifts.preferences.preferenceBinding(\.microBreakEnabled)).labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)

                    if shifts.preferences.microBreakEnabled {
                        HStack {
                            Text(shifts.text.t("microBreakInterval")).font(.body)
                            Spacer()
                            if takenOverByFocus {
                                // Not disabled and not switched off: the
                                // reminder still fires, on the plan's rhythm
                                // instead of a fixed interval. Saying so is
                                // more use than greying the field out.
                                Text(shifts.text.t("microBreakFollowsFocus"))
                                    .font(.callout)
                                    .foregroundStyle(OWCDesign.secondary)
                            } else {
                                OWCNumberField(
                                    placeholder: "60",
                                    text: $intervalDraft.value,
                                    width: 72,
                                    onCommit: clampInterval
                                )
                                .focused($intervalFocused)
                                Text(shifts.text.t("minutesUnit"))
                                    .font(.callout)
                                    .foregroundStyle(OWCDesign.secondary)
                            }
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

                if takenOverByFocus {
                    OWCGroupCard {
                        NavigationLink(value: AppRoute.focus) {
                            OWCRow(
                                icon: FocusTaskIcon.focus.systemName,
                                title: shifts.text.t("microBreakOpenFocus"),
                                subtitle: shifts.text.t("microBreakTakenOverNote"),
                                isLast: true
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(OWCDesign.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 16)
                }

                settingsDetailFooter(shifts.text.t("microBreakEffectiveTimeNote"))
            }
        }
        .scrollDismissesKeyboard(.never)
        .background(OWCDesign.page)
        .navigationTitle(shifts.text.t("microBreakReminder"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: shifts.text.t("settings"), pageTitle: shifts.text.t("microBreakReminder"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(shifts.text.t("done")) { intervalFocused = false; clampInterval() }
            }
        }
        .onAppear { intervalDraft.receive("\(shifts.preferences.microBreakIntervalMinutes)") }
        .onChange(of: shifts.preferences.microBreakIntervalMinutes) { _, minutes in
            intervalDraft.receive("\(minutes)")
        }
        .onDisappear { clampInterval() }
        .sensoryFeedback(.selection, trigger: shifts.preferences.microBreakEnabled)
    }

    private func clampInterval() {
        guard intervalDraft.hasChanges else { return }
        let typed = Int(intervalDraft.value) ?? shifts.preferences.microBreakIntervalMinutes
        let clamped = min(120, max(20, typed))
        if shifts.preferences.microBreakIntervalMinutes != clamped {
            let generation = intervalDraft.editGeneration
            let command = shifts.preferences.applyPreferences {
                $0.microBreakIntervalMinutes = clamped
            }
            if command.immediateResult == true {
                intervalDraft.accept(
                    "\(shifts.preferences.microBreakIntervalMinutes)",
                    ifUnchangedSince: generation
                )
            } else if command.immediateResult == nil {
                Task {
                    guard await command.value else { return }
                    intervalDraft.accept(
                        "\(shifts.preferences.microBreakIntervalMinutes)",
                        ifUnchangedSince: generation
                    )
                }
            }
        } else {
            intervalDraft.accept("\(clamped)")
        }
    }
}

struct RecordsTimeZoneSettingsView: View {
    @Bindable var shifts: ShiftSessionStore
    @State private var confirmsMigrate = false

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    OWCRow(
                        title: shifts.text.t("recordsTimeZone"),
                        isLast: !shifts.preferences.systemTimeZoneDiffersFromRecords
                    ) {
                        Text(shifts.preferences.recordsTimeZoneLabel)
                            .font(.body)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    if shifts.preferences.systemTimeZoneDiffersFromRecords {
                        OWCRow(title: shifts.text.t("recordsTimeZoneThisDevice"), isLast: true) {
                            Text(shifts.preferences.systemTimeZoneLabel)
                                .font(.body)
                                .foregroundStyle(OWCDesign.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)

                if shifts.preferences.systemTimeZoneDiffersFromRecords {
                    Button(shifts.text.t("recordsTimeZoneMigrate")) {
                        confirmsMigrate = true
                    }
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)
                }

                settingsDetailFooter(shifts.text.t("recordsTimeZoneFooter"))
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(shifts.text.t("recordsTimeZone"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: shifts.text.t("settings"), pageTitle: shifts.text.t("recordsTimeZone"))
        .confirmationDialog(
            shifts.text.t("recordsTimeZoneMigrateConfirm"),
            isPresented: $confirmsMigrate,
            titleVisibility: .visible
        ) {
            Button(shifts.text.t("recordsTimeZoneMigrate")) {
                shifts.migrateRecordsTimeZone()
            }
            Button(shifts.text.t("cancel"), role: .cancel) {}
        } message: {
            Text(shifts.text.t("recordsTimeZoneDevice", values: ["zone": shifts.preferences.systemTimeZoneLabel]))
        }
        .onAppear { shifts.preferences.refreshSystemTimeZone() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            shifts.preferences.refreshSystemTimeZone()
        }
    }
}

struct ThemeSettingsView: View {
    @Bindable var preferences: PreferencesStore
    let text: AppText

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                themeRow(.auto, title: text.t("auto"), icon: "circle.lefthalf.filled")
                themeRow(.light, title: text.t("light"), icon: "sun.max")
                themeRow(.dark, title: text.t("dark"), icon: "moon", isLast: true)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 22)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("theme"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("theme"))
        .sensoryFeedback(.selection, trigger: preferences.theme)
    }

    private func themeRow(
        _ theme: AppTheme,
        title: String,
        icon: String?,
        textIcon: String? = nil,
        isLast: Bool = false
    ) -> some View {
        Button { preferences.applyPreferences { $0.theme = theme } } label: {
            OWCRow(icon: icon, textIcon: textIcon, title: title, isLast: isLast) {
                if preferences.theme == theme {
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
    @Bindable var preferences: PreferencesStore
    let text: AppText

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                languageRow(nil, title: text.t("auto"))
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

            settingsDetailFooter(text.t("languageFooter"))
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("chooselanguage"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("chooselanguage"))
        .sensoryFeedback(.selection, trigger: preferences.languageOverride)
    }

    private func languageRow(_ code: String?, title: String, isLast: Bool = false) -> some View {
        Button { preferences.applyPreferences { $0.languageOverride = code } } label: {
            OWCRow(icon: nil, title: title, isLast: isLast) {
                if preferences.languageOverride == code {
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

/// Trailing header control on a page that is saved rather than committed
/// field by field.
///
/// Matches the native back chevron without drawing a second glass surface.
/// `ToolbarItem` supplies its own Liquid Glass chrome on iOS 26, so the label
/// must remain a plain symbol. The old capsule label (`Enregistrer`,
/// `Сохранить`, `जतन करा`) could crowd the compact header; the checkmark keeps
/// the system hit target and the VoiceOver name.
struct ScheduleSaveButton: View {
    let text: AppText
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
        }
        .tint(enabled ? OWCDesign.accent : nil)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(text.t("saveAction"))
    }
}

private extension View {
    func owcDivider() -> some View {
        overlay(alignment: .bottomTrailing) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }
}
