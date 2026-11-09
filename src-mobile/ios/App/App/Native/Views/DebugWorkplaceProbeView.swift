#if DEBUG || WORKPLACE_PROBE
import SwiftUI

/// Plan 021 P0: controls and log for `WorkplaceProbe`. Debug-only and
/// maintainer-facing, so its text is written inline like the other debug
/// sections and stays out of the String Catalog.
struct DebugWorkplaceProbeView: View {
    @State private var probe = WorkplaceProbe.shared
    @State private var innerRadius = WorkplaceAutomation.defaultInnerRadius
    @State private var exportURL: URL?
    @State private var isWorking = false

    var body: some View {
        List {
#if !DEBUG
            Section {
                Label(String("内部测试版：含工作地点探针，不得提交审核或发布"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
#endif
            Section {
                row("状态", probe.archive.isEnabled ? "运行中" : "未开启")
                row("定位授权", probe.authorizationLabel)
                row("精度", probe.accuracyLabel)
                row("条件数", "\(probe.archive.conditionCount) / 20")
            } footer: {
                Text(verbatim: "测试前在 Xcode Scheme 关闭 Debug executable，或安装后停止运行再从主屏幕打开；调试器会让 App 一直留在后台。")
            }

            Section {
                if probe.archive.isEnabled {
                    Button(role: .destructive) { run { await probe.disable() } } label: {
                        Label(String("关闭探针"), systemImage: "stop.circle")
                    }
                } else {
                    Button { run { await probe.enable() } } label: {
                        Label(String("开启探针并请求“始终”授权"), systemImage: "location.circle")
                    }
                }
                Stepper(value: $innerRadius, in: 100...500, step: 50) {
                    Text(verbatim: "内圈 \(Int(innerRadius)) 米 · 外圈 \(Int(innerRadius + WorkplaceAutomation.defaultOuterRadiusMargin)) 米")
                }
                Button { run { await probe.addCurrentLocation(innerRadius: innerRadius) } } label: {
                    HStack {
                        Label(String("把当前位置加为地点"), systemImage: "mappin.and.ellipse")
                        Spacer()
                        if probe.isLocating { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(!probe.archive.isEnabled || probe.archive.places.count >= WorkplaceProbeArchive.maximumPlaces)
                Button { run { await probe.fillToFivePlaces() } } label: {
                    Label(String("补足到 5 个地点（10 个条件）"), systemImage: "square.stack.3d.up")
                }
                .disabled(!probe.archive.isEnabled || probe.archive.places.isEmpty)
                Button(role: .destructive) { run { await probe.removeAllPlaces() } } label: {
                    Label(String("移除全部地点"), systemImage: "trash")
                }
                .disabled(probe.archive.places.isEmpty)
            } footer: {
                Text(verbatim: "补足用的地点在第一个地点以北 1–4 公里，只用来测试系统额度。")
            }
            .disabled(isWorking)

            if !probe.archive.places.isEmpty {
                Section {
                    ForEach(probe.archive.places) { place in
                        row(place.name, "\(Int(place.innerRadius))/\(Int(place.outerRadius)) 米\(place.isFiller ? " · 补足" : "")")
                    }
                } header: {
                    Text(verbatim: "地点")
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(String("分享导出文件"), systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    exportURL = try? probe.exportFile()
                } label: {
                    Label(String("生成导出文件（不含坐标）"), systemImage: "doc.text")
                }
                Button(role: .destructive) {
                    probe.clearLog()
                    exportURL = nil
                } label: {
                    Label(String("清空记录"), systemImage: "xmark.bin")
                }
            } header: {
                Text(verbatim: "记录 · \(probe.archive.entries.count) 条")
            }

            Section {
                ForEach(probe.archive.entries.suffix(200).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: summary(entry))
                            .font(.callout.monospaced())
                        Text(verbatim: context(entry))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(verbatim: "最新的在上方，只显示最近 200 条；导出包含全部。")
            }
        }
        .navigationTitle(String("工作地点探针"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).monospaced()
        } label: {
            Text(verbatim: title)
        }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }

    private func summary(_ entry: WorkplaceProbeEntry) -> String {
        let time = entry.receivedAt.formatted(date: .omitted, time: .standard)
        var parts = [time, entry.kind.rawValue]
        if let identifier = entry.identifier { parts.append(probe.archive.placeLabel(for: identifier)) }
        if let state = entry.state { parts.append(state) }
        if let delay = entry.deliveryDelay { parts.append("+\(Int(delay))s") }
        return parts.joined(separator: " ")
    }

    private func context(_ entry: WorkplaceProbeEntry) -> String {
        var parts = [
            entry.appState,
            entry.protectedDataAvailable ? "unlocked" : "locked",
            entry.authorization,
            entry.accuracy,
        ]
        parts.append(contentsOf: entry.flags)
        if let detail = entry.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}
#endif
