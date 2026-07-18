import Foundation

public struct LoupeAccessibilityAction: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var customName: String?

    public init(name: String, customName: String? = nil) {
        self.name = name
        self.customName = customName
    }

    public static let activate = Self(name: "activate")
    public static let increment = Self(name: "increment")
    public static let decrement = Self(name: "decrement")
    public static let zoomIn = Self(name: "zoom-in")
    public static let zoomOut = Self(name: "zoom-out")
    public static let scrollRight = Self(name: "scroll-right")
    public static let scrollLeft = Self(name: "scroll-left")
    public static let scrollUp = Self(name: "scroll-up")
    public static let scrollDown = Self(name: "scroll-down")
    public static let scrollNext = Self(name: "scroll-next")
    public static let scrollPrevious = Self(name: "scroll-previous")
    public static let escape = Self(name: "escape")
    public static let magicTap = Self(name: "magic-tap")

    public static let press = Self(name: "press")
    public static let confirm = Self(name: "confirm")
    public static let pick = Self(name: "pick")
    public static let cancel = Self(name: "cancel")
    public static let raise = Self(name: "raise")
    public static let showMenu = Self(name: "show-menu")
    public static let delete = Self(name: "delete")
    public static let scrollToVisible = Self(name: "scroll-to-visible")
    public static let showAlternateUI = Self(name: "show-alternate-ui")
    public static let showDefaultUI = Self(name: "show-default-ui")

    public static func custom(_ name: String) -> Self {
        Self(name: "custom", customName: name)
    }

    public var commandName: String {
        guard name == "custom", let customName else { return name }
        return "custom:\(customName)"
    }

    public static func parse(_ raw: String) -> Self {
        let prefix = "custom:"
        if raw.lowercased().hasPrefix(prefix) {
            return .custom(String(raw.dropFirst(prefix.count)))
        }
        return Self(name: raw.lowercased())
    }
}

public struct LoupeAccessibilityTargetIdentity: Codable, Equatable {
    public var ref: String
    public var sourceRef: String
    public var testID: String?
    public var role: String?
    public var label: String?
    public var frame: LoupeRect?

    public init(
        ref: String,
        sourceRef: String,
        testID: String? = nil,
        role: String? = nil,
        label: String? = nil,
        frame: LoupeRect? = nil
    ) {
        self.ref = ref
        self.sourceRef = sourceRef
        self.testID = testID
        self.role = role
        self.label = label
        self.frame = frame
    }
}
