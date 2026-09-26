#if PERF_AUTOPILOT
import Foundation

/// Profiling only. Replays tab switches and settings pushes by writing the same
/// scene state a tap writes, so an Instruments recording carries no XCUITest
/// accessibility snapshots on the main thread. Compiled only into builds that
/// add `PERF_AUTOPILOT` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`; start with
/// the launch argument `-owcPerfAutopilot A|B|C`.
@MainActor
enum PerfAutopilot {
    private enum Step {
        case tab(AppTab)
        case push(AppRoute)
        case pop
        case wait(Double)
    }

    static func run(scene: SceneState) async {
        guard let name = UserDefaults.standard.string(forKey: "owcPerfAutopilot") else { return }
        let steps: [Step] = switch name {
        case "A":
            [.tab(.timer)]
                + Array(repeating: [Step.tab(.records), .tab(.settings), .tab(.timer)], count: 5).flatMap { $0 }
                + [.tab(.settings), .wait(6), .tab(.timer)]
        case "B":
            [.tab(.settings)] + Array(repeating: [Step.push(.schedule), .pop], count: 6).flatMap { $0 }
        case "C":
            [.tab(.settings)]
                + Array(repeating: [Step.push(.notifications), .pop], count: 4).flatMap { $0 }
                + Array(repeating: [Step.push(.salary), .pop], count: 4).flatMap { $0 }
        default:
            []
        }
        try? await Task.sleep(for: .seconds(6))
        LaunchTrace.signposter.emitEvent("autopilotBegin")
        for step in steps {
            switch step {
            case .tab(let tab):
                LaunchTrace.signposter.emitEvent("autopilot", "tab \(tab.rawValue)")
                scene.selectedTab = tab
            case .push(let route):
                LaunchTrace.signposter.emitEvent("autopilot", "push \(route.rawValue)")
                scene.settingsPath.append(route)
            case .pop:
                LaunchTrace.signposter.emitEvent("autopilot", "pop")
                _ = scene.settingsPath.popLast()
            case .wait(let seconds):
                try? await Task.sleep(for: .seconds(seconds))
                continue
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        LaunchTrace.signposter.emitEvent("autopilotEnd")
    }
}
#endif
