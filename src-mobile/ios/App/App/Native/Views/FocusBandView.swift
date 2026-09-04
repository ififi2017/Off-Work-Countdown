import SwiftUI

/// The shift, drawn to scale.
///
/// One block is one target, so the band is vertical and scrolls: a horizontal
/// strip of a whole shift cannot give a 25-minute block a 44 pt hit area. The
/// records day canvas stays horizontal for the opposite reason — it is read,
/// not edited.
///
/// Proportion is the point, so nothing here has a minimum height. A five
/// minute break is a fifth of a focus block and a one minute break is a
/// hairline, because that is what they are.
struct FocusBandView: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    @Binding var selectedBlock: Int64?
    var onPick: (FocusDayCanvasModel.Block) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rulerWidth: CGFloat { 58 }

    var body: some View {
        // At accessibility sizes the band's meaning comes from height
        // differences that the text itself then eats. The list keeps the same
        // order, the same states and the same actions.
        if dynamicTypeSize.isAccessibilitySize {
            FocusBandList(store: store, model: model, onPick: onPick)
        } else {
            band
        }
    }

    private var band: some View {
        HStack(alignment: .top, spacing: 0) {
            ruler
            ZStack(alignment: .topLeading) {
                ForEach(model.gaps) { gap in
                    gapTile(gap)
                        .offset(y: model.offset(ofMs: gap.startAtMs))
                }
                ForEach(model.blocks) { block in
                    blockTile(block)
                        .offset(y: model.offset(ofMs: block.startAtMs))
                        .id(block.startAtMs)
                }
                if let nowAtMs = model.nowAtMs {
                    nowLine.offset(y: model.offset(ofMs: nowAtMs) - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: model.totalHeight, alignment: .top)
        .accessibilityRepresentation {
            FocusBandList(store: store, model: model, onPick: onPick)
        }
    }

    private var ruler: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(hourMarks, id: \.self) { ms in
                Text(store.formatTime(Date(timeIntervalSince1970: Double(ms) / 1_000)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: model.offset(ofMs: ms) - 7)
            }
        }
        .frame(width: rulerWidth, alignment: .topTrailing)
        .padding(.trailing, 8)
        .accessibilityHidden(true)
    }

    /// Whole hours inside the drawn shift. A shift that crosses midnight keeps
    /// running past 24:00 rather than restarting, because the band measures
    /// this shift and not a civil day.
    private var hourMarks: [Int64] {
        guard model.durationMs > 0 else { return [] }
        let hour: Int64 = 3_600_000
        var marks: [Int64] = []
        var cursor = (model.shiftStartAtMs / hour) * hour
        if cursor < model.shiftStartAtMs { cursor += hour }
        while cursor <= model.shiftEndAtMs {
            marks.append(cursor)
            cursor += hour
        }
        return marks
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(OWCDesign.accent)
                .frame(width: 7, height: 7)
                .offset(x: -3.5)
            Rectangle().fill(OWCDesign.accent).frame(height: 2)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func gapTile(_ gap: FocusDayCanvasModel.Gap) -> some View {
        let height = model.height(ofMs: gap.endAtMs - gap.startAtMs)
        Group {
            switch gap.kind {
            case .betweenSegments:
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(OWCDesign.control)
            case .tail:
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        OWCDesign.separator,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
        }
        .frame(height: height)
        .overlay(alignment: .leading) {
            if height >= 20 {
                Text(gapLabel(gap))
                    .font(.caption2)
                    .foregroundStyle(OWCDesign.tertiary)
                    .padding(.leading, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func gapLabel(_ gap: FocusDayCanvasModel.Gap) -> String {
        switch gap.kind {
        case .betweenSegments:
            return store.t("focusBandGapBreak")
        case .tail:
            return store.t("focusBandGapTooShort", values: ["count": "\(gap.durationMinutes)"])
        }
    }

    @ViewBuilder
    private func blockTile(_ block: FocusDayCanvasModel.Block) -> some View {
        let height = model.height(ofMs: block.durationMs)
        if block.kind == .breakTime {
            breakTile(block, height: height)
                .accessibilityElement()
                .accessibilityLabel(spokenLabel(block))
        } else {
            Button { onPick(block) } label: {
                // A block the user turned into a break draws as one. Its kind
                // stays `.task`, which is what keeps it editable — otherwise
                // converting a block would be a one-way door.
                if block.isUserBreak {
                    breakTile(block, height: height)
                } else {
                    workTile(block, height: height)
                }
            }
            .buttonStyle(.plain)
            .disabled(!block.isEditable)
            .accessibilityLabel(spokenLabel(block))
            .accessibilityHint(block.isEditable ? store.t("focusBandBlockHint") : "")
        }
    }

    private func breakTile(_ block: FocusDayCanvasModel.Block, height: CGFloat) -> some View {
        // A break separates the work; it is not the work. Solid teal at full
        // saturation made these the loudest thing on the band, so they get the
        // same tinted ground and leading bar as a work block and sit behind it.
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: height >= 12 ? 3 : 1.5, style: .continuous)
                .fill(OWCDesign.recordsBreak.opacity(0.16))
            RoundedRectangle(cornerRadius: height >= 12 ? 1.75 : 0.75, style: .continuous)
                .fill(OWCDesign.recordsBreak)
                .frame(width: 3.5)
            if height >= 20 {
                VStack(alignment: .leading, spacing: 1) {
                    if block.isUserBreak {
                        Text(store.formatTime(Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    Label(
                        store.t("focusBandBreakMinutes", values: ["count": "\(block.durationMs / 60_000)"]),
                        systemImage: "cup.and.saucer.fill"
                    )
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(OWCDesign.recordsBreak)
                }
                .padding(.leading, 14)
            }
        }
        .frame(height: height)
        .opacity(block.state == .past ? 0.45 : 1)
        .frame(maxWidth: .infinity)
        .overlay {
            if block.state == .current {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(OWCDesign.accent, lineWidth: 2)
            } else if selectedBlock == block.startAtMs {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(OWCDesign.accent.opacity(0.6), lineWidth: 2)
            }
        }
    }

    private func workTile(_ block: FocusDayCanvasModel.Block, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(block.isAssigned ? OWCDesign.recordsWork.opacity(0.14) : Color.clear)
            if block.isAssigned {
                RoundedRectangle(cornerRadius: 1.75, style: .continuous)
                    .fill(OWCDesign.recordsWork)
                    .frame(width: 3.5)
                    .frame(maxHeight: .infinity)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        OWCDesign.tertiary,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.formatTime(Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                if let title = block.taskTitle {
                    Label {
                        Text(title).lineLimit(1)
                    } icon: {
                        Image(systemName: (block.taskIcon ?? .focus).systemName)
                    }
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.primary)
                } else {
                    Label(store.t("focusBandEmptyBlock"), systemImage: "plus")
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
        }
        .frame(height: height)
        .opacity(block.state == .past ? 0.45 : 1)
        .overlay {
            // The clock decides this, not whether a session is running: the
            // block you are inside is the current one either way.
            if block.state == .current {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(OWCDesign.accent, lineWidth: 2)
            } else if selectedBlock == block.startAtMs {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(OWCDesign.accent.opacity(0.6), lineWidth: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if block.state == .past, block.isAssigned {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.trailing, 12)
            }
        }
    }

    private func spokenLabel(_ block: FocusDayCanvasModel.Block) -> String {
        let time = store.formatTime(Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000))
        let minutes = "\(block.durationMs / 60_000)"
        if block.rendersAsBreak {
            return "\(time) · " + store.t("focusBandBreakMinutes", values: ["count": minutes])
        }
        switch block.kind {
        case .breakTime:
            return "\(time) · " + store.t("focusBandBreakMinutes", values: ["count": minutes])
        case .task:
            let what = block.taskTitle ?? store.t("focusBandEmptyBlock")
            let state: String
            switch block.state {
            case .past: state = store.t("focusBandStatePast")
            case .current: state = store.t("focusBandStateCurrent")
            case .future: state = ""
            }
            return [time, what, state].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}

/// The band's text form: the accessibility-size layout, and the alternative
/// VoiceOver reads instead of a picture.
struct FocusBandList: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    var onPick: (FocusDayCanvasModel.Block) -> Void

    var body: some View {
        OWCGroupCard {
            let rows = model.blocks.filter { $0.kind == .task || $0.durationMs >= 5 * 60_000 }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, block in
                Button { onPick(block) } label: {
                    OWCRow(
                        icon: rowIcon(block),
                        title: store.formatTime(Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)),
                        subtitle: subtitle(block),
                        isLast: index == rows.count - 1
                    ) { EmptyView() }
                }
                .buttonStyle(OWCRowButtonStyle())
                .disabled(!block.isEditable)
            }
        }
    }

    private func rowIcon(_ block: FocusDayCanvasModel.Block) -> String {
        if block.rendersAsBreak { return "cup.and.saucer.fill" }
        return (block.taskIcon ?? .focus).systemName
    }

    private func subtitle(_ block: FocusDayCanvasModel.Block) -> String {
        let minutes = "\(block.durationMs / 60_000)"
        if block.rendersAsBreak {
            return store.t("focusBandBreakMinutes", values: ["count": minutes])
        }
        let what = block.taskTitle ?? store.t("focusBandEmptyBlock")
        switch block.state {
        case .past: return "\(what) · " + store.t("focusBandStatePast")
        case .current: return "\(what) · " + store.t("focusBandStateCurrent")
        case .future: return what
        }
    }
}
