import Foundation

public struct LoupeNetworkEvent: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var method: String?
    public var url: String
    public var statusCode: Int?
    public var requestBody: String?
    public var responseBody: String?
    public var error: String?
    public var metadata: [String: LoupeMetadataValue]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        method: String? = nil,
        url: String,
        statusCode: Int? = nil,
        requestBody: String? = nil,
        responseBody: String? = nil,
        error: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.error = error
        self.metadata = metadata
    }
}

public struct LoupeReferenceEvidence: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var owner: String
    public var target: String
    public var kind: String?
    public var label: String?
    public var metadata: [String: LoupeMetadataValue]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        owner: String,
        target: String,
        kind: String? = nil,
        label: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.owner = owner
        self.target = target
        self.kind = kind
        self.label = label
        self.metadata = metadata
    }
}

public struct LoupeReferenceGraph: Codable, Equatable, Sendable {
    public var target: String?
    public var evidenceKind: String
    public var nodes: [LoupeReferenceGraphNode]
    public var edges: [LoupeReferenceGraphEdge]
    public var owners: [LoupeReferenceGraphOwner]

    public init(
        target: String? = nil,
        evidenceKind: String = "app-authored-reference-evidence",
        nodes: [LoupeReferenceGraphNode],
        edges: [LoupeReferenceGraphEdge],
        owners: [LoupeReferenceGraphOwner]
    ) {
        self.target = target
        self.evidenceKind = evidenceKind
        self.nodes = nodes
        self.edges = edges
        self.owners = owners
    }
}

public struct LoupeReferenceGraphNode: Codable, Equatable, Sendable {
    public var name: String
    public var incomingCount: Int
    public var outgoingCount: Int

    public init(name: String, incomingCount: Int, outgoingCount: Int) {
        self.name = name
        self.incomingCount = incomingCount
        self.outgoingCount = outgoingCount
    }
}

public struct LoupeReferenceGraphEdge: Codable, Equatable, Sendable {
    public var evidenceID: String
    public var owner: String
    public var target: String
    public var kind: String?
    public var label: String?
    public var metadata: [String: LoupeMetadataValue]
    public var timestamp: Date

    public init(
        evidenceID: String,
        owner: String,
        target: String,
        kind: String? = nil,
        label: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:],
        timestamp: Date
    ) {
        self.evidenceID = evidenceID
        self.owner = owner
        self.target = target
        self.kind = kind
        self.label = label
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public struct LoupeReferenceGraphOwner: Codable, Equatable, Sendable {
    public var evidenceID: String
    public var owner: String
    public var kind: String?
    public var label: String?
    public var metadata: [String: LoupeMetadataValue]
    public var timestamp: Date

    public init(
        evidenceID: String,
        owner: String,
        kind: String? = nil,
        label: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:],
        timestamp: Date
    ) {
        self.evidenceID = evidenceID
        self.owner = owner
        self.kind = kind
        self.label = label
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public struct LoupeStateEntry: Codable, Equatable, Sendable {
    public var key: String
    public var value: LoupeMetadataValue?

    public init(key: String, value: LoupeMetadataValue?) {
        self.key = key
        self.value = value
    }
}

public struct LoupeStateMutationRequest: Codable, Equatable, Sendable {
    public var key: String
    public var value: LoupeMetadataValue?

    public init(key: String, value: LoupeMetadataValue?) {
        self.key = key
        self.value = value
    }
}

public struct LoupeStateMutationResponse: Codable, Equatable, Sendable {
    public var key: String
    public var before: LoupeMetadataValue?
    public var after: LoupeMetadataValue?

    public init(key: String, before: LoupeMetadataValue?, after: LoupeMetadataValue?) {
        self.key = key
        self.before = before
        self.after = after
    }
}

public struct LoupeKeychainItem: Codable, Equatable, Sendable {
    public var itemClass: String
    public var service: String?
    public var account: String?
    public var accessGroup: String?

    public init(itemClass: String, service: String? = nil, account: String? = nil, accessGroup: String? = nil) {
        self.itemClass = itemClass
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }
}

public struct LoupeEnvironmentMutationRequest: Codable, Equatable, Sendable {
    public var appearance: String?

    public init(appearance: String? = nil) {
        self.appearance = appearance
    }
}

public struct LoupeEnvironmentMutationResponse: Codable, Equatable, Sendable {
    public var appearance: String?

    public init(appearance: String? = nil) {
        self.appearance = appearance
    }
}

public struct LoupeHitTestReport: Codable, Equatable, Sendable {
    public var point: LoupePoint
    public var hitRef: String?
    public var hitTestID: String?
    public var hitTypeName: String?
    public var responderChain: [LoupeResponderEntry]

    public init(
        point: LoupePoint,
        hitRef: String? = nil,
        hitTestID: String? = nil,
        hitTypeName: String? = nil,
        responderChain: [LoupeResponderEntry] = []
    ) {
        self.point = point
        self.hitRef = hitRef
        self.hitTestID = hitTestID
        self.hitTypeName = hitTypeName
        self.responderChain = responderChain
    }
}

public struct LoupeResponderEntry: Codable, Equatable, Sendable {
    public var typeName: String
    public var ref: String?
    public var testID: String?
    public var frame: LoupeRect?

    public init(typeName: String, ref: String? = nil, testID: String? = nil, frame: LoupeRect? = nil) {
        self.typeName = typeName
        self.ref = ref
        self.testID = testID
        self.frame = frame
    }
}

public struct LoupeScrollProfile: Codable, Equatable, Sendable {
    public var ref: String?
    public var testID: String?
    public var beforeOffset: LoupePoint?
    public var afterOffset: LoupePoint?
    public var delta: LoupePoint?
    public var actionElapsed: Double
    public var traceDirectory: String?

    public init(
        ref: String? = nil,
        testID: String? = nil,
        beforeOffset: LoupePoint? = nil,
        afterOffset: LoupePoint? = nil,
        delta: LoupePoint? = nil,
        actionElapsed: Double,
        traceDirectory: String? = nil
    ) {
        self.ref = ref
        self.testID = testID
        self.beforeOffset = beforeOffset
        self.afterOffset = afterOffset
        self.delta = delta
        self.actionElapsed = actionElapsed
        self.traceDirectory = traceDirectory
    }
}
