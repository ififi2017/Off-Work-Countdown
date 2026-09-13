import SwiftUI
import UIKit

enum OWCBrand {
    static let shortName = "DoneAt"
}

enum OWCDesign {
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let primary = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator).opacity(0.55)
    static let control = Color(uiColor: .tertiarySystemFill)
    static let orange = Color(red: 0.976, green: 0.451, blue: 0.086)
    static let orangeDeep = Color(red: 0.918, green: 0.345, blue: 0.047)
    static let brandPlum = Color(red: 0.169, green: 0.098, blue: 0.208)
    static let brandCream = Color(red: 1.0, green: 0.945, blue: 0.847)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.53, blue: 0.18, alpha: 1)
            : UIColor(red: 0.95, green: 0.35, blue: 0.04, alpha: 1)
    })
    static let warning = Color(uiColor: .systemOrange)

    static let lifeChildhood = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.72, blue: 0.86, alpha: 1)
            : UIColor(red: 0.45, green: 0.58, blue: 0.76, alpha: 1)
    })
    static let lifeStudy = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.78, blue: 0.68, alpha: 1)
            : UIColor(red: 0.32, green: 0.58, blue: 0.50, alpha: 1)
    })
    static let lifeWork = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.64, blue: 0.38, alpha: 1)
            : UIColor(red: 0.72, green: 0.48, blue: 0.20, alpha: 1)
    })
    static let lifeRetirement = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.70, green: 0.68, blue: 0.78, alpha: 1)
            : UIColor(red: 0.52, green: 0.50, blue: 0.62, alpha: 1)
    })
    static let lifeUnset = Color(uiColor: .tertiarySystemFill)

    static let recordsWork = Color(uiColor: .systemIndigo)
    static let recordsOvertime = Color(uiColor: .systemOrange)
    static let recordsBreak = Color(uiColor: .systemTeal)
    static let recordsSleep = Color(uiColor: .systemBlue)
    static let recordsFree = Color(uiColor: .systemPurple)
    static let recordsUnclassified = Color(uiColor: .systemGray2)

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let rowHeight: CGFloat = 52
    static let pageInset: CGFloat = 16
    static let contentInset: CGFloat = 20
    static let rootControlInset: CGFloat = pageInset - 5
    static let rootHeaderHeight: CGFloat = 44
    static let rootHeaderTopInset: CGFloat = 0
    static let heroGap: CGFloat = 26
    static let sectionGap: CGFloat = 22
    static let detailBottomInset: CGFloat = 24
}

enum OWCText {
    /// Keeps a clock range left-to-right inside Arabic or Hebrew layout.
    static func ltrRange(_ from: String, _ to: String) -> String {
        "\u{2066}\(from) – \(to)\u{2069}"
    }
}
