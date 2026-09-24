import Foundation

public struct LoupeRuntimeLog: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var level: String
    public var message: String
    public var metadata: [String: LoupeMetadataValue]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        level: String,
        message: String,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

public struct LoupeRuntimeIdentity: Codable, Equatable, Sendable {
    public var launchID: String
    public var startedAt: Date
    public var platform: String?
    public var deviceIdentifier: String?
    public var deviceName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32
    public var simulatorUDID: String?
    public var simulatorName: String?

    public init(
        launchID: String = UUID().uuidString,
        startedAt: Date = Date(),
        platform: String? = nil,
        deviceIdentifier: String? = nil,
        deviceName: String? = nil,
        bundleIdentifier: String? = nil,
        processIdentifier: Int32,
        simulatorUDID: String? = nil,
        simulatorName: String? = nil
    ) {
        self.launchID = launchID
        self.startedAt = startedAt
        self.platform = platform
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.simulatorUDID = simulatorUDID
        self.simulatorName = simulatorName
    }
}

public struct LoupeRuntimeState: Codable, Equatable, Sendable {
    public var identity: LoupeRuntimeIdentity
    public var logs: [LoupeRuntimeLog]

    public init(
        identity: LoupeRuntimeIdentity,
        logs: [LoupeRuntimeLog] = []
    ) {
        self.identity = identity
        self.logs = logs
    }
}

/// Small, stable liveness payload.  Logs deliberately stay on `/logs` so an
/// ordinary identity check does not copy an ever-growing diagnostic buffer.
public struct LoupeRuntimeStatus: Codable, Equatable, Sendable {
    public var identity: LoupeRuntimeIdentity
    public var runtimeVersion: String?
    public var retainedLogCount: Int

    public init(identity: LoupeRuntimeIdentity, runtimeVersion: String? = nil, retainedLogCount: Int) {
        self.identity = identity
        self.runtimeVersion = runtimeVersion
        self.retainedLogCount = retainedLogCount
    }
}
