import Foundation

public enum LoupeMutationSelectorKind: String, Codable, Equatable {
    case testID
    case ref
    case role
    case text
    case roleAndText
}

public struct LoupeMutationSelector: Codable, Equatable {
    public var kind: LoupeMutationSelectorKind
    public var value: String
    public var role: String?
    public var exact: Bool

    public init(kind: LoupeMutationSelectorKind, value: String, role: String? = nil, exact: Bool = true) {
        self.kind = kind
        self.value = value
        self.role = role
        self.exact = exact
    }
}

public enum LoupeMutationValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case color(LoupeColor)
    case point(LoupePoint)
    case size(LoupeSize)
    case rect(LoupeRect)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case bool
        case int
        case double
        case string
        case color
        case point
        case size
        case rect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .color:
            self = .color(try container.decode(LoupeColor.self, forKey: .value))
        case .point:
            self = .point(try container.decode(LoupePoint.self, forKey: .value))
        case .size:
            self = .size(try container.decode(LoupeSize.self, forKey: .value))
        case .rect:
            self = .rect(try container.decode(LoupeRect.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .bool(value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .int(value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .double(value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .color(value):
            try container.encode(ValueType.color, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .point(value):
            try container.encode(ValueType.point, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .size(value):
            try container.encode(ValueType.size, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .rect(value):
            try container.encode(ValueType.rect, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct LoupeMutationRequest: Codable, Equatable {
    public var selector: LoupeMutationSelector
    public var property: String
    public var value: LoupeMutationValue
    public var layout: Bool

    public init(
        selector: LoupeMutationSelector,
        property: String,
        value: LoupeMutationValue,
        layout: Bool = true
    ) {
        self.selector = selector
        self.property = property
        self.value = value
        self.layout = layout
    }
}

public struct LoupeMutationResponse: Codable, Equatable {
    public var property: String
    public var selector: LoupeMutationSelector
    public var value: LoupeMutationValue
    public var target: LoupeQueryResult
    public var before: LoupeNode
    public var after: LoupeNode
    public var hierarchy: LoupeMutationHierarchyContext?
    public var requested: LoupeMutationValue?
    public var effective: LoupeMutationValue?
    public var changed: Bool?
    public var warning: String?
    public var snapshotID: String

    public init(
        property: String,
        selector: LoupeMutationSelector,
        value: LoupeMutationValue,
        target: LoupeQueryResult,
        before: LoupeNode,
        after: LoupeNode,
        hierarchy: LoupeMutationHierarchyContext? = nil,
        requested: LoupeMutationValue? = nil,
        effective: LoupeMutationValue? = nil,
        changed: Bool? = nil,
        warning: String? = nil,
        snapshotID: String
    ) {
        self.property = property
        self.selector = selector
        self.value = value
        self.target = target
        self.before = before
        self.after = after
        self.hierarchy = hierarchy
        self.requested = requested
        self.effective = effective
        self.changed = changed
        self.warning = warning
        self.snapshotID = snapshotID
    }
}

public struct LoupeConstraintMutationRequest: Codable, Equatable {
    public var id: String
    public var constant: Double?
    public var priority: Double?
    public var isActive: Bool?
    public var layout: Bool

    public init(
        id: String,
        constant: Double? = nil,
        priority: Double? = nil,
        isActive: Bool? = nil,
        layout: Bool = true
    ) {
        self.id = id
        self.constant = constant
        self.priority = priority
        self.isActive = isActive
        self.layout = layout
    }
}

public struct LoupeConstraintMutationResponse: Codable, Equatable {
    public var id: String
    public var before: LoupeUILayoutConstraintProperties
    public var after: LoupeUILayoutConstraintProperties
    public var effective: LoupeUILayoutConstraintProperties
    public var requested: LoupeConstraintMutationRequest
    public var changed: Bool
    public var warning: String?
    public var snapshotID: String

    public init(
        id: String,
        before: LoupeUILayoutConstraintProperties,
        after: LoupeUILayoutConstraintProperties,
        effective: LoupeUILayoutConstraintProperties? = nil,
        requested: LoupeConstraintMutationRequest,
        changed: Bool,
        warning: String? = nil,
        snapshotID: String
    ) {
        self.id = id
        self.before = before
        self.after = after
        self.effective = effective ?? after
        self.requested = requested
        self.changed = changed
        self.warning = warning
        self.snapshotID = snapshotID
    }
}

public struct LoupeMutationCapability: Codable, Equatable {
    public var property: String
    public var aliases: [String]

    public init(property: String, aliases: [String]) {
        self.property = property
        self.aliases = aliases
    }
}

public struct LoupeMutationSourceCandidate: Codable, Equatable {
    public var path: String
    public var line: Int
    public var text: String

    public init(path: String, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }
}

public struct LoupeMutationNodeSummary: Codable, Equatable {
    public var ref: String
    public var typeName: String
    public var role: String?
    public var testID: String?
    public var text: String?
    public var frame: LoupeRect?

    public init(
        ref: String,
        typeName: String,
        role: String? = nil,
        testID: String? = nil,
        text: String? = nil,
        frame: LoupeRect? = nil
    ) {
        self.ref = ref
        self.typeName = typeName
        self.role = role
        self.testID = testID
        self.text = text
        self.frame = frame
    }
}

public struct LoupeMutationHierarchyContext: Codable, Equatable {
    public var target: LoupeMutationNodeSummary
    public var parent: LoupeMutationNodeSummary?
    public var siblings: [LoupeMutationNodeSummary]
    public var children: [LoupeMutationNodeSummary]

    public init(
        target: LoupeMutationNodeSummary,
        parent: LoupeMutationNodeSummary? = nil,
        siblings: [LoupeMutationNodeSummary] = [],
        children: [LoupeMutationNodeSummary] = []
    ) {
        self.target = target
        self.parent = parent
        self.siblings = siblings
        self.children = children
    }
}

public struct LoupeMutationReflection: Codable, Equatable {
    public var selector: LoupeMutationSelector
    public var property: String
    public var value: LoupeMutationValue
    public var targetType: String
    public var testID: String?
    public var before: LoupeMutationNodeSummary
    public var after: LoupeMutationNodeSummary
    public var targetMatchesHierarchy: Bool
    public var hierarchy: LoupeMutationHierarchyContext
    public var sourceCandidates: [LoupeMutationSourceCandidate]

    public init(
        selector: LoupeMutationSelector,
        property: String,
        value: LoupeMutationValue,
        targetType: String,
        testID: String?,
        before: LoupeMutationNodeSummary,
        after: LoupeMutationNodeSummary,
        targetMatchesHierarchy: Bool,
        hierarchy: LoupeMutationHierarchyContext,
        sourceCandidates: [LoupeMutationSourceCandidate]
    ) {
        self.selector = selector
        self.property = property
        self.value = value
        self.targetType = targetType
        self.testID = testID
        self.before = before
        self.after = after
        self.targetMatchesHierarchy = targetMatchesHierarchy
        self.hierarchy = hierarchy
        self.sourceCandidates = sourceCandidates
    }
}
