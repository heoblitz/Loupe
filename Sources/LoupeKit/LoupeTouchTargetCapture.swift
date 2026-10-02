import Foundation
import LoupeCore

// Keep the live debug graph in Swift storage. Encoding it as Any/JSON boxes
// every node and scalar even though discovery consumes only a few modifiers.
struct LoupeSwiftUITouchDebugNode {
    var typeName: String
    var value: [String: Any]
    var frame: LoupeRect?
    var children: [LoupeSwiftUITouchDebugNode]
}

struct LoupeSwiftUITouchDeclaration {
    var testID: String?
    var label: String?
    var frame: LoupeRect
    var actions: [LoupeTouchAction]
}

struct LoupeSwiftUITouchDeclarations {
    var targets: [LoupeSwiftUITouchDeclaration] = []
    var anchors: [String: LoupeRect] = [:]

    /// Read only concrete modifier nodes, never a parent generic type whose
    /// name merely contains gestures belonging to one of its descendants.
    static func parse(_ roots: [LoupeSwiftUITouchDebugNode]) -> Self {
        var result = Self()
        var remaining = 4096
        func visit(_ node: LoupeSwiftUITouchDebugNode, frame: LoupeRect?, identifier: String?, enabled: Bool, depth: Int) {
            guard depth < 128, remaining > 0 else { return }
            remaining -= 1
            let type = node.typeName
            let value = node.value
            let enabled = enabled && !(type.hasSuffix("._AllowsHitTestingModifier") &&
                (value["subattributes"] as? [[String: Any]])?.contains(where: {
                    $0["name"] as? String == "allowsHitTesting" && $0["value"] as? Bool == false
                }) == true)
            let frame = node.frame ?? frame
            let ownID = find(value, type: "SwiftUI.AccessibilityIdentifierStorage")
                .flatMap { string($0, name: "rawValue") }
            let identifier = ownID ?? identifier
            if let ownID, let frame { result.anchors[ownID] = frame }
            let children = node.children
            if enabled, type.hasPrefix("SwiftUI.AddGestureModifier<"), let frame {
                let mask = find(value, type: "SwiftUI.GestureMask").flatMap { number($0, name: "rawValue") }
                let hasHandler = type.contains("SwiftUI._EndedGesture<") || type.contains("SwiftUI._ChangedGesture<")
                    || type.contains("SwiftUI.GestureStateGesture<")
                var actions: [LoupeTouchAction] = []
                if hasHandler, let mask, mask.isFinite, (0...3).contains(mask), mask.rounded() == mask,
                   Int(mask) & 1 != 0, !type.contains("PrimitiveButtonGesture") {
                    if let tap = find(value, type: "SwiftUI.TapGesture"), let count = number(tap, name: "count") {
                        if count == 1 { actions.append(.tap) }
                        if count == 2 { actions.append(.doubleTap) }
                    }
                    if find(value, type: "SwiftUI.LongPressGesture") != nil { actions.append(.longPress) }
                    if find(value, type: "SwiftUI.DragGesture") != nil { actions.append(.drag) }
                }
                if !actions.isEmpty {
                    result.targets.append(.init(testID: identifier, label: renderedText(children), frame: frame, actions: actions))
                }
            }
            for child in children { visit(child, frame: frame, identifier: identifier, enabled: enabled, depth: depth + 1) }
        }
        for root in roots { visit(root, frame: nil, identifier: nil, enabled: true, depth: 0) }
        return result
    }

    private static func find(_ attribute: [String: Any], type: String, depth: Int = 0) -> [String: Any]? {
        guard depth < 16 else { return nil }
        if attribute["type"] as? String == type { return attribute }
        for child in attribute["subattributes"] as? [[String: Any]] ?? [] {
            if let match = find(child, type: type, depth: depth + 1) { return match }
        }
        return nil
    }

    private static func number(_ attribute: [String: Any], name: String) -> Double? {
        (attribute["subattributes"] as? [[String: Any]])?.first { $0["name"] as? String == name }?["value"].flatMap(loupeTouchDebugNumber)
    }

    private static func string(_ attribute: [String: Any], name: String, depth: Int = 0) -> String? {
        guard depth < 16 else { return nil }
        if attribute["name"] as? String == name, let value = attribute["value"] as? String { return value }
        for child in attribute["subattributes"] as? [[String: Any]] ?? [] {
            if let value = string(child, name: name, depth: depth + 1) { return value }
        }
        return nil
    }

    private static func renderedText(_ children: [LoupeSwiftUITouchDebugNode], depth: Int = 0) -> String? {
        guard depth < 24 else { return nil }
        for child in children {
            if child.typeName == "SwiftUI.Text",
               let label = string(child.value, name: "key") ?? string(child.value, name: "verbatim") { return label }
            if let label = renderedText(child.children, depth: depth + 1) { return label }
        }
        return nil
    }

}

#if os(iOS)
import UIKit
import LoupeSyntheticEvents

@MainActor
func loupeTouchActions(for view: UIView) -> [LoupeTouchAction] {
    guard view.window != nil else { return [] }
    var ancestor: UIView? = view
    while let current = ancestor {
        guard current.isUserInteractionEnabled, !current.isHidden, current.alpha > 0.01 else { return [] }
        ancestor = current.superview
    }
    if let control = view as? UIControl, !control.isEnabled { return [] }
    if let field = view as? UITextField { return field.isEnabled ? [.tap, .input] : [] }
    if let text = view as? UITextView { return text.isEditable ? [.tap, .input] : [] }
    if let scroll = view as? UIScrollView {
        guard scroll.isScrollEnabled,
              scroll.contentSize.width + scroll.adjustedContentInset.left + scroll.adjustedContentInset.right > scroll.bounds.width + 1
                || scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height + 1 else { return [] }
        return [.drag, .swipe]
    }
    if let button = view as? UIButton {
        return !button.allControlEvents.isEmpty || button.menu != nil ? [.tap] : []
    }
    if let control = view as? UIControl {
        return !control.allControlEvents.isEmpty || view is UISwitch || view is UISlider
            || view is UIStepper || view is UISegmentedControl || view is UIPageControl ? [.tap] : []
    }
    let nativeType = String(describing: type(of: view))
    let bundle = Bundle(for: type(of: view)).bundleIdentifier ?? ""
    guard nativeType == "UIView" || nativeType == "UILabel" || nativeType == "UIImageView"
            || !bundle.hasPrefix("com.apple.UIKit") else { return [] }
    var actions: [LoupeTouchAction] = []
    for gesture in view.gestureRecognizers ?? [] where gesture.isEnabled && LoupeGestureHasTargets(gesture) {
        if let tap = gesture as? UITapGestureRecognizer, tap.numberOfTouchesRequired == 1 {
            if tap.numberOfTapsRequired == 1 { actions.append(.tap) }
            if tap.numberOfTapsRequired == 2 { actions.append(.doubleTap) }
        } else if let hold = gesture as? UILongPressGestureRecognizer, hold.numberOfTouchesRequired == 1 {
            actions.append(.longPress)
        } else if let pan = gesture as? UIPanGestureRecognizer, pan.minimumNumberOfTouches == 1 {
            actions.append(.drag)
        } else if let swipe = gesture as? UISwipeGestureRecognizer, swipe.numberOfTouchesRequired == 1 {
            actions.append(.swipe)
        }
    }
    return LoupeTouchAction.allObservedOrder.filter(actions.contains)
}

@MainActor
func loupeTouchable(_ frame: LoupeRect, in view: UIView) -> Bool {
    guard let window = view.window else { return false }
    let point = CGPoint(x: frame.center.x, y: frame.center.y)
    guard let hit = window.hitTest(window.convert(point, from: nil), with: nil) else { return false }
    return hit === view || hit.isDescendant(of: view)
}

@MainActor
func loupeSwiftUITouchDeclarations(in view: UIView, elements: @MainActor () -> [NSObject]) -> [LoupeSwiftUITouchDeclaration] {
    LoupeCaptureDiagnostics.record("hosting.debug-data.begin", object: view)
    guard let nodes = loupeSwiftUITouchDebugNodes(in: view) else { return [] }
    LoupeCaptureDiagnostics.record("hosting.debug-data.end", object: view)
    let declarations = LoupeSwiftUITouchDeclarations.parse(nodes)
    LoupeCaptureDiagnostics.record("hosting.debug-parse.end", object: view)
    guard !declarations.targets.isEmpty else { return [] }
    var native: [String: LoupeRect] = [:]
    var disabledIDs = Set<String>()
    LoupeCaptureDiagnostics.record("hosting.anchors.begin", object: view)
    for element in elements() {
        guard let id = accessibilityIdentifier(for: element) else { continue }
        if element.accessibilityTraits.contains(.notEnabled) { disabledIDs.insert(id); continue }
        let frame = element.accessibilityFrame
        guard !frame.isEmpty else { continue }
        native[id] = LoupeRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }
    LoupeCaptureDiagnostics.record("hosting.anchors.end", object: view)
    // Debug positions can be relative to a scroll content coordinate space.
    // Anchor them against native geometry; require agreement rather than guessing.
    let offsets = declarations.anchors.compactMap { id, frame -> LoupePoint? in
        guard let live = native[id], abs(live.width - frame.width) < 1, abs(live.height - frame.height) < 1 else { return nil }
        return LoupePoint(x: live.x - frame.x, y: live.y - frame.y)
    }
    let offset = offsets.count >= 2 && offsets.allSatisfy({ abs($0.x - offsets[0].x) < 1 && abs($0.y - offsets[0].y) < 1 }) ? offsets[0] : nil
    return declarations.targets.compactMap { target in
        var target = target
        if let id = target.testID, disabledIDs.contains(id) { return nil }
        if let id = target.testID, let live = native[id] { target.frame = live }
        else if let offset { target.frame.x += offset.x; target.frame.y += offset.y }
        else { return nil }
        guard loupeTouchable(target.frame, in: view) else { return nil }
        return target
    }
}
#endif
