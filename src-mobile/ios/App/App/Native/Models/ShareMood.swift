import Foundation

enum ShareMood: String, CaseIterable, Identifiable {
    case happy = "1f604"
    case relaxed = "1f60c"
    case tired = "1f62b"
    case crying = "1f62d"
    case firedUp = "1f525"
    case excited = "1f929"
    case celebrating = "1f973"
    case coffee = "2615"

    var id: String { rawValue }

    /// Rendered at runtime by the system emoji font. Keeping the stable code
    /// point as the raw value avoids changing picker identity or saved state.
    var emoji: String {
        switch self {
        case .happy: "😄"
        case .relaxed: "😌"
        case .tired: "😫"
        case .crying: "😭"
        case .firedUp: "🔥"
        case .excited: "🤩"
        case .celebrating: "🥳"
        case .coffee: "☕️"
        }
    }

    /// Matches the mood keys the Web share dialog already ships in all 19
    /// locales, so the picker reads out properly under VoiceOver.
    var labelKey: String {
        switch self {
        case .happy: "moodHappy"
        case .relaxed: "moodRelaxed"
        case .tired: "moodTired"
        case .crying: "moodCounting"
        case .firedUp: "moodFiredUp"
        case .excited: "moodExcited"
        case .celebrating: "moodCelebrating"
        case .coffee: "moodCoffee"
        }
    }
}

