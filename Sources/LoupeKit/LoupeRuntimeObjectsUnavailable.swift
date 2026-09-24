import Foundation
import LoupeCore

#if !(((canImport(UIKit) && !os(watchOS)) || canImport(AppKit)) && canImport(ObjectiveC))
@MainActor
extension LoupeRuntime {
    nonisolated public func runtimeObjectClasses(
        matching: String? = nil,
        limit: Int = 100
    ) -> LoupeRuntimeObjectClassList {
        LoupeRuntimeObjectClassList(
            matching: matching,
            totalCount: 0,
            returnedCount: 0,
            classes: []
        )
    }

    nonisolated public func runtimeObjectDescription(className: String) throws -> LoupeRuntimeObjectDescription {
        throw LoupeRuntimeObjectError.unavailable("Objective-C runtime inspection is unavailable on this platform")
    }
}

public enum LoupeRuntimeObjectError: Error, CustomStringConvertible {
    case unavailable(String)

    public var description: String {
        switch self {
        case let .unavailable(message):
            return message
        }
    }
}
#endif
