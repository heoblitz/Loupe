import Foundation
import LoupeCore

#if canImport(UIKit) || canImport(AppKit)
#if canImport(UIKit)
import UIKit
typealias LoupePlatformView = UIView
#elseif canImport(AppKit)
import AppKit
typealias LoupePlatformView = NSView
#endif

@MainActor
public final class LoupeRuntime {
    public static let shared = LoupeRuntime()

    public let identity: LoupeRuntimeIdentity
    private var logs: [LoupeRuntimeLog] = []
    private var networkEvents: [LoupeNetworkEvent] = []
    private var referenceEvidence: [LoupeReferenceEvidence] = []
    private var metadataByTestID: [String: [String: LoupeMetadataValue]] = [:]
    private var didInstallBridge = false

    private init() {
        let environment = ProcessInfo.processInfo.environment
        identity = LoupeRuntimeIdentity(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            simulatorUDID: environment["SIMULATOR_UDID"],
            simulatorName: environment["SIMULATOR_DEVICE_NAME"]
        )
    }

    public func activateBridge() {
        installBridgeIfNeeded()
    }

    public func runtimeState() -> LoupeRuntimeState {
        LoupeRuntimeState(identity: identity, logs: logs)
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
        LoupeNetworkCaptureProtocol.install()
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
        if let view = payload.view {
            view.loupeMetadata.merge(payload.metadata) { _, new in new }
        }

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
    let reservedKeys: Set<String> = ["level", "message", "metadata", "view", "testID", "id", "owner", "target", "kind", "label"]
    for (rawKey, rawValue) in userInfo {
        guard let key = rawKey as? String, !reservedKeys.contains(key), let value = loupeMetadataValue(from: rawValue) else {
            continue
        }
        payload[key] = value
    }
    return payload
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
    var view: LoupePlatformView?
    var testID: String?
    var metadata: [String: LoupeMetadataValue]

    init?(notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let metadata = metadataPayload(from: userInfo)
        guard !metadata.isEmpty else {
            return nil
        }

        self.view = (notification.object as? LoupePlatformView) ?? (userInfo["view"] as? LoupePlatformView)
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

public extension Notification.Name {
    static let loupeLog = Notification.Name("dev.loupe.log")
    static let loupeViewMetadata = Notification.Name("dev.loupe.viewMetadata")
    static let loupeNetwork = Notification.Name("dev.loupe.network")
    static let loupeReference = Notification.Name("dev.loupe.reference")
}

#endif
