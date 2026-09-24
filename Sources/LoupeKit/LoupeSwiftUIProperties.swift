import Foundation
import LoupeCore

func loupeSwiftUIProperties(
    backingTypeName: String,
    frameworkBundleIdentifier: String?,
    viewController: String? = nil,
    customMetadata: [String: LoupeMetadataValue] = [:],
    privateSummary: @autoclosure () -> LoupeSwiftUIPrivateSummary? = nil
) -> LoupeSwiftUIProperties? {
    var evidence: [String] = []

    let isMarkedProbe = boolMetadata("loupe.swiftUI", from: customMetadata)
    if isMarkedProbe {
        evidence.append("loupe.swiftUI")
    }

    let isSwiftUIFramework = frameworkBundleIdentifier.map(isSwiftUIFrameworkIdentifier) ?? false
    if isSwiftUIFramework {
        evidence.append("frameworkBundleIdentifier")
    }

    let backingHasSignal = containsSwiftUIRuntimeSignal(backingTypeName)
    if backingHasSignal {
        evidence.append("backingTypeName")
    }

    let controllerHasSignal = viewController.map(containsSwiftUIRuntimeSignal) ?? false
    if controllerHasSignal {
        evidence.append("viewController")
    }

    guard !evidence.isEmpty else {
        return nil
    }

    let origin = swiftUINodeOrigin(
        isMarkedProbe: isMarkedProbe,
        backingTypeName: backingTypeName,
        viewController: viewController,
        isSwiftUIFramework: isSwiftUIFramework
    )
    let hostSummary: LoupeSwiftUIPrivateSummary?
    if origin == "host" {
        // A snapshot visits every native view, so private reflection belongs only to confirmed hosts.
        hostSummary = privateSummary()
    } else {
        hostSummary = nil
    }

    if hostSummary != nil {
        evidence.append("privateReflection")
    }

    return LoupeSwiftUIProperties(
        origin: origin,
        backingTypeName: backingTypeName,
        viewController: viewController,
        rootTypeName: hostSummary?.rootTypeName,
        properties: hostSummary?.properties ?? [],
        evidence: evidence
    )
}

func loupeSwiftUISemanticProperties(
    backingTypeName: String,
    hostTypeName: String,
    viewController: String? = nil,
    evidence: [String] = ["nativeAccessibility"]
) -> LoupeSwiftUIProperties {
    LoupeSwiftUIProperties(
        origin: "rendered",
        backingTypeName: backingTypeName,
        viewController: viewController,
        evidence: evidence + ["host:\(hostTypeName)"]
    )
}

func loupeSwiftUISemanticTypeName(role: String?, traits: [String]) -> String {
    if let role {
        switch role {
        case "button":
            return "SwiftUI.Button"
        case "image":
            return "SwiftUI.Image"
        case "link":
            return "SwiftUI.Link"
        case "searchField":
            return "SwiftUI.TextField"
        case "staticText":
            return "SwiftUI.Text"
        case "adjustable":
            return "SwiftUI.Adjustable"
        default:
            break
        }
    }
    if traits.contains("header") {
        return "SwiftUI.Text"
    }
    return "SwiftUI.AccessibilityElement"
}

func loupeSwiftUISemanticSignature(for node: LoupeNode) -> String {
    [
        node.testID,
        node.role,
        node.label,
        node.value,
        node.frame.map { "\($0.x),\($0.y),\($0.width),\($0.height)" },
    ]
    .compactMap(\.self)
    .joined(separator: "|")
}

private func swiftUINodeOrigin(
    isMarkedProbe: Bool,
    backingTypeName: String,
    viewController: String?,
    isSwiftUIFramework: Bool
) -> String {
    if isMarkedProbe {
        return "probe"
    }
    if containsSwiftUIHostingSignal(backingTypeName) || viewController.map(containsSwiftUIHostingSignal) == true {
        return "host"
    }
    if isSwiftUIFramework {
        return "rendered"
    }
    return "rendered"
}

private func boolMetadata(_ key: String, from metadata: [String: LoupeMetadataValue]) -> Bool {
    guard case let .bool(value)? = metadata[key] else {
        return false
    }
    return value
}

private func isSwiftUIFrameworkIdentifier(_ identifier: String) -> Bool {
    identifier == "com.apple.SwiftUI" || identifier == "com.apple.SwiftUICore"
}

private func containsSwiftUIRuntimeSignal(_ value: String) -> Bool {
    value.localizedCaseInsensitiveContains("SwiftUI")
        || containsSwiftUIHostingSignal(value)
        || value.localizedCaseInsensitiveContains("PlatformViewHost")
}

private func containsSwiftUIHostingSignal(_ value: String) -> Bool {
    value.localizedCaseInsensitiveContains("HostingController")
        || value.localizedCaseInsensitiveContains("HostingView")
        || value.localizedCaseInsensitiveContains("CellHostingView")
        || value.localizedCaseInsensitiveContains("UIHosting")
        || value.localizedCaseInsensitiveContains("NSHosting")
}
