import Foundation

/// The installed app's version, including its build when available.
nonisolated enum AppVersion {
    static func display(in bundle: Bundle = .main) -> String {
        display(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func display(version: String?, build: String?) -> String {
        let version = version ?? "1.0"
        guard let build = build?.trimmingCharacters(in: .whitespacesAndNewlines),
              !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
