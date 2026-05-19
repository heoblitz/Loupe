import LoupeCore

package struct ActionScreen: Equatable {
    package var size: LoupeSize
    package var scale: Double

    package init(size: LoupeSize, scale: Double) {
        self.size = size
        self.scale = scale
    }
}

package enum ActionScreenResolver {
    package static func explicit(_ size: LoupeSize) -> ActionScreen? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        return ActionScreen(size: size, scale: 1)
    }

    package static func resolve(explicit: LoupeSize, fallback: LoupeScreen) -> ActionScreen {
        if let screen = self.explicit(explicit) {
            return screen
        }
        return ActionScreen(size: fallback.size, scale: fallback.scale)
    }
}
