import Foundation

/// Browsing and editor presentation belong to the scene, so changing layout
/// does not reset a selected period or dismiss a pending operation.
@MainActor
@Observable
final class RecordsSceneState {
    var scale: RecordsScale
    var anchor = Date.now
    var selectedDayKey: String?
    var quickDay: RecordsDayIdentified?
    var selectedYearMonth: Int?
    var selectedLifeStageID: String?
    var yearCalloutMonth: Int?
    var yearSelectionDate: Date?
    var lifeSelectionDate: Date?
    var expanded: [RecordsScale: Bool] = [:]
    var showsLifeEditor = false

    init(scale: RecordsScale = .month, defaults: UserDefaults? = nil) {
        self.scale = scale
#if DEBUG
        if let requested = defaults?.string(forKey: "ios.native.qaRecordsScale").flatMap(RecordsScale.init(rawValue:)) {
            self.scale = requested
        }
        if defaults?.bool(forKey: "ios.native.qaRecordsExpanded") == true,
           self.scale == .year || self.scale == .life {
            expanded[self.scale] = true
        }
#endif
    }
}

enum FocusCanvasScale: String, CaseIterable, Identifiable {
    case today, usual
    var id: String { rawValue }
}

enum FocusQuickCreateLanding: String, Identifiable {
    case nextBlock, currentOrNextBlock, startNow, unscheduled
    var id: String { rawValue }
}

/// What the editor was opened for.
struct FocusTemplateDraft: Identifiable {
    var id: UUID { template?.id ?? newID }
    /// nil when this is a new template being drawn from today.
    var template: FocusTemplate?
    var newID = UUID()
    var name: String
    var slots: [FocusTemplateSlot]
}

@MainActor
@Observable
final class FocusSceneState {
    var scale: FocusCanvasScale = .today
    var selectedBlock: Int64?
    var editingBlock: FocusDayCanvasModel.Block?
    var editingTask: FocusTask?
    var confirmsClearDay = false
    var namesDayTemplate = false
    var dayTemplateName = ""
    var favoriteToCreate: FocusTask?
    var quickCreateLanding: FocusQuickCreateLanding?
    var showsTimerSettings = false
    var editingTemplate: FocusTemplateDraft?
    var confirmsStop = false
    var taskToExtend: UUID?

    init(defaults: UserDefaults? = nil) {
#if DEBUG
        scale = defaults?.string(forKey: "ios.native.qaFocusScale").flatMap(FocusCanvasScale.init(rawValue:)) ?? .today
#endif
    }
}
