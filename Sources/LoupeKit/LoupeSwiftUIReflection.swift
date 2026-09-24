import Foundation
import LoupeCore

struct LoupeSwiftUIPrivateSummary: Equatable {
    var rootTypeName: String?
    var properties: [LoupeSwiftUIProperty]
    var evidence: [String]
}

func loupeSwiftUIPrivateSummary(
    from hostObject: AnyObject,
    maxDepth: Int = 10,
    maxProperties: Int = 16
) -> LoupeSwiftUIPrivateSummary? {
    var builder = LoupeSwiftUIPrivateSummaryBuilder(maxDepth: maxDepth, maxProperties: maxProperties)
    return builder.build(from: hostObject)
}

private struct LoupeSwiftUIPrivateSummaryBuilder {
    var maxDepth: Int
    var maxProperties: Int
    private var visitedObjects: Set<ObjectIdentifier> = []
    private var properties: [LoupeSwiftUIProperty] = []
    private var seenPropertyNames: Set<String> = []
    private var rootTypeName: String?

    init(maxDepth: Int, maxProperties: Int) {
        self.maxDepth = maxDepth
        self.maxProperties = maxProperties
    }

    mutating func build(from hostObject: AnyObject) -> LoupeSwiftUIPrivateSummary? {
        visit(hostObject, propertyName: nil, depth: 0)

        guard rootTypeName != nil else {
            return nil
        }

        return LoupeSwiftUIPrivateSummary(
            rootTypeName: rootTypeName,
            properties: properties,
            evidence: ["privateReflection"]
        )
    }

    private mutating func visit(_ value: Any, propertyName: String?, depth: Int) {
        guard depth <= maxDepth, rootTypeName == nil else {
            return
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class, let object = value as AnyObject? {
            let id = ObjectIdentifier(object)
            guard visitedObjects.insert(id).inserted else {
                return
            }
        }

        let typeName = displayTypeName(for: value)
        if rootTypeName == nil, isUserAuthoredSwiftUIViewType(typeName) {
            rootTypeName = swiftUILeafTypeName(typeName)
            properties.removeAll()
            seenPropertyNames.removeAll()
            collectProperties(from: value)
            return
        }

        for (index, child) in mirror.children.enumerated().prefix(24) {
            visit(
                child.value,
                propertyName: normalizedPropertyName(child.label),
                depth: depth + 1 + index / 24
            )
            guard rootTypeName == nil else {
                return
            }
        }
    }

    private mutating func collectProperties(from value: Any) {
        for child in Mirror(reflecting: value).children {
            collectProperty(
                name: normalizedPropertyName(child.label),
                typeName: displayTypeName(for: child.value),
                value: child.value
            )
        }
    }

    private mutating func collectProperty(name: String?, typeName: String, value: Any) {
        guard properties.count < maxProperties,
              let name,
              !seenPropertyNames.contains(name),
              let primitive = firstPrimitive(in: value, depth: 0) else {
            return
        }

        seenPropertyNames.insert(name)
        properties.append(
            LoupeSwiftUIProperty(
                name: name,
                typeName: primitive.typeName,
                value: primitive.value,
                evidence: ["privateReflection", "propertyName"]
            )
        )
    }

    private func firstPrimitive(in value: Any, depth: Int) -> (typeName: String, value: LoupeMetadataValue)? {
        guard depth <= 5 else {
            return nil
        }

        switch value {
        case let value as Bool:
            return ("Bool", .bool(value))
        case let value as Int:
            return ("Int", .int(value))
        case let value as Double:
            guard value.isFinite else {
                return nil
            }
            return ("Double", .double(value))
        case let value as Float:
            guard value.isFinite else {
                return nil
            }
            return ("Float", .double(Double(value)))
        case let value as CGFloat:
            guard value.isFinite else {
                return nil
            }
            return ("CGFloat", .double(Double(value)))
        case let value as String:
            return value.nilIfBlank.map { ("String", .string($0)) }
        default:
            break
        }

        for child in Mirror(reflecting: value).children {
            if let primitive = firstPrimitive(in: child.value, depth: depth + 1) {
                return primitive
            }
        }
        return nil
    }
}

private func displayTypeName(for value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    return String(reflecting: mirror.subjectType)
}

private func isUserAuthoredSwiftUIViewType(_ typeName: String) -> Bool {
    let leaf = swiftUILeafTypeName(typeName)
    guard leaf.hasSuffix("View") || leaf.hasSuffix("Screen") || leaf.hasSuffix("Route") else {
        return false
    }
    guard !leaf.hasPrefix("UI"),
          !leaf.hasPrefix("NS"),
          !leaf.hasPrefix("_"),
          !leaf.contains("LoupeFallbackProbeView") else {
        return false
    }
    let lowercased = typeName.lowercased()
    return !lowercased.contains("swiftui.")
        && !lowercased.contains("swiftuicore.")
        && !lowercased.contains("uikit.")
        && !lowercased.contains("appkit.")
        && !lowercased.contains("foundation.")
        && !lowercased.contains("objectivec.")
}

private func swiftUILeafTypeName(_ typeName: String) -> String {
    let trimmed = typeName
        .replacingOccurrences(of: "SwiftUI.", with: "")
        .replacingOccurrences(of: "SwiftUICore.", with: "")
    let leaf = trimmed
        .split(separator: ".")
        .last
        .map(String.init) ?? trimmed
    return leaf.split(separator: "<").first.map(String.init) ?? leaf
}

private func normalizedPropertyName(_ name: String?) -> String? {
    guard let name = name?.nilIfBlank else {
        return nil
    }
    return name
        .replacingOccurrences(of: "$__lazy_storage_$_", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        .nilIfBlank
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
