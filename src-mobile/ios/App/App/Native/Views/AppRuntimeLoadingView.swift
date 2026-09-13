import SwiftUI

/// Keeps every scene and process service behind the same durable bootstrap.
/// A failed debug reset therefore exposes neither stale owners nor QA seeds.
struct AppRuntimeLoadingView: View {
    @State private var runtime: AppRuntime?
    @State private var isLoading = false
    @State private var failed = false
    private let localizer = NativeLocalizer()

    var body: some View {
        Group {
            if let runtime {
                OffWorkCountdownRootView(runtime: runtime)
            } else if failed {
                ContentUnavailableView {
                    Label(text("recordsArchiveSaveFailedTitle"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(text("recordsArchiveSaveFailedBody"))
                } actions: {
                    Button(text("retryAction")) { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard runtime == nil, !isLoading else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            runtime = try await AppRuntime.loadShared()
        } catch {
            failed = true
        }
    }

    private func text(_ key: String) -> String {
        localizer.string(key, locale: NativeLocalizer.systemLanguage())
    }
}
