import SwiftUI

/// Presentation-only modes. The persisted schedule retains its existing enum;
/// automatic modes are represented by the same shared cycle/roster model.
private enum ScheduleEditorMode: CaseIterable, Hashable {
    case weekly, alternating, rotation, free, manual

    var titleKey: String {
        switch self {
        case .weekly: "scheduleClassic"
        case .alternating: "scheduleAlternating"
        case .rotation: "scheduleRotation"
        case .free: "scheduleFreeCalendar"
        case .manual: "scheduleManualTimer"
        }
    }
    var preset: ShiftCycleRule.Preset? {
        switch self {
        case .weekly: .weekly
        case .alternating: .alternatingWeeks
        case .rotation: .rotation
        case .free, .manual: nil
        }
    }
}

struct ScheduleCalendarEditor: View {
    let shifts: ShiftSessionStore
    let content: ExtendedScheduleContent
    let handSetDays: [String: UUID]
    let isManual: Bool
    let rosterEdits: [String: RosterDayEdit]?
    let onContentChange: (ExtendedScheduleContent) -> Void
    let onManualChange: (Bool) -> Void
    let onSetDay: (String, RosterDayEdit) -> Void
    let onRemovePattern: () -> Void
    let onClearExpected: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace
    @State private var selectionFeedback = 0
    @State private var assignmentFeedback = 0
    @State private var monthOffset = 0
    @State private var selectedKey: String?
    @State private var selectedWeek = 0
    @State private var paint = ScheduleCalendarPaintSelection()
    @State private var dayFrames: [String: CGRect] = [:]
    @State private var strokePoint: CGPoint?
    @GestureState private var strokeIsActive = false
    @State private var showsTypes = false
    @State private var confirmsClearExpected = false
    @State private var showsHolidayRegions = false
    @State private var pendingMode: ScheduleEditorMode?
    @State private var patternDrafts: [ScheduleEditorMode: ShiftCycleRule] = [:]
    @State private var editingType: ShiftTypeEditing?
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 46

    private var session: ShiftSession { shifts.session }
    private var text: AppText { shifts.text }
    private var today: String { session.extendedTodayKey(at: .now) }
    private var selected: String { selectedKey ?? today }
    private var isPainting: Bool { mode == .free && paint.brushID != nil }
    private var types: [ShiftType] { ExtendedScheduleEditing.activeTypes(in: content) }
    private var schedulePlan: ExtendedSchedulePlan {
        ExtendedSchedulePlan(
            shiftTypes: content.shiftTypes, rule: content.rule, handSetDays: handSetDays,
            holidayRegionIdentifier: content.holidayRegionIdentifier,
            clearedFromDayKey: content.clearedFromDayKey,
            frozenShiftTypes: shifts.records.frozenRosterShiftTypes.filter { rosterEdits?[$0.key] == nil }
        )
    }
    private var resolver: ExtendedScheduleResolver {
        LaunchTrace.interval("scheduleEditorResolver") { ExtendedScheduleResolver(plan: schedulePlan) }
    }
    private var mode: ScheduleEditorMode {
        if isManual { return .manual }
        guard let rule = content.rule else { return .free }
        switch rule.preset {
        case .weekly: return .weekly
        case .alternatingWeeks: return .alternating
        case .rotation, .custom: return .rotation
        }
    }

    var body: some View {
        // One plan per evaluation: building it parses every hand-set day.
        let resolved = resolver
        VStack(alignment: .leading, spacing: 18) {
            if let month = ExtendedScheduleEditing.month(of: today, plus: monthOffset) {
                calendar(month, resolver: resolved)
            }
            VStack(spacing: 0) {
                modePicker
                controls
                Divider().padding(.horizontal, 16)
                holidayCalendarPicker
            }
            .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
            selectedDay(resolver: resolved)
        }
        .fixedSize(horizontal: false, vertical: true)
        .tint(OWCDesign.accent)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.selection, trigger: assignmentFeedback)
        .confirmationDialog(text.t("scheduleClearExpected"), isPresented: $confirmsClearExpected, titleVisibility: .visible) {
            Button(text.t("scheduleClearExpected"), role: .destructive) {
                onClearExpected()
                assignmentFeedback += 1
            }
            Button(text.t("cancelAction"), role: .cancel) {}
        } message: {
            Text(text.t("scheduleClearExpectedMessage"))
        }
        .onChange(of: mode) { paint.choose(nil); strokePoint = nil }
        .onChange(of: strokeIsActive) {
            if !strokeIsActive {
                paint.endStroke()
                strokePoint = nil
            }
        }
        .onChange(of: types.map(\.id)) {
            if let brushID = paint.brushID, !types.contains(where: { $0.id == brushID }) {
                paint.choose(nil)
                strokePoint = nil
            }
        }
        .onAppear {
#if DEBUG
            // Navigate screenshot demos without changing the clock or saved roster.
            if let key = UserDefaults.standard.string(forKey: "ios.native.qaScheduleDate"),
               let date = RecordJSON.date(fromDayKey: key, calendar: shifts.preferences.recordsCalendar) {
                let calendar = shifts.preferences.recordsCalendar
                let target = calendar.dateComponents([.year, .month], from: date)
                let current = calendar.dateComponents([.year, .month], from: .now)
                if let year = target.year, let month = target.month,
                   let currentYear = current.year, let currentMonth = current.month {
                    monthOffset = (year - currentYear) * 12 + month - currentMonth
                    selectedKey = key
                }
            }
#endif
        }
        .sheet(isPresented: $showsTypes) {
            NavigationStack {
                ScrollView {
                    ExtendedShiftTypesSection(
                        session: session, types: types,
                        dateCoverage: ShiftTypeScheduleOverview.coverage(plan: schedulePlan, fromDayKey: today),
                        onEdit: { editType($0) }, onAdd: addType
                    )
                    .padding(.bottom, OWCDesign.pageInset)
                }
                .background(OWCDesign.page)
                .navigationTitle(text.t("extendedShiftTypes"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(text.t("done")) { showsTypes = false }
                    }
                }
                .sheet(item: $editingType, content: typeEditor)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsHolidayRegions) {
            HolidayRegionPicker(
                text: text,
                locale: shifts.preferences.locale,
                selection: content.holidayRegionIdentifier,
                onSelect: selectHolidayRegion
            )
        }
        .confirmationDialog(
            text.t(pendingMode == .free ? "extendedRemovePatternTitle" : "extendedApplyTemplateTitle"),
            isPresented: Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingMode {
                Button(text.t(pendingMode.titleKey)) { applyMode(pendingMode) }
            }
            Button(text.t("cancelAction"), role: .cancel) { pendingMode = nil }
        } message: {
            Text(pendingMode == .free ? text.t("extendedRemovePatternMessage") : text.t("extendedApplyTemplateMessage", values: ["pattern": text.t(pendingMode?.titleKey ?? mode.titleKey)]))
        }
    }

    private var holidayCalendarPicker: some View {
        Button { showsHolidayRegions = true } label: {
            HStack(spacing: 12) {
                LabeledContent {
                    Text(holidayRegionLabel).foregroundStyle(OWCDesign.secondary)
                } label: {
                    Text(text.t("holidayCalendar")).foregroundStyle(OWCDesign.primary)
                }
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(OWCDesign.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(OWCRowButtonStyle())
        // Clipping only affects drawing; the styled row also needs an explicit
        // interaction boundary before the next section's ellipsis button.
        .contentShape(.interaction, Rectangle())
        .clipShape(.rect(cornerRadius: OWCDesign.cardRadius))
        .accessibilityLabel(text.t("holidayCalendar") + ", " + holidayRegionLabel)
    }

    private var holidayRegionLabel: String {
        // Never set means off. The device's region used to be shown here as a
        // suggestion, which read as though it were already applied; the
        // picker still offers it first, marked as suggested.
        guard let identifier = content.holidayRegionIdentifier, !identifier.isEmpty else {
            return text.t("holidayCalendarOff")
        }
        return HolidayCalendar.shared.regionName(identifier, locale: shifts.preferences.locale)
    }

    private func selectHolidayRegion(_ identifier: String) {
        if identifier != content.holidayRegionIdentifier {
            var next = content
            next.holidayRegionIdentifier = identifier
            onContentChange(next)
            assignmentFeedback += 1
        }
        showsHolidayRegions = false
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            LabeledContent {
                Text(text.t(mode.titleKey)).foregroundStyle(OWCDesign.primary)
            } label: {
                Text(text.t("extendedPattern")).foregroundStyle(OWCDesign.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold)).foregroundStyle(OWCDesign.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 48)
        .owcRowMenu(accessibilityLabel: text.t("extendedPattern") + ", " + text.t(mode.titleKey)) {
            Picker(text.t("workSchedule"), selection: Binding(
                get: { mode }, set: { next in
                    guard next != mode else { return }
                    if next == .manual || mode == .manual { applyMode(next) }
                    else { pendingMode = next }
                }
            )) {
                ForEach(ScheduleEditorMode.allCases, id: \.self) { option in
                    Text(text.t(option.titleKey)).tag(option)
                }
            }
        }
    }

    private var weekdayLabels: [String] {
        guard dynamicTypeSize.isAccessibilitySize else { return text.weekdayLabels() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = shifts.preferences.locale
        let names = calendar.veryShortStandaloneWeekdaySymbols
        return Array(names.dropFirst()) + [names[0]]
    }

    private func calendar(_ month: (year: Int, month: Int), resolver resolved: ExtendedScheduleResolver) -> some View {
        let first = CivilZone.dayNumber(year: month.year, month: month.month, day: 1)
        let weekday = ((first + 4) % 7 + 7) % 7
        let leading = (weekday - (shifts.queries.recordsGridCalendar.firstWeekday - 1) + 7) % 7
        let count = ExtendedScheduleEditing.daysIn(year: month.year, month: month.month)
        let slots = ((leading + count + 6) / 7) * 7
        let today = self.today
        let previews = pastPreviews(first: first, count: count, today: today)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                Button { returnToToday() } label: {
                    Text(text.formatCivilDate(year: month.year, month: month.month, template: "yMMMM"))
                        .font(.title3.weight(.semibold)).foregroundStyle(OWCDesign.primary)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : OWCMotion.stateEnter, value: monthOffset)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(text.t("extendedToday"))
                Spacer(minLength: 8)
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(text.t("extendedPreviousMonth"))
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.forward").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(text.t("extendedNextMonth"))
            }
            .padding(.horizontal, 8)
            .buttonStyle(ScheduleCalendarPressStyle())
            VStack(spacing: 5) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                    ForEach(Array(shifts.queries.recordsWeekdayGridSymbols().enumerated()), id: \.offset) { _, label in
                        Text(label).font(.caption.weight(.medium)).foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1).accessibilityHidden(true)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                    ForEach(0..<slots, id: \.self) { slot in
                        if slot < leading || slot >= leading + count {
                            Color.clear.frame(height: cellHeight).accessibilityHidden(true)
                        } else {
                            dayCell(number: first + slot - leading, day: slot - leading + 1, resolver: resolved,
                                    today: today, previews: previews)
                        }
                    }
                }
                .coordinateSpace(.named("schedule-paint"))
                .onPreferenceChange(SchedulePaintDayFramesKey.self) { dayFrames = $0 }
                .highPriorityGesture(paintGesture, including: isPainting ? .all : .subviews)
            }
            if let warning = holidayCoverageWarning(for: month) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(8)
        .padding(.bottom, 8)
        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
    }

    private func dayCell(
        number: Int, day: Int, resolver: ExtendedScheduleResolver,
        today: String, previews: [String: PlannedRosterPreview]
    ) -> some View {
        let key = ExtendedScheduleEditing.dayKey(dayNumber: number)
        let result = resolver.day(dayNumber: number)
        let type = typeForDay(key, id: result.shiftTypeID, today: today, preview: previews[key])
        let chosen = isPainting ? handSetDays[key] == paint.brushID : key == (selectedKey ?? today)
        let isToday = key == today
        let holiday = holidayDay(key)
        let leave = leavePortion(key)
        return Button {
            if isPainting {
                paint.endStroke()
                paintDay(key)
                paint.endStroke()
            } else { selectDay(key) }
        } label: {
            VStack(spacing: 2) {
                Text(text.formatCount(day))
                    .font(.callout.monospacedDigit().weight(chosen || isToday ? .semibold : .regular))
                    .foregroundStyle(chosen || isToday ? OWCDesign.accent : OWCDesign.primary)
                HStack(spacing: 2) {
                    // Adopted leave sits over the plan this page edits, so the
                    // day keeps its shift and gains a mark, not a new colour.
                    if let leave {
                        Image(systemName: Self.leaveSymbol(leave))
                            .imageScale(.small)
                            .foregroundStyle(OWCDesign.accent)
                    }
                    if let annotation = HolidayDayAnnotation.make(dayKey: key,
                        region: content.holidayRegionIdentifier, language: shifts.preferences.languageCode) {
                        HolidayDayCaption(annotation: annotation, text: text)
                    } else {
                        Text(type.map { shortName($0) } ?? "–").lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .background(dayFill(type), in: .rect(cornerRadius: 8))
            .overlay {
                if chosen {
                    if reduceMotion || isPainting {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(OWCDesign.accent, lineWidth: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(OWCDesign.accent, lineWidth: 2)
                            .matchedGeometryEffect(id: "selectedDate", in: selectionSpace)
                    }
                }
            }
            .padding(3)
            .contentShape(Rectangle())
        }
        // Match Records: the hit area extends into the gutter, and selection
        // outlines the day without covering its work/rest colour.
        .padding(-3)
        .buttonStyle(ScheduleCalendarPressStyle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SchedulePaintDayFramesKey.self, value: [key: proxy.frame(in: .named("schedule-paint"))])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([dayLabel(key: key, type: type, isToday: isToday, holiday: holiday), leave.map(leaveLabel)]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private func dayFill(_ type: ShiftType?) -> Color {
        switch type?.kind {
        case .work:
            // This screen edits plans. Keep their colour uniform rather than
            // implying recorded hours or overtime through intensity.
            OWCDesign.recordsWork.opacity(RecordsWorkIntensity.opacity(overtimeMs: 0, estimated: true))
        case .rest: OWCDesign.control.opacity(0.36)
        case nil: .clear
        }
    }

    @ViewBuilder private var controls: some View {
        if isManual {
            Text(text.t("scheduleOffManualStart"))
                .font(.footnote).foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
        } else if let rule = content.rule {
            VStack(spacing: 6) {
                if mode == .alternating {
                    Picker(text.t("alternatingCurrentWeek"), selection: $selectedWeek) {
                        ForEach(0..<2) { week in
                            Text(text.t("extendedWeekNumber", values: ["week": text.formatCount(week + 1)])).tag(week)
                        }
                    }.pickerStyle(.segmented)
                } else if mode == .rotation {
                    HStack {
                        Stepper(value: Binding(
                            get: { rule.days.count },
                            set: { onContentChange(ExtendedScheduleEditing.resizing(content, to: $0, restName: text.t("extendedDefaultRest"))) }
                        ), in: 1...max(ExtendedScheduleEditing.maximumCycleLength, rule.days.count)) {
                            Text(text.t("extendedCycleLength") + ": " + text.formatCount(rule.days.count))
                                .font(.subheadline)
                        }
                    }.frame(minHeight: 44)
                    HStack {
                        Text(text.t("extendedTodayIs")).foregroundStyle(OWCDesign.secondary)
                        Spacer(minLength: 8)
                        Picker(text.t("extendedTodayIs"), selection: Binding(
                            get: { ExtendedScheduleEditing.cycleDay(of: rule, todayKey: today) ?? 1 },
                            set: { onContentChange(ExtendedScheduleEditing.anchoring(content, todayKey: today, atCycleDay: $0)) }
                        )) {
                            ForEach(1...max(1, rule.days.count), id: \.self) { day in
                                Text(text.t("extendedCycleDay", values: ["day": text.formatCount(day)])).tag(day)
                            }
                        }.pickerStyle(.menu).labelsHidden()
                    }
                    .font(.subheadline).frame(minHeight: 44)
                }
                cycleGrid(rule)
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        } else {
            Button(role: .destructive) { confirmsClearExpected = true } label: {
                Label(text.t("scheduleClearExpected"), systemImage: "calendar.badge.minus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 16).padding(.bottom, 4)
        }
    }

    private func cycleGrid(_ rule: ShiftCycleRule) -> some View {
        let start = mode == .alternating ? selectedWeek * 7 : 0
        let end = mode == .alternating ? min(start + 7, rule.days.count) : rule.days.count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(start..<max(start, end), id: \.self) { index in
                let type = content.shiftTypes.first { $0.id == rule.days[index] }
                VStack(spacing: 3) {
                    Text(mode == .rotation ? text.formatCount(index + 1) : weekdayLabels[index % 7])
                        .font(.subheadline.weight(type?.kind == .work ? .semibold : .regular))
                    if mode == .rotation {
                        Text(type.map { shortName($0) } ?? "–").font(.caption2)
                    }
                }
                .foregroundStyle(type?.kind == .work ? OWCDesign.accent : OWCDesign.secondary)
                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                .background(type?.kind == .work ? OWCDesign.accent.opacity(0.10) : OWCDesign.control.opacity(0.5),
                            in: .rect(cornerRadius: OWCDesign.controlRadius))
                .owcRowMenu(
                    accessibilityLabel: (mode == .rotation ? text.formatCount(index + 1) : weekdayLabels[index % 7])
                        + ", " + (type?.name ?? text.t("extendedUnassigned")),
                    cornerRadius: OWCDesign.controlRadius
                ) {
                    ForEach(types) { option in
                        Button(option.name) {
                            onContentChange(ExtendedScheduleEditing.assigning(option.id, at: index, in: content))
                            assignmentFeedback += 1
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func selectedDay(resolver: ExtendedScheduleResolver) -> some View {
        let result = ExtendedScheduleResolver.dayNumber(dayKey: selected).map { resolver.day(dayNumber: $0) }
        let type = typeForDay(selected, id: result?.shiftTypeID, today: today)
        let canEdit = canEditDay(selected)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLabel(key: selected, type: nil, isToday: false, holiday: nil))
                        .font(.subheadline.weight(.semibold))
                    if let holiday = holidayDay(selected) {
                        Text(holiday.name(language: shifts.preferences.languageCode) + " · "
                             + text.t(holiday.isWorkday ? "holidayMakeupWorkday" : "holidayRestDay")
                             + (isEstimatedHoliday(selected) ? " · " + text.t("holidayEstimatedLabel") : ""))
                            .font(.caption).foregroundStyle(OWCDesign.secondary)
                    }
                    Text(text.t(sourceKey(result?.source)))
                        .font(.caption).foregroundStyle(OWCDesign.secondary)
                    if let leave = leavePortion(selected) {
                        Label(leaveLabel(leave), systemImage: Self.leaveSymbol(leave))
                            .font(.caption).foregroundStyle(OWCDesign.accent)
                    }
                }
                .contentTransition(.opacity)
                Spacer(minLength: 0)
                Button { showsTypes = true } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary).frame(width: 44, height: 44)
                }
                .buttonStyle(ScheduleCalendarPressStyle())
                .accessibilityLabel(text.t("extendedShiftTypes"))
            }
            .padding(.leading, 4)
            if mode == .free {
                Text(text.t(paint.brushID == nil ? "schedulePaintStartHint" : "schedulePaintHint"))
                    .font(.footnote).foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 4)
            }
            if !canEdit {
                Text(text.t("extendedHistoryNeedsCareer"))
                    .font(.footnote).foregroundStyle(OWCDesign.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(types.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { Divider().padding(.leading, 38) }
                    let chosen = mode == .free ? paint.brushID == option.id : type?.id == option.id
                    Button {
                        if mode == .free {
                            paint.choose(option.id)
                            strokePoint = nil
                            selectionFeedback += 1
                        } else { assign(option.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(option.displayColor).frame(width: 8, height: 8)
                            Text(option.name).foregroundStyle(OWCDesign.primary)
                            Spacer(minLength: 8)
                            if option.kind == .work {
                                Text(session.hoursLabel(for: option))
                                    .font(.caption).foregroundStyle(OWCDesign.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(OWCDesign.accent)
                                .opacity(chosen ? 1 : 0)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OWCRowButtonStyle())
                    .accessibilityAddTraits(chosen ? [.isSelected] : [])
                }
            }
            .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
            .clipShape(.rect(cornerRadius: OWCDesign.cardRadius))
            .disabled(mode != .free && !canEdit)
            if handSetDays[selected] != nil {
                Button { followPattern() } label: {
                    Label(text.t(content.rule == nil ? "extendedClearDay" : "extendedFollowPattern"), systemImage: "arrow.uturn.backward")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain).disabled(!canEdit)
                .padding(.horizontal, 4)
            }
            if leavePortion(selected) != nil {
                NavigationLink(value: AppRoute.leave) {
                    Label(text.t("leaveManage"), systemImage: "suitcase")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OWCDesign.accent)
                .padding(.horizontal, 4)
            }
        }
    }

    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("schedule-paint"))
            .updating($strokeIsActive) { _, active, _ in active = true }
            .onChanged { value in
                guard isPainting else { return }
                // Only begin a stroke on a date, never on a weekday heading.
                guard strokePoint != nil || dayFrames.values.contains(where: { $0.contains(value.startLocation) }) else { return }
                let start = strokePoint ?? value.startLocation
                for key in ScheduleCalendarPaintSelection.crossedDays(from: start, to: value.location, frames: dayFrames) {
                    paintDay(key)
                }
                strokePoint = value.location
            }
            .onEnded { _ in
                paint.endStroke()
                strokePoint = nil
            }
    }

    private func canEditDay(_ key: String) -> Bool {
        key >= today || shifts.records.canEditRosterDay(key, timeZoneIdentifier: previewTimeZoneIdentifier)
    }

    private func paintDay(_ key: String) {
        guard canEditDay(key) else { selectDay(key); return }
        guard let edit = paint.edit(dayKey: key, currentShiftID: handSetDays[key]) else { return }
        onSetDay(key, edit)
        selectedKey = key
        assignmentFeedback += 1
    }

    private func selectDay(_ key: String) {
        guard key != selected else { return }
        withAnimation(reduceMotion ? nil : OWCMotion.selection) { selectedKey = key }
        selectionFeedback += 1
    }

    private func assign(_ id: UUID) {
        guard handSetDays[selected] != id else { return }
        withAnimation(reduceMotion ? nil : OWCMotion.selection) { onSetDay(selected, .shift(id)) }
        assignmentFeedback += 1
    }

    private func followPattern() {
        withAnimation(reduceMotion ? nil : OWCMotion.selection) { onSetDay(selected, .followPattern) }
        assignmentFeedback += 1
    }

    /// Past days show the plan recorded for them. A month asks for all of its
    /// past days together, so days under one snapshot share its roster plan.
    private func pastPreviews(first: Int, count: Int, today: String) -> [String: PlannedRosterPreview] {
        let keys = (0..<count).map { ExtendedScheduleEditing.dayKey(dayNumber: first + $0) }.filter { key in
            guard key < today else { return false }
            if case .shift = rosterEdits?[key] { return false }
            return true
        }
        guard !keys.isEmpty else { return [:] }
        return shifts.records.plannedRosterPreviews(
            dayKeys: keys,
            timeZoneIdentifier: previewTimeZoneIdentifier,
            fallbackTypes: content.shiftTypes,
            ignoringRosterAssignment: { rosterEdits?[$0] == .followPattern }
        )
    }

    private var previewTimeZoneIdentifier: String {
        session.rulesTimeZoneIdentifier ?? shifts.preferences.recordsTimeZone.identifier
    }

    private func typeForDay(_ key: String, id: UUID?, today: String, preview: PlannedRosterPreview? = nil) -> ShiftType? {
        if case .shift(let assigned) = rosterEdits?[key] {
            return content.shiftTypes.first { $0.id == assigned }
        }
        if key < today {
            switch preview ?? shifts.records.plannedRosterPreview(
                dayKey: key,
                timeZoneIdentifier: previewTimeZoneIdentifier,
                fallbackTypes: content.shiftTypes,
                ignoringRosterAssignment: rosterEdits?[key] == .followPattern
            ) {
            case .shift(let type): return type
            case .rest: return content.shiftTypes.first { $0.kind == .rest }
            case .noPlan: return nil
            }
        }
        if rosterEdits?[key] == nil, let frozen = shifts.records.frozenRosterShiftTypes[key] { return frozen }
        return id.flatMap { id in content.shiftTypes.first { $0.id == id } }
    }

    private func sourceKey(_ source: ExtendedScheduleDay.Source?) -> String {
        switch source {
        case .handSet: "extendedSetByHand"
        case .holiday: "holidaySource"
        case .rule: "extendedPattern"
        case .annualRange: "extendedSourceAnnualRange"
        case .carriedOver: "extendedCarriedOver"
        // The editor's plans never carry leave; it edits the plan beneath it.
        case .leave, .leaveOverBase: "extendedSetByHand"
        case .unassigned, nil: "extendedUnassigned"
        }
    }

    /// Leave adopted from a plan (plan 020) on `key`, which the live schedule
    /// lays over the plan edited here.
    private func leavePortion(_ key: String) -> LeavePortion? {
        shifts.records.state.leaveDays.first { $0.dayKey == key }?.portion
    }

    private func leaveLabel(_ portion: LeavePortion) -> String {
        text.t("leaveDayLeave") + " · " + text.t(portion.titleKey)
    }

    static func leaveSymbol(_ portion: LeavePortion) -> String {
        portion == .whole ? "suitcase.fill" : "circle.lefthalf.filled"
    }

    private func shortName(_ type: ShiftType) -> String {
        // Keep the cue legible, with the full name and hours directly below.
        dynamicTypeSize.isAccessibilitySize ? String(type.name.prefix(1)) : type.name
    }
    private func dayLabel(key: String, type: ShiftType?, isToday: Bool, holiday: HolidayCalendar.Day? = nil) -> String {
        guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { return key }
        return [text.formatCivilDate(year: parts.year, month: parts.month, day: parts.day, template: "MMMMdEEEE"),
                type?.name,
                holiday.map { $0.name(language: shifts.preferences.languageCode) },
                holiday.map { text.t($0.isWorkday ? "holidayMakeupWorkday" : "holidayRestDay") },
                holiday != nil && isEstimatedHoliday(key) ? text.t("holidayEstimatedLabel") : nil,
                isToday ? text.t("extendedToday") : nil].compactMap { $0 }.joined(separator: ", ")
    }

    private func holidayDay(_ key: String) -> HolidayCalendar.Day? {
        guard let region = content.holidayRegionIdentifier, !region.isEmpty else { return nil }
        return HolidayCalendar.shared.day(dayKey: key, regionIdentifier: region)
    }

    private func isEstimatedHoliday(_ key: String) -> Bool {
        guard let region = content.holidayRegionIdentifier,
              let parts = ExtendedScheduleResolver.parse(dayKey: key) else { return false }
        return HolidayCalendar.shared.isEstimated(year: parts.year, regionIdentifier: region)
    }

    private func holidayCoverageWarning(for month: (year: Int, month: Int)) -> String? {
        guard let region = content.holidayRegionIdentifier, !region.isEmpty else { return nil }
        if !HolidayCalendar.shared.covers(year: month.year, regionIdentifier: region) {
            return text.t("holidayCoverageYearWarning", values: ["year": text.formatYear(month.year)])
        }
        if HolidayCalendar.shared.isEstimated(year: month.year, regionIdentifier: region) {
            return text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(month.year)])
        }
        if month.month == 12, HolidayCalendar.shared.isEstimated(year: month.year + 1, regionIdentifier: region) {
            return text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(month.year + 1)])
        }
        if month.month == 12, !HolidayCalendar.shared.covers(year: month.year + 1, regionIdentifier: region) {
            return text.t("holidayCoverageNextYearWarning", values: ["year": text.formatYear(month.year + 1)])
        }
        return nil
    }
    private func changeMonth(_ delta: Int) {
        // Keep the month grid stable; only the heading fades between months.
        paint.endStroke()
        strokePoint = nil
        monthOffset += delta
        if let month = ExtendedScheduleEditing.month(of: today, plus: monthOffset) {
            selectedKey = ExtendedScheduleEditing.dayKey(dayNumber: CivilZone.dayNumber(year: month.year, month: month.month, day: 1))
        }
        selectionFeedback += 1
    }
    private func returnToToday() {
        guard monthOffset != 0 || selected != today else { return }
        paint.endStroke()
        strokePoint = nil
        monthOffset = 0
        selectedKey = today
        selectionFeedback += 1
    }

    private func applyMode(_ next: ScheduleEditorMode) {
        if let rule = content.rule, !isManual { patternDrafts[mode] = rule }
        pendingMode = nil
        selectedWeek = 0
        if next == .manual { onManualChange(true); return }
        onManualChange(false)
        if next == .free { onRemovePattern() }
        else if let preset = next.preset {
            if let savedRule = patternDrafts[next] {
                var restored = content
                restored.rule = savedRule
                onContentChange(restored)
            } else {
                onContentChange(session.applyingTemplate(preset, to: content, at: .now))
            }
        }
    }
    private func editType(_ type: ShiftType) {
        editingType = ShiftTypeEditing(type: type, isNew: false, isInUse: ExtendedScheduleEditing.ruleUses(type.id, in: content)
            || (shifts.preferences.extendedScheduleContent?.shiftTypes.contains { $0.id == type.id } != true
                && handSetDays.values.contains(type.id)),
            dateCoverage: ShiftTypeScheduleOverview.coverage(plan: schedulePlan, fromDayKey: today)[type.id],
            otherTypes: types)
    }
    private func addType() {
        editingType = ShiftTypeEditing(type: ShiftType(
            id: UUID(), name: "", kind: .work,
            startMinutes: shifts.preferences.startMinutes, endMinutes: shifts.preferences.endMinutes,
            breakEnabled: false, breakStartMinutes: 720, breakDurationMinutes: 30,
            colorHex: ExtendedScheduleEditing.nextColor(after: content.shiftTypes), isArchived: false
        ), isNew: true, isInUse: false, otherTypes: types)
    }
    private func typeEditor(_ editing: ShiftTypeEditing) -> some View {
        ShiftTypeEditorSheet(session: session, editing: editing,
            onSave: { onContentChange(ExtendedScheduleEditing.upserting($0, in: content)) },
            onDelete: { onContentChange(ExtendedScheduleEditing.removing(editing.type.id, from: content, saved: shifts.preferences.extendedScheduleContent)) }
        )
    }
}

private struct SchedulePaintDayFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ScheduleCalendarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(OWCMotion.press) { content in
                content.opacity(configuration.isPressed ? 0.6 : 1)
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            }
    }
}

struct HolidayRegionPicker: View {
    let text: AppText
    let locale: Locale
    let selection: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var regions: [String] {
        HolidayCalendar.shared.regionIdentifiers
            .sorted {
                HolidayCalendar.shared.regionName($0, locale: locale)
                    .localizedStandardCompare(HolidayCalendar.shared.regionName($1, locale: locale)) == .orderedAscending
            }
            .filter { identifier in
                query.isEmpty
                    || HolidayCalendar.shared.regionName(identifier, locale: locale)
                        .localizedStandardContains(query)
                    || identifier.localizedStandardContains(query)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Button { onSelect("") } label: {
                            regionRow(text.t("holidayCalendarOff"), selected: selection?.isEmpty != false)
                        }
                        if let featuredRegion {
                            Button { onSelect(featuredRegion) } label: {
                                let name = HolidayCalendar.shared.regionName(featuredRegion, locale: locale)
                                regionRow(
                                    selection == featuredRegion ? name : text.t("holidayCalendarSystemDefault", values: ["region": name]),
                                    selected: selection == featuredRegion
                                )
                            }
                        }
                    }
                }
                Section {
                    ForEach(regions.filter { !query.isEmpty || $0 != featuredRegion }, id: \.self) { identifier in
                        Button { onSelect(identifier) } label: {
                            regionRow(
                                HolidayCalendar.shared.regionName(identifier, locale: locale),
                                selected: selection == identifier
                            )
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: text.t("holidayCalendarSearch"))
            .navigationTitle(text.t("holidayCalendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction")) { dismiss() }
                }
            }
        }
    }

    private var featuredRegion: String? {
        if let selection, !selection.isEmpty { return selection }
        return HolidayCalendar.shared.defaultRegionIdentifier()
    }

    private func regionRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(OWCDesign.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
            }
        }
        .contentShape(Rectangle())
    }
}

struct HolidayCoverageNoticeView: View {
    let regionIdentifier: String?
    let dates: [Date]
    let timeZone: TimeZone
    let text: AppText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notices, id: \.self) { notice in
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notices: [String] {
        guard let regionIdentifier, !regionIdentifier.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = dates.map { calendar.dateComponents([.year, .month], from: $0) }
        let years = Set(components.compactMap(\.year)).sorted()
        let estimateYears = Set(years + components.filter { $0.month == 12 }.compactMap { $0.year.map { $0 + 1 } })
        var notices = estimateYears.sorted().filter {
            HolidayCalendar.shared.isEstimated(year: $0, regionIdentifier: regionIdentifier)
        }.map { text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear($0)]) }
        if let uncovered = years.first(where: {
            !HolidayCalendar.shared.covers(year: $0, regionIdentifier: regionIdentifier)
        }) {
            notices.append(text.t("holidayCoverageYearWarning", values: ["year": text.formatYear(uncovered)]))
        }
        if let december = components.first(where: { $0.month == 12 })?.year,
           !HolidayCalendar.shared.covers(year: december + 1, regionIdentifier: regionIdentifier) {
            notices.append(text.t("holidayCoverageNextYearWarning", values: ["year": text.formatYear(december + 1)]))
        }
        return notices
    }
}
