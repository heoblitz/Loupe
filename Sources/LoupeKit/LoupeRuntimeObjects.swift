import Foundation
import LoupeCore

#if ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit)) && canImport(ObjectiveC)
import ObjectiveC

@MainActor
extension LoupeRuntime {
    nonisolated public func runtimeObjectClasses(
        matching: String? = nil,
        limit: Int = 100
    ) -> LoupeRuntimeObjectClassList {
        let allClasses = objcRuntimeClassSummaries()
        let filtered = matching.map { query in
            allClasses.filter { $0.name.localizedCaseInsensitiveContains(query) }
        } ?? allClasses
        let boundedLimit = max(1, min(limit, 1_000))
        let classes = Array(filtered.prefix(boundedLimit))
        return LoupeRuntimeObjectClassList(
            matching: matching,
            totalCount: filtered.count,
            returnedCount: classes.count,
            classes: classes
        )
    }

    nonisolated public func runtimeObjectDescription(className: String) throws -> LoupeRuntimeObjectDescription {
        guard let cls = NSClassFromString(className) ?? objc_getClass(className) as? AnyClass else {
            throw LoupeRuntimeObjectError.classNotFound(className)
        }

        return LoupeRuntimeObjectDescription(
            name: String(cString: class_getName(cls)),
            superclass: superclassName(for: cls),
            ivars: ivarMembers(for: cls),
            properties: propertyMembers(for: cls)
        )
    }

    nonisolated private func objcRuntimeClassSummaries() -> [LoupeRuntimeObjectClassSummary] {
        let capacity = Int(objc_getClassList(nil, 0))
        guard capacity > 0 else { return [] }
        let classes = UnsafeMutablePointer<AnyClass?>.allocate(capacity: capacity)
        defer { classes.deallocate() }
        // Class registration can race the count query. The runtime returns the
        // total class count even when the supplied buffer is smaller.
        let count = min(capacity, Int(objc_getClassList(AutoreleasingUnsafeMutablePointer(classes), Int32(capacity))))
        guard count > 0 else { return [] }

        return (0..<count)
            .compactMap { index -> LoupeRuntimeObjectClassSummary? in
                guard let cls = classes[index] else { return nil }
                return LoupeRuntimeObjectClassSummary(
                    name: String(cString: class_getName(cls)),
                    superclass: superclassName(for: cls)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated private func superclassName(for cls: AnyClass) -> String? {
        guard let superclass = class_getSuperclass(cls) else {
            return nil
        }
        return String(cString: class_getName(superclass))
    }

    nonisolated private func ivarMembers(for cls: AnyClass) -> [LoupeRuntimeObjectMember] {
        var count: UInt32 = 0
        guard let ivars = class_copyIvarList(cls, &count) else {
            return []
        }
        defer { free(ivars) }

        return (0..<Int(count)).compactMap { index in
            let ivar = ivars[index]
            guard let name = ivar_getName(ivar) else {
                return nil
            }
            return LoupeRuntimeObjectMember(
                name: String(cString: name),
                typeEncoding: ivar_getTypeEncoding(ivar).map { String(cString: $0) }
            )
        }
    }

    nonisolated private func propertyMembers(for cls: AnyClass) -> [LoupeRuntimeObjectMember] {
        var count: UInt32 = 0
        guard let properties = class_copyPropertyList(cls, &count) else {
            return []
        }
        defer { free(properties) }

        return (0..<Int(count)).map { index in
            let property = properties[index]
            return LoupeRuntimeObjectMember(
                name: String(cString: property_getName(property)),
                attributes: property_getAttributes(property).map { String(cString: $0) }
            )
        }
    }
}

public enum LoupeRuntimeObjectError: Error, CustomStringConvertible {
    case classNotFound(String)

    public var description: String {
        switch self {
        case let .classNotFound(name):
            return "Runtime class not found: \(name)"
        }
    }
}
#endif
