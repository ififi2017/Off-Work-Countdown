import SwiftUI
import WidgetKit

/// Settings › Widgets (plan 023 W6): every widget DoneAt offers, drawn with
/// the user's own data at its real size, marked free or Plus, with how to add
/// it. iOS has no API for an app to place a widget itself, so adding stays a
/// short set of steps.
struct WidgetGallerySettingsView: View {
    let shifts: ShiftSessionStore

    @State private var data: WidgetGalleryData?
    @State private var expandedHowTo: Set<WidgetGalleryHowTo> = []

    private var text: AppText { shifts.text }
    private var isPlus: Bool { shifts.plus.isAuthorized }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 22) {
                intro
                if let data {
                    section(text.t("widgetGallerySectionCountdown"), howTo: .homeAndLock) {
                        item(name: text.t("widgetGalleryClassicName"), plus: false, families: Self.classicFamilies) { family in
                            OffWorkCountdownWidgetView(entry: data.countdown.base, familyOverride: family)
                        }
                        item(name: text.t("widgetStyleBigName"), plus: false, families: [.systemSmall]) { _ in
                            CountdownBigDigitsView(model: CountdownStyleModel(entry: data.countdown))
                        }
                        item(name: text.t("widgetStyleRingName"), plus: false, families: [.systemSmall, .accessoryCircular]) { family in
                            CountdownRingView(familyOverride: family, model: CountdownStyleModel(entry: data.countdown))
                        }
                        item(name: text.t("widgetStyleTimelineName"), plus: false, families: [.systemSmall]) { _ in
                            CountdownTimelineView(model: CountdownStyleModel(entry: data.countdown))
                        }
                        item(name: text.t("widgetStyleDetailName"), plus: false, families: [.systemMedium, .systemLarge], isLast: true) { family in
                            CountdownDetailView(familyOverride: family, model: CountdownStyleModel(entry: data.countdown))
                        }
                    }
                    section(text.t("widgetGallerySectionWeek"), howTo: .homeAndLock) {
                        item(name: text.t("widgetSuiteWeekName"), plus: false,
                             families: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]) { family in
                            WeekProgressView(familyOverride: family, entry: CalendarWidgetEntry(date: data.now, payload: data.calendar))
                        }
                        item(name: text.t("widgetSuiteRosterName"), plus: false,
                             families: [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]) { family in
                            RosterView(familyOverride: family, entry: CalendarWidgetEntry(date: data.now, payload: data.calendar))
                        }
                        item(name: text.t("widgetSuiteWeekendName"), plus: false,
                             families: [.systemSmall, .accessoryRectangular]) { family in
                            WeekendWidgetView(familyOverride: family, entry: HolidayWidgetEntry(date: data.now, payload: data.holiday, calendar: data.calendar))
                        }
                        item(name: text.t("widgetSuiteHolidayName"), plus: false, partlyPlus: true,
                             families: [.systemSmall, .systemMedium, .accessoryRectangular], isLast: true) { family in
                            HolidayWidgetView(familyOverride: family, entry: HolidayWidgetEntry(date: data.now, payload: data.holiday, calendar: data.calendar))
                        }
                    }
                    section(text.t("widgetGallerySectionRecords"), howTo: .homeAndLock) {
                        item(name: text.t("widgetSuiteSummaryName"), plus: true,
                             families: [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]) { family in
                            SummaryWidgetView(familyOverride: family, entry: SummaryWidgetEntry(date: data.now, payload: data.summary))
                        }
                        item(name: text.t("widgetSuiteLifeName"), plus: true,
                             families: [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]) { family in
                            LifeWidgetView(familyOverride: family, entry: LifeWidgetEntry(date: data.now, payload: data.life))
                        }
                        item(name: text.t("widgetSuiteYearName"), plus: false, families: [.systemSmall, .accessoryCircular], isLast: true) { family in
                            YearProgressView(familyOverride: family, entry: LifeWidgetEntry(date: data.now, payload: data.life))
                        }
                    }
                    section(text.t("widgetGallerySectionFocus"), howTo: .homeAndControl) {
                        item(name: text.t("widgetSuiteFocusName"), plus: true, families: [.systemMedium, .systemSmall]) { family in
                            FocusWidgetView(familyOverride: family, entry: FocusWidgetEntry(date: data.now, payload: data.focus))
                        }
                        controlsRow
                    }
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        watchSection
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .frame(maxWidth: 720)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("widgetGalleryTitle"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("widgetGalleryTitle"))
        .task { await load() }
    }

    private static var classicFamilies: [WidgetFamily] {
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular]
    }

    private func load() async {
        data = await WidgetGalleryData.load(shifts: shifts)
    }

    // MARK: Layout

    private var intro: some View {
        OWCGroupCard {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.largeTitle)
                    .foregroundStyle(OWCDesign.accent)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(text.t("widgetGalleryIntro"))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !isPlus {
                    Text(text.t("widgetGalleryPlusNote"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }

    private func section<Content: View>(_ title: String, howTo: WidgetGalleryHowTo, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: title)
            OWCGroupCard {
                content()
                howToRow(howTo)
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }

    private func item<Preview: View>(
        name: String, plus: Bool, partlyPlus: Bool = false, families: [WidgetFamily], isLast: Bool = false,
        @ViewBuilder preview: @escaping (WidgetFamily) -> Preview
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(name).font(.headline).foregroundStyle(OWCDesign.primary)
                Spacer(minLength: 8)
                if plus && !isPlus {
                    badge(text.t("widgetGallerySample"), tint: OWCDesign.secondary)
                }
                badge(plus ? "Plus" : (partlyPlus ? text.t("widgetGalleryFreeAndPlus") : text.t("widgetGalleryFree")),
                      tint: plus ? OWCDesign.accent : OWCDesign.secondary)
            }
            WidgetGalleryPreviewStage(families: families, sizeName: sizeName) { family in preview(family) }
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }

    private var controlsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.t("widgetGalleryControlsTitle")).font(.headline).foregroundStyle(OWCDesign.primary)
                Spacer()
                badge(text.t("widgetGalleryFree"), tint: OWCDesign.secondary)
            }
            HStack(spacing: 18) {
                control("play.fill", text.t("widgetSuiteControlClockIn"))
                control("clock.fill", text.t("widgetSuiteControlCountdown"))
                control("timer", text.t("widgetSuiteControlFocus"))
            }
            Text(text.t("widgetGalleryControlsNote"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }

    private func control(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(OWCDesign.accent, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(OWCDesign.primary).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: 90)
    }

    private var watchSection: some View {
        section("Apple Watch", howTo: .watch) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(text.t("widgetGalleryWatchTitle")).font(.headline).foregroundStyle(OWCDesign.primary)
                    Spacer()
                    badge(text.t("widgetGalleryFree"), tint: OWCDesign.secondary)
                }
                ForEach([
                    ("timer", text.t("widgetGalleryWatchCountdown")),
                    ("calendar", text.t("widgetSuiteWeekName")),
                    ("person.badge.clock", text.t("widgetSuiteRosterName")),
                    ("sun.max", text.t("widgetSuiteWeekendName")),
                    ("square.stack", text.t("comingUp")),
                ], id: \.1) { symbol, title in
                    Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(OWCDesign.primary)
                }
                Text(text.t("widgetGalleryWatchNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
            }
        }
    }

    private func howToRow(_ howTo: WidgetGalleryHowTo) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedHowTo.contains(howTo) },
            set: { if $0 { expandedHowTo.insert(howTo) } else { expandedHowTo.remove(howTo) } }
        )) {
            VStack(alignment: .leading, spacing: 12) {
                switch howTo {
                case .homeAndLock:
                    step(text.t("widgetGalleryStepsHome"))
                    step(text.t("widgetGalleryStepsLock"))
                case .homeAndControl:
                    step(text.t("widgetGalleryStepsHome"))
                    step(text.t("widgetGalleryStepsControl"))
                case .watch:
                    step(text.t("widgetGalleryStepsWatch"))
                }
            }
            .padding(.top, 8)
        } label: {
            Label(text.t("widgetGalleryHowToAdd"), systemImage: "plus.square.on.square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OWCDesign.accent)
        }
        .tint(OWCDesign.secondary)
        .padding(16)
    }

    private func step(_ instruction: String) -> some View {
        Text(instruction)
            .font(.subheadline)
            .foregroundStyle(OWCDesign.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(tint)
    }

    private func sizeName(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: text.t("widgetGallerySizeSmall")
        case .systemMedium: text.t("widgetGallerySizeMedium")
        case .systemLarge: text.t("widgetGallerySizeLarge")
        case .systemExtraLarge: text.t("widgetGallerySizeExtraLarge")
        case .accessoryCircular: text.t("widgetGallerySizeCircular")
        default: text.t("widgetGallerySizeRectangular")
        }
    }
}

enum WidgetGalleryHowTo: Hashable {
    case homeAndLock
    case homeAndControl
    case watch
}

struct WidgetGalleryData {
    let now: Date
    let countdown: CountdownStyleEntry
    let calendar: WidgetCalendarPayload
    let holiday: WidgetHolidayPayload
    let summary: WidgetSummaryPayload
    let life: WidgetLifePayload
    let focus: WidgetFocusPayload

    /// The user's own data in every widget's payload; Plus widgets fall back
    /// to labelled sample figures until Plus.
    @MainActor
    static func load(shifts: ShiftSessionStore) async -> WidgetGalleryData {
        let now = Date.now
        let locale = shifts.preferences.languageCode
        let composer = WidgetSuiteComposer.shared
        let access = WidgetSuiteComposer.access(for: shifts.plus)
        let calendar = composer.calendarPayload(shifts: shifts, now: now, locale: locale)
        let snapshot = await WidgetSnapshotComposer.shared.prepare(shifts: shifts, now: now)
            ?? WidgetSnapshotComposer.shared.publishedSnapshot(shifts: shifts, now: now)
        let logical = snapshot.logicalNowMs(fromRealMs: WidgetSuiteTime.ms(now))
        let countdown = CountdownStyleEntry(
            base: OffWorkCountdownWidgetEntry(date: now, snapshotEntry: snapshot.entry(atMs: logical), locale: snapshot.locale,
                                              upcoming: snapshot.upcoming, clockOffsetMs: snapshot.clockOffsetMs),
            segments: snapshot.shift?.segments ?? []
        )
        var holiday = composer.holidayPayload(shifts: shifts, calendar: calendar, access: access, now: now, locale: locale)
        var summary = await composer.summaryPayload(shifts: shifts, calendar: calendar, access: access, now: now, locale: locale)
        var life = composer.lifePayload(shifts: shifts, access: access, now: now, locale: locale)
        var focus = composer.focusPayload(shifts: shifts, access: access, now: now, locale: locale)
        if !shifts.plus.isAuthorized {
            let samples = WidgetGallerySamples(now: now, locale: locale, text: shifts.text)
            summary = samples.summary
            life = samples.life
            focus = samples.focus
            holiday = samples.holiday(base: holiday)
        }
        return WidgetGalleryData(now: now, countdown: countdown, calendar: calendar, holiday: holiday,
                                 summary: summary, life: life, focus: focus)
    }
}

/// One size at a time on a light stage, chosen with a size picker; a row of
/// every size at once took the height of the tallest.
private struct WidgetGalleryPreviewStage<Preview: View>: View {
    let families: [WidgetFamily]
    let sizeName: (WidgetFamily) -> String
    @ViewBuilder let preview: (WidgetFamily) -> Preview
    @State private var selected: WidgetFamily?

    var body: some View {
        let family = selected ?? families.first ?? .systemSmall
        VStack(spacing: 10) {
            if families.count > 1 {
                Picker(selection: Binding(get: { family }, set: { selected = $0 })) {
                    ForEach(families, id: \.self) { Text(sizeName($0)).tag($0) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            ViewThatFits(in: .horizontal) {
                WidgetGalleryFrame(family: family) { preview(family) }
                WidgetGalleryFrame(family: family) { preview(family) }
                    .scaleEffect(0.82)
                    .frame(width: WidgetGalleryFrame<Preview>.size(family).width * 0.82,
                           height: WidgetGalleryFrame<Preview>.size(family).height * 0.82)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(WidgetGalleryColors.stage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.snappy, value: family)
        }
    }
}

/// A widget at its real point size, on the plate WidgetKit would draw.
struct WidgetGalleryFrame<Content: View>: View {
    let family: WidgetFamily
    @ViewBuilder let content: () -> Content

    var body: some View {
        let size = Self.size(family)
        let isAccessory = family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
        let radius: CGFloat = isAccessory ? (family == .accessoryCircular ? size.width / 2 : 14) : 22
        content()
            .padding(isAccessory ? 0 : 16)
            .frame(width: size.width, height: size.height)
            .background(isAccessory ? Color(white: 0.16) : WidgetGalleryColors.widget)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(WidgetGalleryAccessoryScheme(isAccessory: isAccessory))
            .shadow(color: .black.opacity(isAccessory ? 0 : 0.10), radius: 12, y: 4)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isAccessory ? 0 : 0.06), lineWidth: 0.5)
            }
            .padding(isAccessory ? 10 : 0)
            .background {
                if isAccessory {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.12, green: 0.16, blue: 0.22))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .systemExtraLarge: CGSize(width: 715, height: 338)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        default: CGSize(width: 234, height: 26)
        }
    }
}

/// Stage and widget surfaces. In dark mode a black widget would vanish into
/// a black stage, so the stage reads as a dimmed wallpaper and the widget as
/// the system's dark widget plate.
enum WidgetGalleryColors {
    static let stage = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.24, alpha: 1) : .systemGroupedBackground
    })
    static let widget = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : .systemBackground
    })
}

/// Lock Screen accessories always sit on a dark wallpaper; Home Screen
/// widgets follow the system appearance, as they do on the Home Screen.
private struct WidgetGalleryAccessoryScheme: ViewModifier {
    let isAccessory: Bool

    func body(content: Content) -> some View {
        if isAccessory { content.environment(\.colorScheme, .dark) } else { content }
    }
}

/// Plausible figures for Plus widgets before Plus. Labelled "Sample" on the
/// page; never the user's own data.
struct WidgetGallerySamples {
    let now: Date
    let locale: String
    let text: AppText

    private var nowMs: Int64 { WidgetSuiteTime.ms(now) }
    private var unlocked: WidgetAccess { WidgetAccess(plus: true, validUntilMs: nil) }

    var summary: WidgetSummaryPayload {
        let hour: Int64 = 3_600_000
        let weekdays = text.weekdayLabels()
        let week = WidgetSummaryPeriod(
            kind: .week, title: text.t("widgetSuiteThisWeek"), subtitle: nil, startDayKey: "", endDayKey: "",
            workedMs: 316 * hour / 10, overtimeMs: 2 * hour, workdays: 4, plannedWorkdays: 5, remainingWorkdays: 1,
            progress: 0.8,
            bars: [85, 90, 88, 53, 0].enumerated().map { index, tenths in
                .init(label: weekdays[safe: index] ?? "", valueMs: Int64(tenths) * hour / 10, state: index == 3 ? .current : (index < 3 ? .past : .future))
            },
            comparison: text.t("widgetSuiteLastWeekTotal", values: ["hours": text.formatHours(38.5)]), includesToday: false
        )
        let month = WidgetSummaryPeriod(
            kind: .month, title: text.t("widgetSuiteThisMonth"), subtitle: nil, startDayKey: "", endDayKey: "",
            workedMs: 1_185 * hour / 10, overtimeMs: 65 * hour / 10, workdays: 14, plannedWorkdays: 21, remainingWorkdays: 7,
            progress: 0.67, bars: [],
            comparison: text.t("widgetSuiteLastMonthTotal", values: ["hours": text.formatHours(162)]), includesToday: false
        )
        let year = WidgetSummaryPeriod(
            kind: .year, title: text.t("widgetSuiteThisYear"), subtitle: nil, startDayKey: "", endDayKey: "",
            workedMs: 1_590 * hour, overtimeMs: 74 * hour, workdays: 198, plannedWorkdays: 250, remainingWorkdays: 52,
            progress: 0.79,
            bars: [152, 128, 176, 168, 160, 172, 181, 177, 158, 118, 0, 0].enumerated().map { index, hours in
                .init(label: text.formatCount(index + 1), valueMs: Int64(hours) * hour, state: index == 9 ? .current : (index < 9 ? .past : .future))
            },
            comparison: text.t("widgetSuiteLastYearTotal", values: ["hours": text.formatHours(1_820)]), includesToday: false
        )
        return WidgetSummaryPayload(generatedAtMs: nowMs, locale: locale, access: unlocked, periods: [week, month, year],
                                    liveSegments: [], labels: ["hoursUnit": text.formatHours(0).replacingOccurrences(of: "0", with: "").trimmingCharacters(in: .whitespaces)])
    }

    var life: WidgetLifePayload {
        let day = Int(floor(now.timeIntervalSince1970 / 86_400))
        return WidgetLifePayload(generatedAtMs: nowMs, locale: locale, access: unlocked,
                                 bornDay: day - 11_470, bornIsApproximate: false, careerStartDay: day - 3_440,
                                 retirementDay: day + 10_440, lifeYears: 80, hidesExactAges: false, labels: [:])
    }

    var focus: WidgetFocusPayload {
        let minute: Int64 = 60_000
        let start = nowMs - 7 * minute
        return WidgetFocusPayload(generatedAtMs: nowMs, locale: locale, access: unlocked, blocks: [
            .init(title: text.t("widgetGallerySampleTask"), symbol: "doc.text", startMs: start, endMs: start + 25 * minute,
                  round: 2, rounds: 4, isBreak: false),
            .init(title: text.t("focusBreak"), symbol: "cup.and.saucer.fill", startMs: start + 25 * minute,
                  endMs: start + 30 * minute, round: 2, rounds: 4, isBreak: true),
            .init(title: text.t("widgetGallerySampleTask"), symbol: "doc.text", startMs: start + 30 * minute,
                  endMs: start + 55 * minute, round: 3, rounds: 4, isBreak: false),
        ], labels: [:])
    }

    func holiday(base: WidgetHolidayPayload) -> WidgetHolidayPayload {
        var payload = base
        payload.access = unlocked
        let day: Int64 = 86_400_000
        let start = WidgetSuiteTime.ms(Calendar.current.startOfDay(for: now)) + 18 * day
        let kinds: [WidgetHolidayPayload.Leave.DayKind] = [.rest, .rest, .holiday, .holiday, .holiday, .holiday, .holiday, .leave, .leave]
        let calendar = Calendar.current
        payload.nextLeave = .init(
            startDayKey: "", startMs: start, requestedDays: 2, totalDays: kinds.count,
            days: kinds.enumerated().map { index, kind in
                let date = WidgetSuiteTime.date(start + Int64(index) * day)
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                return .init(dayKey: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0), kind: kind)
            }
        )
        payload.leaveRemainingDays = 5
        payload.labels["remaining"] = text.t("widgetSuiteLeaveRemaining", values: ["days": text.formatDays(5)])
        payload.labels["requested"] = text.t("widgetSuiteLeavePlan", values: [
            "leave": text.formatDays(2), "total": text.formatDays(Double(kinds.count)),
        ])
        return payload
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
