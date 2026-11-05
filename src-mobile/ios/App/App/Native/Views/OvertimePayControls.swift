import SwiftUI

/// Plan 024: the overtime pay multiplier choices the overtime sheet and the
/// salary settings share. The rule itself lives in `OvertimePay`.
nonisolated enum OvertimePayChoices {
    /// Offered directly; anything else is entered with the stepper.
    static let presets: [Double] = [1, 1.5, 2, 3]
    /// The stepper's range, in tenths.
    static let customTenths = 5...50
    /// Menu tag for "Custom…".
    static let customTag = -1

    static func isPreset(_ multiplier: Double) -> Bool { presets.contains(multiplier) }
    static func tenths(_ multiplier: Double) -> Int { Int((multiplier * 10).rounded()) }
    static func multiplier(tenths: Int) -> Double { Double(tenths) / 10 }
}

extension AppText {
    /// "1.5×", with the locale's decimal separator.
    func multiplierLabel(_ multiplier: Double) -> String {
        "\(formatDecimal(multiplier, fractionDigits: 0...1))×"
    }
}

/// A row whose trailing control steps a multiplier between 0.5× and 5× in 0.1s.
struct OvertimeMultiplierStepperRow: View {
    let text: AppText
    @Binding var multiplier: Double
    var isLast = false

    var body: some View {
        OWCRow(title: text.t("overtimeMultiplierRow"), isLast: isLast) {
            Stepper(
                value: Binding(
                    get: { OvertimePayChoices.tenths(multiplier) },
                    set: { multiplier = OvertimePayChoices.multiplier(tenths: $0) }
                ),
                in: OvertimePayChoices.customTenths
            ) {
                Text(text.multiplierLabel(multiplier))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .accessibilityLabel(text.t("overtimeMultiplierRow"))
            .accessibilityValue(text.multiplierLabel(multiplier))
        }
    }
}
