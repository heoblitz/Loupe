#if os(iOS)
import Darwin
import Foundation
import LoupeCore
import ObjectiveC
import SwiftUI
import UIKit

@MainActor
func loupeSwiftUITouchDebugNodes(in view: UIView) -> [LoupeSwiftUITouchDebugNode]? {
    // Verify the actual hosting class, including subclasses. The generic
    // content is never accessed: this non-content API reads the live view graph.
    var current: AnyClass? = type(of: view)
    var isHost = false
    while let type = current {
        if String(reflecting: type).hasPrefix("SwiftUI._UIHostingView<") {
            isHost = true
            break
        }
        current = class_getSuperclass(type)
    }
    guard isHost else { return nil }
    let proof = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("loupe-touch-scope-proof.txt")
    func mark(_ value: String) { try? Data("\(Date().timeIntervalSince1970) \(value)".utf8).write(to: proof) }
    mark("host: \(String(reflecting: type(of: view)))")
    let host = unsafeBitCast(view, to: _UIHostingView<AnyView>.self)
    // View debug traversal can evaluate main-thread graph attributes. It must
    // hold SwiftUI's update scope, including when called from the main actor.
    // Resolve the no-argument Swift entry points so an unavailable private ABI
    // omits debug declarations instead of calling an incompatible function.
    typealias UpdateFunction = @convention(thin) () -> Void
    // iOS 27 renamed Update to ViewGraphHostUpdate. Resolve a complete pair
    // from one ABI so begin/end always operate on the same update scope.
    let scope = ["$s7SwiftUI19ViewGraphHostUpdateV", "$s7SwiftUI6UpdateO"].lazy.compactMap {
        prefix -> (UpdateFunction, UpdateFunction)? in
        guard let begin = dlsym(UnsafeMutableRawPointer(bitPattern: -2), prefix + "5beginyyFZ"),
              let end = dlsym(UnsafeMutableRawPointer(bitPattern: -2), prefix + "3endyyFZ") else { return nil }
        mark("resolved scope: " + prefix)
        return (unsafeBitCast(begin, to: UpdateFunction.self), unsafeBitCast(end, to: UpdateFunction.self))
    }.first
    guard let (begin, end) = scope else { mark("missing update scope"); return nil }
    let roots = {
        mark("before begin")
        begin()
        mark("before graph")
        defer { end() }
        return host._viewDebugData()
    }()
    mark("graph returned \(roots.count) roots")
    var remainingNodes = 4096
    var remainingAttributes = 65_536
    func encode(_ node: _ViewDebug.Data, depth: Int) -> LoupeSwiftUITouchDebugNode? {
        guard depth < 128, remainingNodes > 0 else { return nil }
        remainingNodes -= 1
        let fields = Array(Mirror(reflecting: node).children.prefix(8))
        // Read the stored Swift collections, without bridging unrelated fields
        // or evaluating fields after the matching collection has been found.
        guard let properties = fields.lazy.compactMap({ loupeExactDebugValue($0.value, as: [_ViewDebug.Property: Any].self) }).first,
              let children = fields.lazy.compactMap({ loupeExactDebugValue($0.value, as: [_ViewDebug.Data].self) }).first else { return nil }
        let typeName = (properties[.type] as? Any.Type).map {
            _typeName($0, qualified: true).replacingOccurrences(of: "SwiftUICore.", with: "SwiftUI.")
        } ?? ""
        var value: [String: Any] = [:]
        // Full SwiftUI serialization recursively formats every retained value,
        // including UIKit representables. Touch discovery needs only these
        // concrete modifier fields and text labels, not the complete graph.
        if let stored = properties[.value], loupeNeedsTouchDebugValue(typeName: typeName) {
            value = loupeSelectiveDebugAttribute(stored, remaining: &remainingAttributes)
        }
        let frame: LoupeRect?
        if let position = properties[.position] as? CGPoint,
           let size = properties[.size] as? CGSize,
           position.x.isFinite, position.y.isFinite,
           size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
            frame = LoupeRect(x: Double(position.x), y: Double(position.y), width: Double(size.width), height: Double(size.height))
        } else { frame = nil }
        return .init(typeName: typeName, value: value, frame: frame,
                     children: children.compactMap { encode($0, depth: depth + 1) })
    }
    let compact = roots.compactMap { encode($0, depth: 0) }
    mark("encoded \(compact.count) roots")
    return compact
}
#endif
