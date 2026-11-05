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

/// This overtime's pay: paid or not, and at what multiple of the usual rate.
/// The overtime sheet and the Records day editor share it.
struct OvertimePayCard: View {
    let text: AppText
    @Binding var isPaid: Bool
    @Binding var multiplier: Double
    @Binding var showsCustom: Bool

    var body: some View {
        OWCGroupCard {
            OWCRow(title: text.t("overtimePayRow"), isLast: !isPaid) {
                Picker(text.t("overtimePayRow"), selection: $isPaid) {
                    Text(text.t("overtimePayPaid")).tag(true)
                    Text(text.t("overtimePayUnpaid")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
            }
            if isPaid {
                OWCRow(title: text.t("overtimeMultiplierRow"), isLast: !showsCustom) {
                    HStack(spacing: 6) {
                        Text(text.multiplierLabel(multiplier))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                }
                .owcRowMenu(accessibilityLabel: "\(text.t("overtimeMultiplierRow")), \(text.multiplierLabel(multiplier))") {
                    Picker(text.t("overtimeMultiplierRow"), selection: Binding(
                        get: { showsCustom ? OvertimePayChoices.customTag : OvertimePayChoices.tenths(multiplier) },
                        set: { tag in
                            if tag == OvertimePayChoices.customTag {
                                showsCustom = true
                            } else {
                                showsCustom = false
                                multiplier = OvertimePayChoices.multiplier(tenths: tag)
                            }
                        }
                    )) {
                        ForEach(OvertimePayChoices.presets, id: \.self) { preset in
                            Text(text.multiplierLabel(preset)).tag(OvertimePayChoices.tenths(preset))
                        }
                        Text(text.t("overtimeMultiplierCustom")).tag(OvertimePayChoices.customTag)
                    }
                }
                if showsCustom {
                    OvertimeMultiplierStepperRow(text: text, multiplier: $multiplier, isLast: true)
                }
            }
        }
    }
}
