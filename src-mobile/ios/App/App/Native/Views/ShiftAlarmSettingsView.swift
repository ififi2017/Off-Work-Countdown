import SwiftUI
import UIKit

/// Plan 020 §3: wake-up alarms before each shift. On, how far ahead each
/// shift type rings, what is actually set and until when.
struct ShiftAlarmSettingsView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let alarms: ShiftAlarmService
    @State private var upcoming: [ShiftAlarmPlan.Item] = []
    @State private var refreshFeedback = 0

    private var text: AppText { shifts.text }
    private var settings: ShiftAlarmSettings { shifts.preferences.shiftAlarmSettings }
    private var isOn: Bool { settings.isEnabled && shifts.plus.isAuthorized }
    private var status: ShiftAlarmService.Status { alarms.status }

    /// Work shift types still in use, in the order the schedule lists them.
    private var workTypes: [ShiftType] {
        guard shifts.preferences.isExtendedScheduleEnabled,
              let content = shifts.preferences.extendedScheduleContent else { return [] }
        return content.shiftTypes.filter { $0.kind == .work && !$0.isArchived }
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text.t("shiftAlarmsTitle")).font(.body)
                            if !shifts.plus.isAuthorized {
                                Text(text.t("plusStatusSubscribed"))
                                    .font(.caption2.bold())
                                    .foregroundStyle(OWCDesign.accent)
                            }
                        }
                        Spacer()
                        Toggle(text.t("shiftAlarmsTitle"), isOn: Binding(get: { isOn }, set: setEnabled))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                }
                .padding(.top, 14)
                Text(text.t("shiftAlarmsIntro"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if isOn {
                    statusCard
                        .padding(.top, OWCDesign.sectionGap)
                    leadSection
                    if status.authorization == .authorized, !upcoming.isEmpty {
                        upcomingSection
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("shiftAlarmsTitle"))
        .tint(OWCDesign.accent)
        .sensoryFeedback(.selection, trigger: settings.signature)
        .sensoryFeedback(.success, trigger: refreshFeedback)
        .task(id: "\(settings.signature)|\(status.authorization)|\(shifts.plus.authorization)") {
            if isOn, alarms.status.authorization == .notDetermined {
                _ = await alarms.requestAuthorization()
            }
            await refresh()
        }
    }

    // MARK: - Status

    @ViewBuilder private var statusCard: some View {
        OWCGroupCard {
            switch status.authorization {
            case .notDetermined:
                Button { Task { _ = await alarms.requestAuthorization(); await refresh() } } label: {
                    OWCRow(icon: "alarm", title: text.t("shiftAlarmsAllow"), subtitle: text.t("shiftAlarmsAllowNote"),
                           isLast: true, centersVertically: true) { OWCDetailAccessory(text: nil) }
                }
                .buttonStyle(OWCRowButtonStyle())
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    OWCRow(icon: "exclamationmark.triangle", title: text.t("shiftAlarmsDenied"),
                           subtitle: text.t("shiftAlarmsDeniedNote"), isLast: true, centersVertically: true) {
                        Text(text.t("shiftAlarmsOpenSettings")).font(.subheadline).foregroundStyle(OWCDesign.accent)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            case .authorized:
                OWCRow(icon: "alarm", title: coverageTitle, subtitle: coverageNote, centersVertically: true) {
                    EmptyView()
                }
                Button {
                    Task {
                        await refresh()
                        refreshFeedback += 1
                    }
                } label: {
                    OWCRow(icon: "arrow.clockwise", title: text.t("shiftAlarmsRefresh"), isLast: true) { EmptyView() }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
        }
    }

    private var coverageTitle: String {
        guard let through = status.coveredThrough else { return text.t("shiftAlarmsNoneUpcoming") }
        return text.t("shiftAlarmsCoveredThrough", values: ["date": dateAndTime(through)])
    }

    /// Why the alarms stop where they do, and what continues them.
    private var coverageNote: String? {
        var notes: [String] = []
        if status.reachedSystemLimit || status.failedCount > 0 {
            notes.append(text.t("shiftAlarmsLimitReached"))
        } else if shifts.plus.isLifetime {
            notes.append(text.t("shiftAlarmsLifetimeWindow"))
        } else if let end = status.windowEnd {
            notes.append(text.t("shiftAlarmsUntilExpiry", values: ["date": dateAndTime(end)]))
        }
        if status.refreshReminderUnavailable {
            notes.append(text.t("shiftAlarmsReminderOff"))
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    // MARK: - Lead times

    @ViewBuilder private var leadSection: some View {
        OWCSectionHeader(title: text.t("shiftAlarmsLeadSection"))
            .padding(.top, OWCDesign.sectionGap)
        OWCGroupCard {
            let types = workTypes
            if types.isEmpty {
                leadRow(title: text.t("shiftAlarmsBeforeWork"), subtitle: nil, typeID: nil, isLast: true)
            } else {
                ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                    leadRow(
                        title: type.name,
                        subtitle: text.t("shiftAlarmsStartsAt", values: ["time": clock(type.startMinutes)]),
                        typeID: type.id,
                        isLast: index == types.count - 1
                    )
                }
            }
        }
    }

    private func leadRow(title: String, subtitle: String?, typeID: UUID?, isLast: Bool) -> some View {
        OWCRow(title: title, subtitle: subtitle, isLast: isLast, centersVertically: true) {
            Picker(title, selection: leadBinding(typeID)) {
                if typeID != nil {
                    Text(text.t("shiftAlarmsLeadOff")).tag(Int?.none)
                }
                ForEach(ShiftAlarmSettings.leadChoices, id: \.self) { minutes in
                    Text(text.formatRelativeDuration(Double(minutes) * 60_000)).tag(Int?.some(minutes))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func leadBinding(_ typeID: UUID?) -> Binding<Int?> {
        Binding(
            get: { settings.leadMinutes(for: typeID) },
            set: { minutes in
                var next = settings
                if let typeID {
                    if let minutes {
                        next.silencedShiftTypeIDs.remove(typeID)
                        next.leadMinutesByShiftType[typeID] = minutes
                    } else {
                        next.silencedShiftTypeIDs.insert(typeID)
                    }
                } else if let minutes {
                    next.defaultLeadMinutes = minutes
                }
                shifts.preferences.shiftAlarmSettings = next
            }
        )
    }

    // MARK: - Coming up

    @ViewBuilder private var upcomingSection: some View {
        OWCSectionHeader(title: text.t("shiftAlarmsUpcoming"))
            .padding(.top, OWCDesign.sectionGap)
        OWCGroupCard {
            let shown = Array(upcoming.prefix(5))
            ForEach(Array(shown.enumerated()), id: \.element.systemID) { index, item in
                OWCRow(icon: "alarm", title: dateAndTime(Date(timeIntervalSince1970: item.alarm.fireAtMs / 1_000)),
                       subtitle: item.title, isLast: index == shown.count - 1) { EmptyView() }
            }
        }
    }

    // MARK: - Actions

    private func setEnabled(_ enabled: Bool) {
        guard !enabled || shifts.plus.isAuthorized else {
            scene.requestShiftAlarms()
            return
        }
        var next = settings
        next.isEnabled = enabled
        shifts.preferences.shiftAlarmSettings = next
    }

    /// Plans and hands the alarms to the system now rather than waiting for
    /// the next publication, so the page shows what really got set.
    private func refresh() async {
        let plan = shifts.shiftAlarmPlan()
        upcoming = plan.items
        await alarms.reconcile(plan)
    }

    // MARK: - Formatting

    private func dateAndTime(_ date: Date) -> String {
        RecordsDateFormatters.shared
            .formatter(template: "MMMdEEEjm", locale: shifts.preferences.locale, timeZone: shifts.session.countdownTimeZone)
            .string(from: date)
    }

    private func clock(_ minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let date = Calendar(identifier: .gregorian).date(from: components) ?? .now
        return RecordsDateFormatters.shared
            .formatter(template: "jm", locale: shifts.preferences.locale, timeZone: .current)
            .string(from: date)
    }
}
