import SwiftUI

/// The label on the button that ends the day, in both of its states.
///
/// Shared across the active timer layouts because this is the second thing
/// about the action that has to stay identical everywhere. The first was the
/// confirmation state itself, which is why each scene owns one shared value.
///
/// The armed appearance deliberately copies `ShiftStartButton`: the same deep
/// orange, the same warning glyph. That button already teaches "this one needs
/// a second press", and teaching it twice with two different vocabularies would
/// be worse than not teaching it at all.
struct ClockOffEarlyLabel: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var warningPulse = 0

    private var confirmationID: UUID? { scene.clockOffConfirmationID(at: now, using: shifts) }
    private var armed: Bool { confirmationID != nil }

    var titleKey: String {
        return armed ? "clockOffEarlyConfirm" : "clockOffEarly"
    }

    var body: some View {
        Label(
            shifts.text.t(titleKey),
            systemImage: armed ? "exclamationmark.triangle.fill" : "arrow.left"
        )
        // Tint rather than a button style: three of the five call sites apply
        // their style to an enclosing stack, so a style here would be overridden
        // in some places and fight it in others.
        .foregroundStyle(armed ? OWCDesign.orangeDeep : OWCDesign.primary)
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: armed)
        .sensoryFeedback(.warning, trigger: warningPulse)
        .onChange(of: armed) { _, armed in
            if armed { warningPulse += 1 }
        }
        // Disarms itself, like the start button does. A confirmation left
        // standing is one the user meets again much later, having forgotten it,
        // and fires with a press they meant as their first.
        .task(id: confirmationID) {
            guard let confirmationID else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            scene.cancelTimerConfirmation(id: confirmationID)
        }
    }
}

struct ClockInEarlyLabel: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let now: Date
    var tinted = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var warningPulse = 0

    private var confirmationID: UUID? { scene.clockInConfirmationID(at: now, using: shifts) }
    private var armed: Bool { confirmationID != nil }

    var body: some View {
        Label(
            shifts.text.t(armed ? "clockInEarlyConfirm" : "clockInEarly"),
            systemImage: armed ? "exclamationmark.triangle.fill" : "arrow.right"
        )
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(tinted ? (armed ? OWCDesign.orangeDeep : OWCDesign.primary) : .white)
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: armed)
        .sensoryFeedback(.warning, trigger: warningPulse)
        .onChange(of: armed) { _, armed in
            if armed { warningPulse += 1 }
        }
        .task(id: confirmationID) {
            guard let confirmationID else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            scene.cancelTimerConfirmation(id: confirmationID)
        }
    }
}

/// The way back from an early clock-off. Shared by setup and the completed
/// screen so undoing is the same action in the same words, not two banners
/// that drift apart. Callers pass `note` so the banner does not ask
/// JavaScriptCore again after they already decided to show it.
struct EarlyClockOffBanner: View {
    let shifts: ShiftSessionStore
    let note: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk.departure")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
            Spacer(minLength: 8)
            Button(shifts.text.t("undoClockOffEarly")) { shifts.undoEarlyClockOff() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OWCDesign.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}

struct EarlyClockInBanner: View {
    let shifts: ShiftSessionStore
    let note: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk.arrival")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
            Spacer(minLength: 8)
            Button(shifts.text.t("undoClockInEarly")) { shifts.undoEarlyClockIn() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OWCDesign.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}

struct ManualTimingBanner: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let now: Date
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var warningPulse = 0
    @State private var commitPulse = 0

    private var confirmationID: UUID? {
        scene.cancelManualTimingConfirmationID(at: now, using: shifts)
    }
    private var armed: Bool { confirmationID != nil }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
            Text(shifts.text.t("manualTimingBanner"))
                .font(compact ? .footnote : .subheadline)
                .foregroundStyle(OWCDesign.secondary)
            if !compact { Spacer(minLength: 8) }
            Button {
                let commits = armed
                if !commits { warningPulse += 1 }
                let command = scene.requestCancelManualTiming(at: now, using: shifts)
                if let accepted = command.immediateResult {
                    if accepted { commitPulse += 1 }
                } else {
                    Task {
                        if await command.value { commitPulse += 1 }
                    }
                }
            } label: {
                Text(shifts.text.t(armed ? "cancelManualTimingConfirm" : "cancelManualTiming"))
                    .font((compact ? Font.footnote : .subheadline).weight(.semibold))
                    .foregroundStyle(armed ? OWCDesign.orangeDeep : OWCDesign.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, compact ? 12 : 14)
        .frame(minHeight: compact ? 26 : 48)
        .background(
            OWCDesign.card,
            in: RoundedRectangle(
                cornerRadius: compact ? 100 : OWCDesign.cardRadius,
                style: .continuous
            )
        )
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: armed)
        .sensoryFeedback(.warning, trigger: warningPulse)
        .sensoryFeedback(.impact(weight: .medium), trigger: commitPulse)
        .task(id: confirmationID) {
            guard let confirmationID else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            scene.cancelTimerConfirmation(id: confirmationID)
        }
    }
}
