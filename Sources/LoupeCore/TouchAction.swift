import Foundation

/// Observed touch contracts, distinct from Apple accessibility callbacks.
public enum LoupeTouchAction: String, Codable, Equatable, Sendable {
    case tap
    case doubleTap = "double-tap"
    case longPress = "long-press"
    case drag
    case swipe
    case input
}

public extension LoupeTouchAction {
    static var allObservedOrder: [Self] { [.tap, .doubleTap, .longPress, .drag, .swipe, .input] }
}
