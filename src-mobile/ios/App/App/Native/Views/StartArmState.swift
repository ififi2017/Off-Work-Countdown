import Foundation

/// Whether the start button is waiting for a confirming second tap.
///
/// Starting a countdown on a day the schedule calls a rest day is nearly always
/// a mis-tap, so the first tap arms the button and the second one commits.
enum StartArmState: Equatable {
    case idle
    case armed
}
