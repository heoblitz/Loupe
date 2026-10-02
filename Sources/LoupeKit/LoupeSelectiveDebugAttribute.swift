import Foundation

func loupeExactDebugValue<Value>(_ value: Any, as: Value.Type) -> Value? {
    guard type(of: value) == Value.self else { return nil }
    return value as! Value
}

func loupeNeedsTouchDebugValue(typeName: String) -> Bool {
    typeName.hasPrefix("SwiftUI.AddGestureModifier<")
        || typeName.hasPrefix("SwiftUI.Accessibility")
        || typeName.hasPrefix("SwiftUI._Accessibility")
        || typeName == "SwiftUI._AllowsHitTestingModifier"
        || typeName == "SwiftUI.Text"
}

/// Encode stored scalar fields only, without invoking debug descriptions or
/// walking UIKit/AttributeGraph objects retained by SwiftUI values.
func loupeSelectiveDebugAttribute(
    _ value: Any, name: String? = nil, remaining: inout Int, depth: Int = 0
) -> [String: Any] {
    guard depth < 16, remaining > 0 else { return [:] }
    remaining -= 1
    let valueType = type(of: value)
    // Metatype formatting through String(reflecting:) still performs dynamic
    // printable-protocol lookup. Ask the runtime for the name directly.
    let typeName = _typeName(valueType, qualified: true).replacingOccurrences(of: "SwiftUICore.", with: "SwiftUI.")
    var result: [String: Any] = ["type": typeName]
    if let name { result["name"] = name }
    // A conditional NSNumber cast can run _ObjectiveCBridgeable on an arbitrary
    // Swift value. Read known scalars directly so observation never executes
    // user-defined bridge code or scans protocol conformances for each field.
    if valueType == String.self {
        let string = value as! String
        if string.utf8.prefix(4097).count <= 4096 { result["value"] = string }
    } else if let scalar = loupeDebugScalar(value, type: valueType) {
        result["value"] = scalar
    } else if valueType is NSNumber.Type {
        let number = value as! NSNumber
        if number.doubleValue.isFinite { result["value"] = number }
    } else if valueType is NSString.Type {
        let string = (value as! NSString) as String
        if string.utf8.prefix(4097).count <= 4096 { result["value"] = string }
    } else {
        let mirror = Mirror(reflecting: value)
        let runtimePrefixes = ["UIKit.", "Foundation.", "CoreFoundation.", "AttributeGraph.", "QuartzCore."]
        guard mirror.displayStyle != .class || !runtimePrefixes.contains(where: typeName.hasPrefix) else { return result }
        result["subattributes"] = mirror.children.prefix(24).map { child in
            loupeSelectiveDebugAttribute(child.value, name: child.label, remaining: &remaining, depth: depth + 1)
        }
    }
    return result
}

func loupeDebugScalar(_ value: Any, type: Any.Type) -> Any? {
    if type == Bool.self { return value as! Bool }
    if type == Int.self { return value as! Int }
    if type == Int8.self { return value as! Int8 }
    if type == Int16.self { return value as! Int16 }
    if type == Int32.self { return value as! Int32 }
    if type == Int64.self { return value as! Int64 }
    if type == UInt.self { return value as! UInt }
    if type == UInt8.self { return value as! UInt8 }
    if type == UInt16.self { return value as! UInt16 }
    if type == UInt32.self { return value as! UInt32 }
    if type == UInt64.self { return value as! UInt64 }
    if type == Double.self {
        let scalar = value as! Double
        return scalar.isFinite ? scalar : nil
    }
    if type == Float.self {
        let scalar = value as! Float
        return scalar.isFinite ? scalar : nil
    }
    if type == CGFloat.self {
        let scalar = value as! CGFloat
        return scalar.isFinite ? scalar : nil
    }
    return nil
}

func loupeTouchDebugNumber(_ value: Any) -> Double? {
    let type = type(of: value)
    guard let scalar = loupeDebugScalar(value, type: type) ?? (type is NSNumber.Type ? value : nil) else { return nil }
    return (scalar as? NSNumber)?.doubleValue
}
