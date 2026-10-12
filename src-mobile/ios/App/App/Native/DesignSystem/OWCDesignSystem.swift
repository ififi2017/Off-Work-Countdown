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

    // Life stages: warm childhood, cyan school, indigo work (the same indigo
    // as work hours everywhere in Records) and green after retirement.
    static let lifeChildhood = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.73, blue: 0.31, alpha: 1)
            : UIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
    })
    static let lifeStudy = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.78, blue: 0.88, alpha: 1)
            : UIColor(red: 0.19, green: 0.69, blue: 0.78, alpha: 1)
    })
    static let lifeWork = Color(uiColor: .systemIndigo)
    static let lifeRetirement = Color(uiColor: .systemGreen)
    static let lifeUnset = Color(uiColor: .tertiarySystemFill)

    static let recordsWork = Color(uiColor: .systemIndigo)
    static let recordsOvertime = Color(uiColor: .systemOrange)
    static let recordsBreak = Color(uiColor: UIColor { traits in
        UIColor.systemIndigo.resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.45 : 0.38)
    })
    static let recordsSleep = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1)
            : UIColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1)
    })
    static let recordsFree = Color(uiColor: .systemGreen)
    static let recordsUnclassified = Color(uiColor: .systemGray2)
    /// A public holiday's rest days. Text-weight green in light mode so a
    /// 9 pt holiday name stays readable on white.
    static let recordsHoliday = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
            : UIColor(red: 0.14, green: 0.54, blue: 0.24, alpha: 1)
    })

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
