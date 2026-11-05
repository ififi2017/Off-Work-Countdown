import SwiftUI
import UIKit

struct OvertimeSheet: View {
    let shifts: ShiftSessionStore
    @Environment(\.dismiss) private var dismiss
    /// How the overtime is chosen and what follows from it (plan 024 phase 4).
    @State private var plan = OvertimeSheetPlan(plannedEnd: .now, now: .now, untilDate: .now)
    @State private var confirmed = false
    @State private var saving = false
    /// Fixed when the sheet opens, so the title cannot flip while it is up
    /// (for example when the planned clock-off passes mid-edit).
    @State private var mode = OvertimeSheetMode.add
    /// Plan 024: how this overtime is paid. The wheel's choice, not yet saved.
    @State private var isPaid = true
    @State private var multiplier = 1.0
    @State private var showsCustomMultiplier = false

    private var text: AppText { shifts.text }

    var body: some View {
        NavigationStack {
            // The wheel picker alone is most of a sheet's height, so on iPad's
            // fixed `.form` size the four stacked elements overran it and the
            // confirm button fell past the bottom edge. Scroll the reading
            // material and keep the button pinned, so the primary action is
            // visible the moment the sheet opens no matter how tall the
            // description and info label render in a given locale.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(text.t("overtimeDescription"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                        Picker(text.t("overtimeEndTime"), selection: entryBinding) {
                            Text(text.t("overtimeModeEnd")).tag(OvertimeSheetPlan.Entry.until)
                            Text(text.t("overtimeModeDuration")).tag(OvertimeSheetPlan.Entry.duration)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        endChooser
                        restCard
                        Label(periodSummary, systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OWCDesign.primary)
                            .opacity(plan.countedMs > 0 ? 1 : 0)
                        OvertimePayCard(
                            text: text, isPaid: $isPaid, multiplier: $multiplier, showsCustom: $showsCustomMultiplier
                        )
                        Label(payFootnote, systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                Button(text.t(mode.confirmKey)) {
                    plan.now = timerNow
                    plan.settle()
                    let command = shifts.applyOvertime(
                        date: plan.endDate,
                        payMultiplier: isPaid ? multiplier : 0,
                        startDate: plan.overtimeStart
                    )
                    saving = true
                    Task {
                        defer { saving = false }
                        guard await command.value else { return }
                        confirmed.toggle()
                        dismiss()
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                .disabled(!plan.isValid)
                .padding(20)
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .navigationTitle(text.t(mode.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(text.t("close"))
                }
            }
            .onAppear {
                let now = timerNow
                let snapshot = shifts.session.snapshot(at: now)
                // Read the existing end from the snapshot, not the stored
                // session field: it is what the timer is showing, including
                // a DEBUG scenario's overtime on its virtual clock.
                let existing = snapshot?.overtimeEndDate
                mode = OvertimeSheetMode(
                    hasOvertime: existing != nil,
                    plannedEnd: snapshot?.plannedEndDate,
                    now: now
                )
                let plannedEnd = snapshot?.plannedEndDate ?? now
                var next = OvertimeSheetPlan(plannedEnd: plannedEnd, now: now, untilDate: now)
                // Overtime that began after a rest is its own last segment.
                if existing != nil, let last = snapshot?.segments.last, last.startAtMs > (snapshot?.plannedEndAtMs ?? .infinity) {
                    let restMs = last.startAtMs - (snapshot?.plannedEndAtMs ?? last.startAtMs)
                    next.restMinutes = OvertimeRestChoices.nearest(to: restMs / 60_000)
                }
                // After clock-off this becomes a retrospective record and
                // defaults to now, so someone who actually stayed late can
                // save the time already worked without adding another forced
                // 15-minute block.
                next.untilDate = max(next.minimumEnd, existing ?? now)
                next.settle()
                plan = next
                let current = shifts.session.effectiveOvertimePayMultiplier
                let preferred = shifts.preferences.overtimePayMultiplier
                isPaid = current > 0
                multiplier = current > 0 ? current : (preferred > 0 ? preferred : 1)
                showsCustomMultiplier = isPaid && !OvertimePayChoices.isPreset(multiplier)
            }
            .onChange(of: plan.restMinutes) {
                plan.now = timerNow
                plan.settle()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: confirmed)
        }
    }

    private var entryBinding: Binding<OvertimeSheetPlan.Entry> {
        Binding(get: { plan.entry }, set: { entry in
            plan.now = timerNow
            plan.select(entry)
        })
    }

    /// The end as a clock time, or as how long the overtime lasts.
    @ViewBuilder
    private var endChooser: some View {
        switch plan.entry {
        case .until:
            DatePicker(
                text.t("overtimeEndTime"),
                selection: $plan.untilDate,
                in: plan.minimumEnd...,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        case .duration:
            Picker(text.t("overtimeDurationLabel"), selection: $plan.durationMinutes) {
                ForEach(plan.durationChoices, id: \.self) { minutes in
                    Text(text.formatRelativeDuration(Double(minutes) * 60_000)).tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    /// A rest before the overtime starts, for dinner say; it is a break, not
    /// overtime, so it is left out of what the overtime counts.
    private var restCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            OWCGroupCard {
                OWCRow(title: text.t("overtimeRestRow"), isLast: true) {
                    HStack(spacing: 6) {
                        Text(restLabel(plan.restMinutes))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                }
                .owcRowMenu(accessibilityLabel: "\(text.t("overtimeRestRow")), \(restLabel(plan.restMinutes))") {
                    Picker(text.t("overtimeRestRow"), selection: $plan.restMinutes) {
                        ForEach(OvertimeRestChoices.minutes, id: \.self) { minutes in
                            Text(restLabel(minutes)).tag(minutes)
                        }
                    }
                }
            }
            Text(text.t("overtimeRestFootnote"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func restLabel(_ minutes: Int) -> String {
        minutes == 0 ? text.t("overtimeRestNone") : text.formatRelativeDuration(Double(minutes) * 60_000)
    }

    /// "Overtime 18:30-21:00, 2 h 30 m counted".
    private var periodSummary: String {
        text.t("overtimePeriodSummary", values: [
            "start": text.formatTime(plan.startDate),
            "end": text.formatTime(plan.endDate),
            "duration": text.formatRelativeDuration(plan.countedMs),
        ])
    }

    private var payFootnote: String {
        if !isPaid { return text.t("overtimeUnpaidSheetNote") }
        if multiplier == 1 { return text.t("overtimeNoMultiplier") }
        return text.t("overtimeMultiplierNote", values: ["multiplier": text.formatDecimal(multiplier)])
    }

    /// The timer's clock: the device time, or a DEBUG scenario's virtual time.
    private var timerNow: Date { shifts.session.timerDate(from: .now) }
}

/// What the overtime sheet is doing, which decides its title and button.
/// The timer's entry button already says "Adjust overtime" once overtime is
/// set; the sheet it opens must not then say "Add overtime".
nonisolated enum OvertimeSheetMode: Equatable, Sendable {
    /// No overtime yet and the shift is still running.
    case add
    /// Overtime is already set; this moves its end.
    case adjust
    /// No overtime yet but the planned clock-off has passed: recording time
    /// already worked, so "Start overtime" would be wrong.
    case log

    init(hasOvertime: Bool, plannedEnd: Date?, now: Date) {
        if hasOvertime {
            self = .adjust
        } else if let plannedEnd, now >= plannedEnd {
            self = .log
        } else {
            self = .add
        }
    }

    var titleKey: String {
        switch self {
        case .add: "overtimeTitle"
        case .adjust: "adjustOvertime"
        case .log: "logOvertimeTitle"
        }
    }

    var confirmKey: String {
        self == .add ? "confirmOvertime" : "saveAction"
    }
}

struct ShareComposerView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width >= 840 {
                    let previewWidth = min(360, proxy.size.height * 0.72)
                    HStack(spacing: 32) {
                        sharePreview(maxWidth: previewWidth)
                            .frame(width: previewWidth)
                        wideShareControls
                            .frame(maxWidth: 390, maxHeight: previewWidth * 1.25)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                } else if proxy.size.width >= 520, proxy.size.height >= 340 {
                    let horizontalPadding: CGFloat = 20
                    let columnSpacing: CGFloat = 20
                    let contentWidth = proxy.size.width - horizontalPadding * 2 - columnSpacing
                    let previewWidth = min(
                        300,
                        contentWidth * 0.48,
                        (proxy.size.height - 28) * 0.8
                    )
                    let controlsWidth = contentWidth - previewWidth

                    HStack(spacing: columnSpacing) {
                        sharePreview(maxWidth: previewWidth)
                            .frame(width: previewWidth)
                        wideShareControls
                            .frame(width: controlsWidth)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 14)
                } else {
                    // No scroll view and no arithmetic: the mood row and the
                    // button take their natural height, and the card is handed
                    // whatever is between them. `aspectRatio(.fit)` then picks
                    // the smaller of that height and the available width, so the
                    // card can never end up behind the button — which is exactly
                    // what deriving its size from a height fraction kept doing.
                    VStack(spacing: 14) {
                        moodPicker
                        sharePreview(maxWidth: proxy.size.width - OWCDesign.pageInset * 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        shareButton
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
            .background(OWCDesign.page)
            .navigationTitle(shifts.text.t("shareButton"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(shifts.text.t("close"))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: scene.shareMood)
    }


    private var moodPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(ShareMood.allCases) { mood in
                    moodButton(mood)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 4
            ) {
                ForEach(ShareMood.allCases) { mood in
                    moodButton(mood)
                }
            }
        }
    }

    /// On a wide sheet the preview and controls read as two deliberate columns.
    /// `ViewThatFits` keeps that arrangement useful on a short landscape iPhone
    /// without making the iPad version sparse again.
    private var wideShareControls: some View {
        ViewThatFits(in: .vertical) {
            expandedShareControls
            compactShareControls
        }
    }

    private var expandedShareControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(shifts.text.t("shareMoodLabel"))
                .font(.title3.weight(.semibold))
            moodPicker
            shareDetailsCard
            shareButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactShareControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shifts.text.t("shareMoodLabel"))
                .font(.subheadline.weight(.semibold))
            moodPicker
            Text(shareCopy)
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            shareButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            shareDetailRow("text.quote", text: shareCopy, emphasized: true)
            Divider()
            shareDetailRow("square.and.arrow.up", text: shifts.text.t("shareComposerNote"))
            shareDetailRow("lock", text: shifts.text.t("sharePrivacyNote"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shareDetailRow(_ icon: String, text: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(emphasized ? OWCDesign.accent : OWCDesign.secondary)
                .frame(width: 18)
            Text(text)
                .font(.subheadline.weight(emphasized ? .medium : .regular))
                .foregroundStyle(emphasized ? OWCDesign.primary : OWCDesign.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sharePreview(maxWidth: CGFloat) -> some View {
        let safeWidth = (maxWidth.isFinite && maxWidth > 0) ? maxWidth : nil
        return ShareCard(shifts: shifts, mood: scene.shareMood)
            .frame(maxWidth: safeWidth)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }

    @ViewBuilder
    private func moodButton(_ mood: ShareMood) -> some View {
        let selected = scene.shareMood == mood
        Button {
            withAnimation(.snappy(duration: 0.2)) { scene.shareMood = mood }
        } label: {
            Text(verbatim: mood.emoji)
                .font(.title)
                .frame(width: 34, height: 34)
                .background(selected ? OWCDesign.control : Color.clear)
                .clipShape(Circle())
                .overlay { moodRing(selected) }
                .opacity(selected ? 1 : 0.74)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shifts.text.t(mood.labelKey))
    }

    @ViewBuilder
    private func moodRing(_ selected: Bool) -> some View {
        if selected {
            Circle().stroke(OWCDesign.accent, lineWidth: 1.5)
        }
    }

    private var shareButton: some View {
        Button { Task { await prepareShare() } } label: {
            Label(shifts.text.t("shareNative"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(OWCPrimaryButtonStyle())
    }

    @MainActor
    private func prepareShare() async {
        await Task.yield()
        let card = ShareCard(shifts: shifts, mood: scene.shareMood)
            .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        // Two items, no overlap: the picture, and one string carrying both the
        // message and the link. Previously the item source also returned that
        // string, so targets took one or the other and the image was dropped.
        let metadata = ShareMetadataItemSource(
            title: OWCBrand.shortName,
            text: "\(shareCopy) \(shifts.session.shareURL().absoluteString)",
            icon: UIImage(named: "BrandIcon") ?? image
        )
        SystemShare.present(items: [image, metadata])
    }

    private var shareCopy: String {
        shifts.session.shareCopy()
    }
}

/// The shareable image, drawn by `ImageRenderer`.
///
/// Every size in here is deliberately fixed rather than a Dynamic Type style:
/// this view is rasterised into a PNG that leaves the device, so its layout has
/// to be identical for everyone. Do not "migrate" these to semantic fonts.
///
/// Everything it draws is passed in. `ImageRenderer` renders a view with no
/// hierarchy above it, so an `@Environment` lookup here finds nothing and traps
/// — which is what crashed the share button. `ShareCardRenderTests` renders it
/// the same way the button does.
struct ShareCard: View {
    let shifts: ShiftSessionStore
    let mood: ShareMood

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OWCDesign.orange, Color(red: 0.91, green: 0.18, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(.brandIcon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    // Mixed-case on purpose: DoneAt is the mark, not a
                    // small-caps label. Uppercasing it reads as DONEAT.
                    Text(verbatim: OWCBrand.shortName)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                }
                Spacer()
                Text(verbatim: mood.emoji)
                    .font(.system(size: 72))
                    .frame(width: 82, height: 82)
                    .accessibilityHidden(true)
                Text(heroText)
                    .font(.system(size: 38, weight: .heavy).monospacedDigit())
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 12)
                Text(messageText)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .padding(.top, 10)
                Spacer()

                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * min(1, max(0, shifts.session.shareProgress() / 100)))
                        }
                }
                .frame(height: 5)

                HStack {
                    Text(shifts.text.formatPercent(shifts.session.shareProgress()))
                    Spacer()
                    Text(verbatim: "DoneAt.app")
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .tracking(0.35)
                .opacity(0.85)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(22)
        }
    }

    private var heroText: String { shifts.session.shareHeroText() }
    private var messageText: String { shifts.session.shareCopy() }
}
