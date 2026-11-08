import MapKit
import SwiftUI

// Plan 021 U1 (design stage): Settings → Workplace automation, the
// workplace editor and the review list. These views take plain values and
// callbacks so they can be reviewed in the preview canvas before they are
// connected to `WorkplaceAutomationCoordinator` and location services.

/// What the system currently allows, as the settings page explains it.
enum WorkplaceLocationAccess: Equatable {
    case notRequested
    case whenInUseOnly
    case reducedAccuracy
    case denied
    case always
}

// MARK: - Settings

struct WorkplaceAutomationSettingsContent: View {
    let text: AppText
    let isPlus: Bool
    let access: WorkplaceLocationAccess
    let settings: WorkplaceAutomationSettings
    let workplaces: [SavedWorkplace]
    let pendingCount: Int
    var onToggleMonitoring: (Bool) -> Void = { _ in }
    var onToggleAutoApply: (Bool) -> Void = { _ in }
    var onPromptDelay: (WorkplaceVisitPromptDelay) -> Void = { _ in }
    var onRequestAccess: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}
    var onAddWorkplace: () -> Void = {}
    var onOpenWorkplace: (SavedWorkplace) -> Void = { _ in }

    private var isOn: Bool { settings.isMonitoringEnabled && isPlus }
    private var isFull: Bool { workplaces.count >= WorkplaceAutomation.maximumWorkplaces }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text.t("automationUITitle")).font(.body)
                            if !isPlus {
                                Text(text.t("plusStatusSubscribed"))
                                    .font(.caption2.bold())
                                    .foregroundStyle(OWCDesign.accent)
                            }
                        }
                        Spacer()
                        Toggle(text.t("automationUITitle"), isOn: Binding(get: { isOn }, set: onToggleMonitoring))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                }
                .padding(.top, 14)
                footnote(text.t("automationUIIntro"))

                if isOn {
                    accessCard
                        .padding(.top, OWCDesign.sectionGap)
                    workplacesSection
                    recordingSection
                }
                reviewSection
                shortcutsSection
                footnote(text.t("automationUIPrivacy"))
                    .padding(.top, OWCDesign.sectionGap)
                    .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .padding(.horizontal, OWCDesign.pageInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("automationUITitle"))
        .tint(OWCDesign.accent)
    }

    // MARK: Location access

    @ViewBuilder private var accessCard: some View {
        OWCGroupCard {
            switch access {
            case .notRequested:
                Button(action: onRequestAccess) {
                    OWCRow(icon: "location", title: text.t("automationUIAccessRequest"),
                           subtitle: text.t("automationUIAccessRequestNote"), isLast: true, centersVertically: true) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            case .whenInUseOnly, .reducedAccuracy, .denied:
                Button(action: onOpenSystemSettings) {
                    OWCRow(icon: "location.slash", title: accessTitle, subtitle: accessNote,
                           isLast: true, centersVertically: true) {
                        Text(text.t("shiftAlarmsOpenSettings")).font(.subheadline).foregroundStyle(OWCDesign.accent)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            case .always:
                OWCRow(icon: "location.fill", title: text.t("automationUIAccessReady"),
                       subtitle: text.t("automationUIAccessReadyNote"), isLast: true, centersVertically: true) {
                    EmptyView()
                }
            }
        }
    }

    private var accessTitle: String {
        switch access {
        case .whenInUseOnly: text.t("automationUIAccessWhileUsing")
        case .reducedAccuracy: text.t("automationUIAccessPrecise")
        default: text.t("automationUIAccessOff")
        }
    }

    private var accessNote: String {
        switch access {
        case .whenInUseOnly: text.t("automationUIAccessWhileUsingNote")
        case .reducedAccuracy: text.t("automationUIAccessPreciseNote")
        default: text.t("automationUIAccessOffNote")
        }
    }

    // MARK: Workplaces

    @ViewBuilder private var workplacesSection: some View {
        OWCSectionHeader(title: text.t("automationUIWorkplaces", values: [
            "count": "\(workplaces.count)",
            "max": "\(WorkplaceAutomation.maximumWorkplaces)",
        ]))
        .padding(.top, OWCDesign.sectionGap)
        OWCGroupCard {
            ForEach(workplaces) { workplace in
                Button { onOpenWorkplace(workplace) } label: {
                    OWCRow(icon: "building.2", title: workplace.name, subtitle: workplaceSubtitle(workplace)) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
            Button(action: onAddWorkplace) {
                OWCRow(icon: "plus", title: text.t("automationUIAddWorkplace"),
                       subtitle: isFull ? text.t("automationUIWorkplaceLimit") : nil, isLast: true) {
                    EmptyView()
                }
            }
            .buttonStyle(OWCRowButtonStyle())
            .disabled(isFull)
        }
    }

    private func workplaceSubtitle(_ workplace: SavedWorkplace) -> String {
        let range = text.t("automationUIRadius", values: ["meters": "\(Int(workplace.innerRadius))"])
        return workplace.isEnabled ? range : text.t("automationUIPaused") + " · " + range
    }

    // MARK: Recording

    @ViewBuilder private var recordingSection: some View {
        OWCSectionHeader(title: text.t("automationUIRecordingSection"))
            .padding(.top, OWCDesign.sectionGap)
        OWCGroupCard {
            OWCRow(title: text.t("automationUIAutoApply"), subtitle: text.t("automationUIAutoApplyNote"),
                   centersVertically: true) {
                Toggle(text.t("automationUIAutoApply"),
                       isOn: Binding(get: { settings.appliesDetectedTimesAutomatically }, set: onToggleAutoApply))
                    .labelsHidden()
            }
            OWCRow(title: text.t("automationUIAskAfter"), subtitle: text.t("automationUIAskAfterNote"),
                   isLast: true, centersVertically: true) {
                Picker(text.t("automationUIAskAfter"),
                       selection: Binding(get: { settings.visitPromptDelay }, set: onPromptDelay)) {
                    ForEach(WorkplaceVisitPromptDelay.allCases, id: \.self) { delay in
                        Text(text.formatRelativeDuration(delay.interval * 1_000)).tag(delay)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    // MARK: Review and Shortcuts

    @ViewBuilder private var reviewSection: some View {
        OWCGroupCard {
            NavigationLink(value: AppRoute.workplaceAutomationReview) {
                OWCRow(icon: "checklist", title: text.t("automationUIReviewTitle"), isLast: true) {
                    OWCDetailAccessory(text: pendingCount > 0 ? "\(pendingCount)" : nil)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
        }
        .padding(.top, OWCDesign.sectionGap)
    }

    @ViewBuilder private var shortcutsSection: some View {
        OWCSectionHeader(title: text.t("automationUIShortcutsSection"))
            .padding(.top, OWCDesign.sectionGap)
        OWCGroupCard {
            OWCRow(icon: "square.2.layers.3d", title: text.t("automationUIShortcutsTitle"),
                   subtitle: text.t("automationUIShortcutsNote", values: [
                       "arrive": text.t("automationIntentRecordArrival"),
                       "leave": text.t("automationIntentRecordDeparture"),
                   ]),
                   isLast: true) {
                EmptyView()
            }
        }
    }

    private func footnote(_ string: String) -> some View {
        Text(string)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}

// MARK: - Workplace editor

struct WorkplaceEditorContent: View {
    let text: AppText
    let isNew: Bool
    @Binding var name: String
    @Binding var innerRadius: Double
    @Binding var isEnabled: Bool
    let center: CLLocationCoordinate2D?
    let isLocating: Bool
    var onUseCurrentLocation: () -> Void = {}
    var onSave: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Shown when the editor is presented on its own, as a sheet.
    var onCancel: (() -> Void)? = nil

    static let radiusChoices: [Double] = [150, 200, 300, 400]

    private var outerRadius: Double { innerRadius + WorkplaceAutomation.defaultOuterRadiusMargin }
    private var canSave: Bool { center != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mapCard
                    .padding(.top, 14)
                OWCGroupCard {
                    Button(action: onUseCurrentLocation) {
                        OWCRow(icon: "location", title: text.t("automationUIUseCurrentLocation"),
                               subtitle: text.t("automationUIUseCurrentLocationNote"), isLast: true, centersVertically: true) {
                            if isLocating { ProgressView().controlSize(.small) }
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                    .disabled(isLocating)
                }
                .padding(.top, 12)

                OWCGroupCard {
                    OWCRow(title: text.t("automationUIWorkplaceName")) {
                        TextField(text.t("automationUIWorkplaceNamePlaceholder"), text: $name)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                    }
                    OWCRow(title: text.t("automationUIArrivalRange"),
                           subtitle: text.t("automationUILeaveRange", values: ["meters": "\(Int(outerRadius))"]),
                           isLast: isNew, centersVertically: true) {
                        Picker(text.t("automationUIArrivalRange"), selection: $innerRadius) {
                            ForEach(Self.radiusChoices, id: \.self) { meters in
                                Text(text.t("automationUIRadius", values: ["meters": "\(Int(meters))"])).tag(meters)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    if !isNew {
                        OWCRow(title: text.t("automationUIWorkplaceEnabled"), isLast: true) {
                            Toggle(text.t("automationUIWorkplaceEnabled"), isOn: $isEnabled).labelsHidden()
                        }
                    }
                }
                .padding(.top, OWCDesign.sectionGap)
                Text(text.t("automationUIRangeNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if !isNew {
                    OWCGroupCard {
                        Button(action: onDelete) {
                            OWCRow(icon: "trash", title: text.t("automationUIDeleteWorkplace"), isLast: true,
                                   isDestructive: true) { EmptyView() }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    .padding(.top, OWCDesign.sectionGap)
                    Text(text.t("automationUIDeleteWorkplaceNote"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle(isNew ? text.t("automationUIAddWorkplace") : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancel"), action: onCancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(text.t("saveAction"), action: onSave).disabled(!canSave)
            }
        }
        .tint(OWCDesign.accent)
    }

    @ViewBuilder private var mapCard: some View {
        Group {
            if let center {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: center, latitudinalMeters: outerRadius * 3.2, longitudinalMeters: outerRadius * 3.2
                )), interactionModes: []) {
                    MapCircle(center: center, radius: outerRadius)
                        .foregroundStyle(OWCDesign.accent.opacity(0.06))
                        .stroke(OWCDesign.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    MapCircle(center: center, radius: innerRadius)
                        .foregroundStyle(OWCDesign.accent.opacity(0.16))
                        .stroke(OWCDesign.accent, lineWidth: 1.5)
                    Annotation("", coordinate: center) {
                        Image(systemName: "building.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(OWCDesign.accent))
                    }
                }
                .id(innerRadius)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title2)
                        .foregroundStyle(OWCDesign.tertiary)
                    Text(text.t("automationUINoLocationYet"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OWCDesign.card)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}

// MARK: - Review

/// One suggestion as the review list shows it; built from a `WorkTimeProposal`.
struct AutomationReviewItem: Identifiable, Equatable {
    let id: UUID
    let dayTitle: String
    let boundary: WorkTimeBoundary
    let time: String
    let planned: String
    let note: String?
    let source: AutomationEventSource
}

/// One day's change in the batch preview.
struct AutomationReviewChange: Identifiable, Equatable {
    let id: String
    let dayTitle: String
    let before: String
    let after: String
}

/// A recently adopted time that can still be undone.
struct AutomationRecentItem: Identifiable, Equatable {
    let id: UUID
    let dayTitle: String
    let summary: String
}

struct AutomationReviewContent: View {
    let text: AppText
    let items: [AutomationReviewItem]
    let recent: [AutomationRecentItem]
    var preview: ([UUID]) -> [AutomationReviewChange] = { _ in [] }
    var onApply: ([UUID]) -> Void = { _ in }
    var onDismiss: ([UUID]) -> Void = { _ in }
    var onUndo: (UUID) -> Void = { _ in }

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingApply: [UUID]?

    var body: some View {
        Group {
            if items.isEmpty && recent.isEmpty {
                ContentUnavailableView {
                    Label(text.t("automationUIReviewEmpty"), systemImage: "checkmark.circle")
                } description: {
                    Text(text.t("automationUIReviewEmptyNote"))
                }
                .background(OWCDesign.page)
            } else {
                list
            }
        }
        .navigationTitle(text.t("automationUIReviewTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? text.t("done") : text.t("automationUISelect")) {
                        withAnimation(OWCMotion.selection) {
                            isSelecting.toggle()
                            selection.removeAll()
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .sheet(item: Binding(
            get: { pendingApply.map(PendingApply.init) },
            set: { pendingApply = $0?.ids }
        )) { pending in
            AutomationApplyPreview(text: text, changes: preview(pending.ids)) {
                onApply(pending.ids)
                pendingApply = nil
                selection.removeAll()
                isSelecting = false
            }
        }
        .tint(OWCDesign.accent)
    }

    private struct PendingApply: Identifiable {
        let ids: [UUID]
        var id: String { ids.map(\.uuidString).joined() }
    }

    private var list: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(text.t("automationUIReviewIntro"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                ForEach(groupedDays, id: \.title) { day in
                    OWCSectionHeader(title: day.title)
                        .padding(.top, OWCDesign.sectionGap)
                    OWCGroupCard {
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                            row(item, isLast: index == day.items.count - 1)
                        }
                    }
                }
                if !recent.isEmpty {
                    OWCSectionHeader(title: text.t("automationUIRecentSection"))
                        .padding(.top, OWCDesign.sectionGap)
                    OWCGroupCard {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                            OWCRow(title: item.dayTitle, subtitle: item.summary, isLast: index == recent.count - 1,
                                   centersVertically: true) {
                                Button(text.t("automationUIUndo")) { onUndo(item.id) }
                                    .font(.subheadline)
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .background(OWCDesign.page)
    }

    private var groupedDays: [(title: String, items: [AutomationReviewItem])] {
        var order: [String] = []
        var byDay: [String: [AutomationReviewItem]] = [:]
        for item in items {
            if byDay[item.dayTitle] == nil { order.append(item.dayTitle) }
            byDay[item.dayTitle, default: []].append(item)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    @ViewBuilder private func row(_ item: AutomationReviewItem, isLast: Bool) -> some View {
        let title = text.t(item.boundary == .start ? "automationUIStartAt" : "automationUIEndAt", values: ["time": item.time])
        let source = text.t(item.source == .nativeGeofence ? "automationUISourceLocation" : "automationUISourceShortcuts")
        let subtitle = [text.t("automationUIPlanned", values: ["time": item.planned]), item.note, source]
            .compactMap { $0 }
            .joined(separator: " · ")
        if isSelecting {
            Button { toggle(item.id) } label: {
                OWCRow(icon: selection.contains(item.id) ? "checkmark.circle.fill" : "circle",
                       title: title, subtitle: subtitle, isLast: isLast,
                       iconTint: selection.contains(item.id) ? OWCDesign.accent : OWCDesign.tertiary) { EmptyView() }
            }
            .buttonStyle(OWCRowButtonStyle())
        } else {
            OWCRow(icon: item.boundary == .start ? "figure.walk.arrival" : "figure.walk.departure",
                   title: title, subtitle: subtitle, isLast: isLast) {
                Menu {
                    Button { pendingApply = [item.id] } label: {
                        Label(text.t("automationUIApplyOne"), systemImage: "checkmark")
                    }
                    Button { onDismiss([item.id]) } label: {
                        Label(text.t("automationUIDismissOne"), systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button(selection.count == items.count ? text.t("automationUIDeselectAll") : text.t("automationUISelectAll")) {
                selection = selection.count == items.count ? [] : Set(items.map(\.id))
            }
            Spacer()
            Button(text.t("automationUIDismissSelected")) {
                onDismiss(Array(selection))
                selection.removeAll()
            }
            .disabled(selection.isEmpty)
            Button(text.t("automationUIApplySelected", values: ["count": "\(selection.count)"])) {
                pendingApply = items.map(\.id).filter(selection.contains)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

/// Shows exactly what will change before a batch is adopted (§3.12).
struct AutomationApplyPreview: View {
    let text: AppText
    let changes: [AutomationReviewChange]
    var onConfirm: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.t("automationUIPreviewIntro"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    OWCGroupCard {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            OWCRow(title: change.dayTitle, isLast: index == changes.count - 1) {
                                HStack(spacing: 6) {
                                    Text(change.before)
                                        .foregroundStyle(OWCDesign.secondary)
                                        .strikethrough(color: OWCDesign.tertiary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(OWCDesign.tertiary)
                                    Text(change.after)
                                }
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(text.t("automationUIPreviewTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("automationUIApplySelected", values: ["count": "\(changes.count)"]), action: onConfirm)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(OWCDesign.accent)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum WorkplaceAutomationPreviewFixtures {
    static func text(_ language: String = "zh-TW") -> AppText {
        let defaults = UserDefaults(suiteName: "WorkplaceAutomationPreview.\(language)")!
        defaults.set(language, forKey: "ios.native.languageOverride")
        return AppText(preferences: PreferencesStore(defaults: defaults, records: .inMemory()))
    }

    static let office = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)

    static func workplaces(_ count: Int) -> [SavedWorkplace] {
        let names = ["信義總部", "內湖辦公室", "客戶現場", "倉庫", "共享辦公室"]
        return (0..<count).map { index in
            SavedWorkplace(
                id: UUID(), name: names[index], latitude: 25.03 + Double(index) * 0.01, longitude: 121.56,
                innerRadius: index == 1 ? 300 : 200, outerRadius: index == 1 ? 400 : 300,
                isEnabled: index != 2, registrationGeneration: index + 1
            )
        }
    }

    static let reviewItems: [AutomationReviewItem] = [
        AutomationReviewItem(id: UUID(), dayTitle: "11月10日 週二", boundary: .start, time: "08:12", planned: "09:00",
                             note: "早到，確認後才算開始工作", source: .nativeGeofence),
        AutomationReviewItem(id: UUID(), dayTitle: "11月10日 週二", boundary: .end, time: "19:34", planned: "18:00",
                             note: "加班 1 小時 34 分", source: .nativeGeofence),
        AutomationReviewItem(id: UUID(), dayTitle: "11月9日 週一", boundary: .start, time: "09:14", planned: "09:00",
                             note: nil, source: .appIntentAutomation),
        AutomationReviewItem(id: UUID(), dayTitle: "11月9日 週一", boundary: .end, time: "18:20", planned: "18:00",
                             note: "你已手動修改這天", source: .nativeGeofence),
    ]

    static let recent: [AutomationRecentItem] = [
        AutomationRecentItem(id: UUID(), dayTitle: "11月6日 週五", summary: "09:03–18:41 · 自動套用"),
    ]

    static let changes: [AutomationReviewChange] = [
        AutomationReviewChange(id: "2026-11-10", dayTitle: "11月10日 週二", before: "09:00–18:00", after: "08:12–19:34"),
        AutomationReviewChange(id: "2026-11-09", dayTitle: "11月9日 週一", before: "09:00–18:00", after: "09:14–18:20"),
    ]
}

#Preview("設定 · 已開啟") {
    NavigationStack {
        WorkplaceAutomationSettingsContent(
            text: WorkplaceAutomationPreviewFixtures.text(), isPlus: true, access: .always,
            settings: WorkplaceAutomationSettings(isMonitoringEnabled: true),
            workplaces: WorkplaceAutomationPreviewFixtures.workplaces(2), pendingCount: 4
        )
    }
}

#Preview("設定 · 未開啟") {
    NavigationStack {
        WorkplaceAutomationSettingsContent(
            text: WorkplaceAutomationPreviewFixtures.text(), isPlus: true, access: .notRequested,
            settings: WorkplaceAutomationSettings(), workplaces: [], pendingCount: 0
        )
    }
}

#Preview("設定 · 只允許使用期間 · 5 個地點") {
    NavigationStack {
        WorkplaceAutomationSettingsContent(
            text: WorkplaceAutomationPreviewFixtures.text(), isPlus: true, access: .whenInUseOnly,
            settings: WorkplaceAutomationSettings(isMonitoringEnabled: true, appliesDetectedTimesAutomatically: true),
            workplaces: WorkplaceAutomationPreviewFixtures.workplaces(5), pendingCount: 0
        )
    }
}

#Preview("設定 · 非 Plus · 英文") {
    NavigationStack {
        WorkplaceAutomationSettingsContent(
            text: WorkplaceAutomationPreviewFixtures.text("en"), isPlus: false, access: .notRequested,
            settings: WorkplaceAutomationSettings(), workplaces: [], pendingCount: 0
        )
    }
}

#Preview("新增工作地點") {
    @Previewable @State var name = ""
    @Previewable @State var radius = 200.0
    @Previewable @State var enabled = true
    NavigationStack {
        WorkplaceEditorContent(
            text: WorkplaceAutomationPreviewFixtures.text(), isNew: true, name: $name, innerRadius: $radius,
            isEnabled: $enabled, center: nil, isLocating: false
        )
    }
}

#Preview("編輯工作地點") {
    @Previewable @State var name = "信義總部"
    @Previewable @State var radius = 200.0
    @Previewable @State var enabled = true
    NavigationStack {
        WorkplaceEditorContent(
            text: WorkplaceAutomationPreviewFixtures.text(), isNew: false, name: $name, innerRadius: $radius,
            isEnabled: $enabled, center: WorkplaceAutomationPreviewFixtures.office, isLocating: false
        )
    }
}

#Preview("待確認記錄") {
    NavigationStack {
        AutomationReviewContent(
            text: WorkplaceAutomationPreviewFixtures.text(),
            items: WorkplaceAutomationPreviewFixtures.reviewItems,
            recent: WorkplaceAutomationPreviewFixtures.recent,
            preview: { _ in WorkplaceAutomationPreviewFixtures.changes }
        )
    }
}

#Preview("待確認記錄 · 空") {
    NavigationStack {
        AutomationReviewContent(text: WorkplaceAutomationPreviewFixtures.text(), items: [], recent: [])
    }
}

#Preview("採用前預覽") {
    AutomationApplyPreview(
        text: WorkplaceAutomationPreviewFixtures.text(),
        changes: WorkplaceAutomationPreviewFixtures.changes
    )
}
#endif
