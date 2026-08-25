import SwiftUI

enum OWCMotion {
    static let reduced = Animation.easeOut(duration: 0.16)
    static let countdownTick = Animation.linear(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.14)
    static let selection = Animation.snappy(duration: 0.18)
    static let navigation = Animation.snappy(duration: 0.28)
    static let phase = Animation.smooth(duration: 0.28)
}
