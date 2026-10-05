import SwiftUI

/// The same honest, illustrative feature scenes across discovery and purchase.
/// Manual navigation keeps the price page still while someone makes a decision.
struct PlusFeatureStage: View {
    let text: AppText
    var showsFocus = true
    @State private var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(text: AppText, initialSelection: Int = 0, showsFocus: Bool = true) {
        self.text = text
        self.showsFocus = showsFocus
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(spacing: 16) {
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                tab(0, "chart.bar.xaxis", "reportEntryTitle")
                tab(1, "sun.horizon", "leavePlanAction")
                if showsFocus { tab(2, "timer", "plusBenefitFocus") }
            }
            Group {
                switch selection {
                case 1: OnboardingRestDemo(text: text, isActive: true)
                case 2: OnboardingFocusDemo(text: text, isActive: true)
                default: OnboardingReportsDemo(text: text, isActive: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .id(selection)
            .transition(.opacity)
            Text(text.t(captionKey))
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(text.t("plusIllustration"))
                .font(.caption).foregroundStyle(OWCDesign.secondary)
        }
    }

    private var captionKey: String {
        switch selection {
        case 1: "onboardingPlusRestTitle"
        case 2: "onboardingPlusFocusTitle"
        default: "onboardingPlusReportsTitle"
        }
    }

    private func tab(_ value: Int, _ symbol: String, _ titleKey: String) -> some View {
        Button {
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) { selection = value }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.body)
                Text(text.t(titleKey)).font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selection == value ? OWCDesign.accent : OWCDesign.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 4)
            .background(selection == value ? OWCDesign.accent.opacity(0.10) : .clear,
                in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
