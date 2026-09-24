import Foundation
import LoupeCore

@MainActor
public final class LoupeRuntime {
    public static let shared = LoupeRuntime()

    public let identity: LoupeRuntimeIdentity
    private var logs: [LoupeRuntimeLog] = []
    private var networkEvents: [LoupeNetworkEvent] = []
    private var referenceEvidence: [LoupeReferenceEvidence] = []
    private var lifetimeProbes: [LoupeLifetimeProbeRecord] = []
    private var metadataByTestID: [String: [String: LoupeMetadataValue]] = [:]
    private var probesByID: [String: LoupeRegisteredProbe] = [:]
    private var didInstallBridge = false

    init() {
        let environment = ProcessInfo.processInfo.environment
        let simulatorUDID = environment["SIMULATOR_UDID"]
        identity = LoupeRuntimeIdentity(
            platform: LoupePlatformSupport.platformName,
            deviceIdentifier: environment["LOUPE_DEVICE_ID"] ?? simulatorUDID,
            deviceName: LoupePlatformSupport.deviceName,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            simulatorUDID: simulatorUDID,
            simulatorName: environment["SIMULATOR_DEVICE_NAME"]
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func activateBridge() {
        installBridgeIfNeeded()
    }

    public func runtimeState() -> LoupeRuntimeState {
        LoupeRuntimeState(identity: identity, logs: logs)
    }

    public func runtimeStatus() -> LoupeRuntimeStatus {
        LoupeRuntimeStatus(
            identity: identity,
            runtimeVersion: Bundle(for: LoupeRuntime.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            retainedLogCount: logs.count
        )
    }

    public func runtimeLogs() -> [LoupeRuntimeLog] {
        logs
    }

    public func runtimeNetworkEvents() -> [LoupeNetworkEvent] {
        networkEvents
    }

    public func runtimeReferenceEvidence() -> [LoupeReferenceEvidence] {
        referenceEvidence
    }

    public func runtimeLifetimeProbes(aliveOnly: Bool = false) -> LoupeLifetimeProbeReport {
        let probes = lifetimeProbes.map(\.probe)
        let visibleProbes = aliveOnly ? probes.filter(\.isAlive) : probes
        let aliveCount = probes.filter(\.isAlive).count
        let suspectedLeakCount = probes.filter { $0.expectedDeallocated && $0.isAlive }.count
        return LoupeLifetimeProbeReport(
            aliveOnly: aliveOnly,
            probeCount: probes.count,
            aliveCount: aliveCount,
            suspectedLeakCount: suspectedLeakCount,
            probes: visibleProbes
        )
    }

    public func registerProbe(
        id: String,
        label: String? = nil,
        role: String = "group",
        frame: LoupeRect? = nil,
        isVisible: Bool = true,
        isEnabled: Bool = true,
        isInteractive: Bool = false,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        guard let id = nonEmpty(id) else {
            return
        }
        var mergedMetadata = metadata
        mergedMetadata["id"] = .string(id)
        mergedMetadata["loupe.probe"] = .bool(true)
        probesByID[id] = LoupeRegisteredProbe(
            id: id,
            label: nonEmpty(label),
            role: nonEmpty(role) ?? "group",
            frame: frame,
            isVisible: isVisible,
            isEnabled: isEnabled,
            isInteractive: isInteractive,
            metadata: mergedMetadata
        )
    }

    public func unregisterProbe(id: String) {
        guard let id = nonEmpty(id) else {
            return
        }
        probesByID.removeValue(forKey: id)
    }

    func registeredProbes() -> [LoupeRegisteredProbe] {
        probesByID.values.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func metadata(forTestID testID: String?) -> [String: LoupeMetadataValue] {
        guard let testID = nonEmpty(testID) else {
            return [:]
        }
        return metadataByTestID[testID] ?? [:]
    }

    public func log(
        level: String = "info",
        _ message: String,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        logs.append(
            LoupeRuntimeLog(
                level: level,
                message: message,
                metadata: metadata
            )
        )

        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    public func recordNetworkEvent(_ event: LoupeNetworkEvent) {
        networkEvents.append(event)
        if networkEvents.count > 500 {
            networkEvents.removeFirst(networkEvents.count - 500)
        }
    }

    public func recordReference(_ evidence: LoupeReferenceEvidence) {
        referenceEvidence.append(evidence)
        if referenceEvidence.count > 500 {
            referenceEvidence.removeFirst(referenceEvidence.count - 500)
        }
    }

    @discardableResult
    public func watchLifetime(
        _ object: AnyObject,
        name: String? = nil,
        expectedDeallocated: Bool = true,
        metadata: [String: LoupeMetadataValue] = [:]
    ) -> String {
        let record = LoupeLifetimeProbeRecord(
            object: object,
            name: name,
            expectedDeallocated: expectedDeallocated,
            metadata: metadata
        )
        lifetimeProbes.append(record)
        if lifetimeProbes.count > 500 {
            lifetimeProbes.removeFirst(lifetimeProbes.count - 500)
        }
        return record.id
    }

    private func installBridgeIfNeeded() {
        guard !didInstallBridge else {
            return
        }

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(receiveLogNotification(_:)),
            name: .loupeLog,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveViewMetadataNotification(_:)),
            name: .loupeViewMetadata,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveNetworkNotification(_:)),
            name: .loupeNetwork,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveReferenceNotification(_:)),
            name: .loupeReference,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveLifetimeProbeNotification(_:)),
            name: .loupeLifetimeProbe,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveProbeNotification(_:)),
            name: .loupeProbe,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(receiveRemoveProbeNotification(_:)),
            name: .loupeRemoveProbe,
            object: nil
        )
        LoupePlatformSupport.installAutomaticNetworkCapture()
        didInstallBridge = true
    }

    @objc private nonisolated func receiveLogNotification(_ notification: Notification) {
        guard let payload = LoupeLogNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.receiveLogPayload(payload)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.receiveLogPayload(payload)
                }
            }
        }
    }

    @MainActor
    private func receiveLogPayload(_ payload: LoupeLogNotificationPayload) {
        log(
            level: payload.level,
            payload.message,
            metadata: payload.metadata
        )
    }

    @objc private nonisolated func receiveViewMetadataNotification(_ notification: Notification) {
        guard let payload = LoupeViewMetadataNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.receiveViewMetadataPayload(payload)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.receiveViewMetadataPayload(payload)
                }
            }
        }
    }

    @MainActor
    private func receiveViewMetadataPayload(_ payload: LoupeViewMetadataNotificationPayload) {
        #if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
        if let view = payload.view {
            LoupePlatformSupport.mergeMetadata(payload.metadata, into: view)
        }
        #endif

        if let testID = payload.testID {
            var existing = metadataByTestID[testID] ?? [:]
            existing.merge(payload.metadata) { _, new in new }
            metadataByTestID[testID] = existing
        }
    }

    @objc private nonisolated func receiveNetworkNotification(_ notification: Notification) {
        guard let payload = LoupeNetworkNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.recordNetworkEvent(payload.event)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.recordNetworkEvent(payload.event)
                }
            }
        }
    }

    @objc private nonisolated func receiveReferenceNotification(_ notification: Notification) {
        guard let payload = LoupeReferenceNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.recordReference(payload.evidence)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.recordReference(payload.evidence)
                }
            }
        }
    }

    @objc private nonisolated func receiveLifetimeProbeNotification(_ notification: Notification) {
        guard let payload = LoupeLifetimeProbeNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.watchLifetimePayload(payload)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.watchLifetimePayload(payload)
                }
            }
        }
    }

    @MainActor
    private func watchLifetimePayload(_ payload: LoupeLifetimeProbeNotificationPayload) {
        watchLifetime(
            payload.object,
            name: payload.name,
            expectedDeallocated: payload.expectedDeallocated,
            metadata: payload.metadata
        )
    }

    @objc private nonisolated func receiveProbeNotification(_ notification: Notification) {
        guard let payload = LoupeProbeNotificationPayload(notification: notification) else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.registerProbePayload(payload)
            }
        } else {
            DispatchQueue.main.async { [weak self, payload] in
                MainActor.assumeIsolated {
                    self?.registerProbePayload(payload)
                }
            }
        }
    }

    @MainActor
    private func registerProbePayload(_ payload: LoupeProbeNotificationPayload) {
        registerProbe(
            id: payload.id,
            label: payload.label,
            role: payload.role,
            frame: payload.frame,
            isVisible: payload.isVisible,
            isEnabled: payload.isEnabled,
            isInteractive: payload.isInteractive,
            metadata: payload.metadata
        )
    }

    @objc private nonisolated func receiveRemoveProbeNotification(_ notification: Notification) {
        guard let id = LoupeRemoveProbeNotificationPayload(notification: notification)?.id else {
            return
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.unregisterProbe(id: id)
            }
        } else {
            DispatchQueue.main.async { [weak self, id] in
                MainActor.assumeIsolated {
                    self?.unregisterProbe(id: id)
                }
            }
        }
    }

}

public enum Loupe {
    @MainActor
    public static func log(
        _ message: String,
        level: String = "info",
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        LoupeRuntime.shared.log(level: level, message, metadata: metadata)
    }

    @MainActor
    public static func recordNetwork(
        url: String,
        method: String? = nil,
        statusCode: Int? = nil,
        requestBody: String? = nil,
        responseBody: String? = nil,
        error: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        LoupeRuntime.shared.recordNetworkEvent(
            LoupeNetworkEvent(
                method: method,
                url: url,
                statusCode: statusCode,
                requestBody: requestBody,
                responseBody: responseBody,
                error: error,
                metadata: metadata
            )
        )
    }

    @MainActor
    public static func recordReference(
        owner: String,
        target: String,
        kind: String? = nil,
        label: String? = nil,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        LoupeRuntime.shared.recordReference(
            LoupeReferenceEvidence(
                owner: owner,
                target: target,
                kind: kind,
                label: label,
                metadata: metadata
            )
        )
    }

    @MainActor
    public static func registerProbe(
        _ id: String,
        label: String? = nil,
        role: String = "group",
        frame: LoupeRect? = nil,
        isVisible: Bool = true,
        isEnabled: Bool = true,
        isInteractive: Bool = false,
        metadata: [String: LoupeMetadataValue] = [:]
    ) {
        LoupeRuntime.shared.registerProbe(
            id: id,
            label: label,
            role: role,
            frame: frame,
            isVisible: isVisible,
            isEnabled: isEnabled,
            isInteractive: isInteractive,
            metadata: metadata
        )
    }

    @MainActor
    public static func unregisterProbe(_ id: String) {
        LoupeRuntime.shared.unregisterProbe(id: id)
    }

    @MainActor
    @discardableResult
    public static func watchLifetime(
        _ object: AnyObject,
        name: String? = nil,
        expectedDeallocated: Bool = true,
        metadata: [String: LoupeMetadataValue] = [:]
    ) -> String {
        LoupeRuntime.shared.watchLifetime(
            object,
            name: name,
            expectedDeallocated: expectedDeallocated,
            metadata: metadata
        )
    }
}

private final class LoupeLifetimeProbeRecord {
    let id: String
    let name: String
    let objectType: String
    let createdAt: Date
    let expectedDeallocated: Bool
    let metadata: [String: LoupeMetadataValue]
    weak var object: AnyObject?

    init(
        object: AnyObject,
        name: String?,
        expectedDeallocated: Bool,
        metadata: [String: LoupeMetadataValue]
    ) {
        id = UUID().uuidString
        self.object = object
        objectType = String(reflecting: type(of: object))
        self.name = name ?? objectType
        createdAt = Date()
        self.expectedDeallocated = expectedDeallocated
        self.metadata = metadata
    }

    var probe: LoupeLifetimeProbe {
        LoupeLifetimeProbe(
            id: id,
            name: name,
            objectType: objectType,
            createdAt: createdAt,
            expectedDeallocated: expectedDeallocated,
            isAlive: object != nil,
            metadata: metadata
        )
    }
}

struct LoupeRegisteredProbe: Equatable {
    var id: String
    var label: String?
    var role: String
    var frame: LoupeRect?
    var isVisible: Bool
    var isEnabled: Bool
    var isInteractive: Bool
    var metadata: [String: LoupeMetadataValue]
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func metadataPayload(from userInfo: [AnyHashable: Any]) -> [String: LoupeMetadataValue] {
    if let metadata = userInfo["metadata"] as? [String: Any] {
        return metadata.compactMapValues(loupeMetadataValue)
    }

    var payload: [String: LoupeMetadataValue] = [:]
    let reservedKeys: Set<String> = [
        "level", "message", "metadata", "view", "testID", "id",
        "owner", "target", "kind", "label",
        "object", "name", "expectedDeallocated",
        "role", "frame", "x", "y", "width", "height",
        "isVisible", "isEnabled", "isInteractive",
    ]
    for (rawKey, rawValue) in userInfo {
        guard let key = rawKey as? String, !reservedKeys.contains(key), let value = loupeMetadataValue(from: rawValue) else {
            continue
        }
        payload[key] = value
    }
    return payload
}

private func loupeBoolean(from value: Any?, default defaultValue: Bool) -> Bool {
    switch value {
    case let value as Bool:
        return value
    case let value as NSNumber:
        return value.boolValue
    case let value as String:
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return defaultValue
        }
    default:
        return defaultValue
    }
}

private func loupeDouble(from value: Any?) -> Double? {
    switch value {
    case let value as Double:
        return value
    case let value as Float:
        return Double(value)
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    case let value as String:
        return Double(value)
    default:
        return nil
    }
}

private func loupeRectPayload(from userInfo: [AnyHashable: Any]) -> LoupeRect? {
    if let frame = userInfo["frame"] as? [String: Any] {
        return loupeRectPayload(from: frame)
    }

    return loupeRectPayload(from: userInfo.reduce(into: [String: Any]()) { partial, entry in
        if let key = entry.key as? String {
            partial[key] = entry.value
        }
    })
}

private func loupeRectPayload(from dictionary: [String: Any]) -> LoupeRect? {
    guard let x = loupeDouble(from: dictionary["x"]),
          let y = loupeDouble(from: dictionary["y"]),
          let width = loupeDouble(from: dictionary["width"]),
          let height = loupeDouble(from: dictionary["height"]) else {
        return nil
    }

    return LoupeRect(x: x, y: y, width: width, height: height)
}

private func loupeMetadataValue(from value: Any) -> LoupeMetadataValue? {
    switch value {
    case let value as String:
        return .string(value)
    case let value as Bool:
        return .bool(value)
    case let value as Int:
        return .int(value)
    case let value as Double:
        return .double(value)
    case let value as Float:
        return .double(Double(value))
    case let value as NSNumber:
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return .bool(value.boolValue)
        }
        let doubleValue = value.doubleValue
        if doubleValue.rounded() == doubleValue {
            return .int(value.intValue)
        }
        return .double(doubleValue)
    default:
        return nil
    }
}

private struct LoupeLogNotificationPayload: Sendable {
    var level: String
    var message: String
    var metadata: [String: LoupeMetadataValue]

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let message = nonEmpty(userInfo["message"] as? String) else {
            return nil
        }

        self.level = nonEmpty(userInfo["level"] as? String) ?? "info"
        self.message = message
        self.metadata = metadataPayload(from: userInfo)
    }
}

private struct LoupeViewMetadataNotificationPayload: @unchecked Sendable {
    #if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
    var view: LoupePlatformView?
    #endif
    var testID: String?
    var metadata: [String: LoupeMetadataValue]

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let metadata = metadataPayload(from: userInfo)
        guard !metadata.isEmpty else {
            return nil
        }

        #if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
        self.view = LoupePlatformSupport.metadataView(from: notification, userInfo: userInfo)
        #endif
        self.testID = nonEmpty(userInfo["testID"] as? String ?? userInfo["id"] as? String)
        self.metadata = metadata
    }
}

private struct LoupeNetworkNotificationPayload: Sendable {
    var event: LoupeNetworkEvent

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let url = nonEmpty(userInfo["url"] as? String) else {
            return nil
        }

        let statusCode: Int?
        if let value = userInfo["statusCode"] as? Int {
            statusCode = value
        } else if let value = userInfo["status"] as? Int {
            statusCode = value
        } else if let value = userInfo["statusCode"] as? NSNumber {
            statusCode = value.intValue
        } else {
            statusCode = nil
        }

        event = LoupeNetworkEvent(
            method: nonEmpty(userInfo["method"] as? String),
            url: url,
            statusCode: statusCode,
            requestBody: userInfo["requestBody"] as? String,
            responseBody: userInfo["responseBody"] as? String,
            error: userInfo["error"] as? String,
            metadata: metadataPayload(from: userInfo)
        )
    }
}

private struct LoupeReferenceNotificationPayload: Sendable {
    var evidence: LoupeReferenceEvidence

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let owner = nonEmpty(userInfo["owner"] as? String),
              let target = nonEmpty(userInfo["target"] as? String) else {
            return nil
        }

        evidence = LoupeReferenceEvidence(
            owner: owner,
            target: target,
            kind: nonEmpty(userInfo["kind"] as? String),
            label: nonEmpty(userInfo["label"] as? String),
            metadata: metadataPayload(from: userInfo)
        )
    }
}

private struct LoupeLifetimeProbeNotificationPayload: @unchecked Sendable {
    var object: AnyObject
    var name: String?
    var expectedDeallocated: Bool
    var metadata: [String: LoupeMetadataValue]

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let object = (notification.object as? AnyObject) ?? (userInfo["object"] as? AnyObject) else {
            return nil
        }

        self.object = object
        self.name = nonEmpty(userInfo["name"] as? String)
        if let value = userInfo["expectedDeallocated"] as? Bool {
            expectedDeallocated = value
        } else if let value = userInfo["expectedDeallocated"] as? NSNumber {
            expectedDeallocated = value.boolValue
        } else {
            expectedDeallocated = true
        }
        metadata = metadataPayload(from: userInfo)
    }
}

private struct LoupeProbeNotificationPayload: Sendable {
    var id: String
    var label: String?
    var role: String
    var frame: LoupeRect?
    var isVisible: Bool
    var isEnabled: Bool
    var isInteractive: Bool
    var metadata: [String: LoupeMetadataValue]

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let id = nonEmpty(userInfo["id"] as? String ?? userInfo["testID"] as? String) else {
            return nil
        }

        self.id = id
        label = nonEmpty(userInfo["label"] as? String)
        role = nonEmpty(userInfo["role"] as? String) ?? "group"
        frame = loupeRectPayload(from: userInfo)
        isVisible = loupeBoolean(from: userInfo["isVisible"], default: true)
        isEnabled = loupeBoolean(from: userInfo["isEnabled"], default: true)
        isInteractive = loupeBoolean(from: userInfo["isInteractive"], default: false)
        metadata = metadataPayload(from: userInfo)
    }
}

private struct LoupeRemoveProbeNotificationPayload: Sendable {
    var id: String

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        guard let id = nonEmpty(userInfo["id"] as? String ?? userInfo["testID"] as? String) else {
            return nil
        }

        self.id = id
    }
}

public extension Notification.Name {
    static let loupeLog = Notification.Name("dev.loupe.log")
    static let loupeViewMetadata = Notification.Name("dev.loupe.viewMetadata")
    static let loupeNetwork = Notification.Name("dev.loupe.network")
    static let loupeReference = Notification.Name("dev.loupe.reference")
    static let loupeLifetimeProbe = Notification.Name("dev.loupe.lifetimeProbe")
    static let loupeProbe = Notification.Name("dev.loupe.probe")
    static let loupeRemoveProbe = Notification.Name("dev.loupe.removeProbe")
}
