import AppIntents
import Foundation

// Plan 021 I1: Shortcuts actions for workplace automation.
//
// Two kinds, kept apart on purpose (§I1):
// - "Record arrival/departure" are reports a personal automation sends
//   (Arrive/Leave, Wi-Fi, Focus). They carry no trust level and follow the
//   same rules as a geofence event: review by default, early arrivals wait
//   for the person, lunch exits are only a trace.
// - "Confirm work started/finished" are the person's own statements. They
//   ask for confirmation first and then apply, like a tap in the review list.
//
// None of them requests location, imports a place or carries salary. Every
// write goes through `WorkplaceAutomationCoordinator`.

struct RecordWorkplaceArrivalIntent: AppIntent {
    static let title: LocalizedStringResource = "automationIntentRecordArrival"
    static let description = IntentDescription("automationIntentRecordArrivalDescription")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await WorkplaceAutomationIntentRunner.run(.enterInner, source: .appIntentAutomation)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct RecordWorkplaceDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "automationIntentRecordDeparture"
    static let description = IntentDescription("automationIntentRecordDepartureDescription")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await WorkplaceAutomationIntentRunner.run(.exitOuter, source: .appIntentAutomation)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ConfirmWorkStartedIntent: AppIntent {
    static let title: LocalizedStringResource = "automationIntentConfirmStart"
    static let description = IntentDescription("automationIntentConfirmStartDescription")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The time is when the action runs, not when the person answers.
        let now = Date.now
        let prompt = await WorkplaceAutomationIntentRunner.text(promptKey: "automationConfirmStartPrompt")
        try await requestConfirmation(actionName: .log, dialog: IntentDialog(stringLiteral: prompt))
        let message = await WorkplaceAutomationIntentRunner.run(.enterInner, source: .userConfirmation, at: now)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ConfirmWorkFinishedIntent: AppIntent {
    static let title: LocalizedStringResource = "automationIntentConfirmEnd"
    static let description = IntentDescription("automationIntentConfirmEndDescription")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let prompt = await WorkplaceAutomationIntentRunner.text(promptKey: "automationConfirmEndPrompt")
        try await requestConfirmation(actionName: .log, dialog: IntentDialog(stringLiteral: prompt))
        let message = await WorkplaceAutomationIntentRunner.run(.exitOuter, source: .userConfirmation, at: now)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Runs one Shortcuts action against the shared runtime, without a scene.
@MainActor
enum WorkplaceAutomationIntentRunner {
    static func run(
        _ type: AutomationEventType,
        source: AutomationEventSource,
        at time: Date = .now
    ) async -> String {
        guard let runtime = try? await AppRuntime.loadShared() else {
            return fallbackText("automationResultUnavailable")
        }
        // Checked again on every run: discovering an action does not unlock
        // it, and no purchase sheet opens in the background (§3.14).
        guard runtime.plus.canCollectAutomation else {
            return runtime.text.t("automationResultNeedsPlus")
        }
        // Shortcuts runs the action when its trigger fires, so the run time
        // is the best observation there is; the basis records that it is a
        // receipt time, not a system observation.
        let event = AutomationEvent(
            id: UUID(),
            source: source,
            type: type,
            workplaceID: nil,
            registrationGeneration: 0,
            observedAt: time,
            receivedAt: time,
            timestampBasis: source == .userConfirmation ? .userAction : .callbackReceipt
        )
        let outcome = await runtime.workplaceAutomation.receive(
            event,
            shifts: runtime.queries.automationShifts(around: time),
            now: time
        )
        return runtime.text.t(messageKey(for: outcome))
    }

    static func text(promptKey: String) async -> String {
        guard let runtime = try? await AppRuntime.loadShared() else { return fallbackText(promptKey) }
        return runtime.text.t(promptKey)
    }

    /// What the person hears or reads. "Saved for review" never claims hours changed.
    static func messageKey(for outcome: AutomationCommandOutcome) -> String {
        switch outcome {
        case .applied: "automationResultApplied"
        case .alreadyApplied: "automationResultAlreadyApplied"
        case .recordedForReview: "automationResultRecorded"
        case .needsReview: "automationResultNeedsReview"
        case .ignored: "automationResultNoChange"
        case .temporarilyUnavailable: "automationResultUnavailable"
        }
    }

    private static func fallbackText(_ key: String) -> String {
        NativeLocalizer().string(key, locale: NativeLocalizer.systemLanguage())
    }
}
