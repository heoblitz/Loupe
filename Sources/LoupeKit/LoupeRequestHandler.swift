import Foundation
import LoupeCore

#if canImport(Darwin) && ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit) || os(watchOS))

/// Owns request deadlines, routing, UI handoff, and JSON response formation.
/// Socket admission and descriptor lifetime stay in `LoupeServer`.
final class LoupeRequestHandler: Sendable {
    func responsePayload(for request: HTTPRequest, deadlineNanoseconds: UInt64) async -> ResponsePayload {
        if request.path == "/health" {
            return ResponsePayload(status: 200, body: #"{"status":"ok","name":"LoupeKit"}"#)
        }

        let execution = RequestExecution()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let completion = RequestCompletion(continuation: continuation)
                let operation = Task { [weak self] in
                    guard let self else {
                        completion.resolve(ResponsePayload(status: 503, body: #"{"error":"server_stopped"}"#))
                        return
                    }
                    do {
                        let payload = try await self.response(for: request, execution: execution)
                        completion.resolve(payload)
                    } catch is CancellationError {
                        completion.resolve(ResponsePayload(status: 503, body: #"{"error":"request_cancelled"}"#))
                    } catch {
                        completion.resolve(ResponsePayload(status: 500, body: self.errorBody("request_failed", error: error)))
                    }
                }
                execution.setOperation(operation)
                let deadline = Task {
                    do {
                        let now = DispatchTime.now().uptimeNanoseconds
                        if deadlineNanoseconds > now {
                            try await Task.sleep(nanoseconds: deadlineNanoseconds - now)
                        }
                    } catch {
                        return
                    }
                    let didStart = execution.cancel()
                    let code = didStart && request.mutatesRuntime
                        ? "request_timeout_action_may_have_run"
                        : "request_timeout"
                    completion.resolve(ResponsePayload(status: 503, body: #"{"error":"\#(code)"}"#))
                }
                completion.setDeadline(deadline)
            }
        } onCancel: {
            execution.cancel()
        }
    }

    private func response(for request: HTTPRequest, execution: RequestExecution) async throws -> ResponsePayload {
        switch request.path {
        case "/runtime":
            let state = try await captureUI(execution) { LoupeRuntime.shared.runtimeState() }
            let response = request.queryItems["includeLogs"] == "true"
                ? state
                : LoupeRuntimeState(identity: state.identity)
            return jsonPayload(response, failureCode: "runtime_encoding_failed")
        case "/status":
            return jsonPayload(try await captureUI(execution) { LoupeRuntime.shared.runtimeStatus() }, failureCode: "status_encoding_failed")
        case "/logs":
            return jsonPayload(try await captureUI(execution) { LoupeRuntime.shared.runtimeLogs() }, failureCode: "logs_encoding_failed")
        case "/network":
            return jsonPayload(try await captureUI(execution) { LoupeRuntime.shared.runtimeNetworkEvents() }, failureCode: "network_encoding_failed")
        case "/refs":
            return jsonPayload(try await captureUI(execution) { LoupeRuntime.shared.runtimeReferenceEvidence() }, failureCode: "refs_encoding_failed")
        case "/objects/classes":
            let matching = request.queryItems["matching"]
            let limit = request.queryItems["limit"].flatMap(Int.init) ?? 100
            let runtime = await LoupeRuntime.shared
            return jsonPayload(
                runtime.runtimeObjectClasses(matching: matching, limit: limit),
                failureCode: "object_classes_encoding_failed"
            )
        case "/objects/describe":
            guard let className = request.queryItems["class"] else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_class"}"#)
            }
            do {
                let runtime = await LoupeRuntime.shared
                return jsonPayload(
                    try runtime.runtimeObjectDescription(className: className),
                    failureCode: "object_description_encoding_failed"
                )
            } catch {
                return ResponsePayload(status: 400, body: errorBody("object_description_failed", error: error))
            }
        case "/leaks":
            let aliveOnly = request.queryItems["alive"] == "true" || request.queryItems["aliveOnly"] == "true"
            return jsonPayload(try await captureUI(execution) {
                LoupeRuntime.shared.runtimeLifetimeProbes(aliveOnly: aliveOnly)
            }, failureCode: "leaks_encoding_failed")
        case "/snapshot":
            return jsonPayload(try await captureUI(execution) { LoupeAgent().captureSnapshot() }, failureCode: "snapshot_encoding_failed")
        case "/accessibility":
            let includeHidden = request.queryItems["includeHidden"] == "true"
            #if canImport(AppKit) && !canImport(UIKit)
            // AppKit's native accessibility bridge walks live NSAccessibility
            // elements, so this capture itself must stay on the main actor.
            return jsonPayload(
                try await captureUI(execution) { LoupeAgent().captureAccessibilityTree(includeHidden: includeHidden) },
                failureCode: "accessibility_encoding_failed"
            )
            #elseif canImport(UIKit) && !os(watchOS)
            if ProcessInfo.processInfo.environment["LOUPE_NATIVE_ACCESSIBILITY"] == "1" {
                return jsonPayload(
                    try await captureUI(execution) { LoupeAgent().captureAccessibilityTree(includeHidden: includeHidden) },
                    failureCode: "accessibility_encoding_failed"
                )
            }
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            return jsonPayload(
                LoupeAccessibilityTree.build(from: snapshot, includeHidden: includeHidden),
                failureCode: "accessibility_encoding_failed"
            )
            #else
            // watchOS derives its tree solely from the immutable snapshot.
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            return jsonPayload(
                LoupeAccessibilityTree.build(from: snapshot, includeHidden: includeHidden),
                failureCode: "accessibility_encoding_failed"
            )
            #endif
        case "/accessibility/action-observation":
            return jsonPayload(
                try await captureUI(execution) { LoupeAgent().captureAccessibilityActionObservation() },
                failureCode: "accessibility_action_observation_encoding_failed"
            )
        case "/accessibility/actions":
            return jsonPayload(try await captureUI(execution) { LoupeAgent().captureAccessibilityActionTree() }, failureCode: "accessibility_actions_encoding_failed")
        case "/inspect":
            guard let selector = selector(from: request.queryItems) else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
            }
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            guard let inspection = LoupeSnapshotInspector.inspect(selector, in: snapshot) else {
                return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
            }
            return jsonPayload(inspection, failureCode: "inspect_encoding_failed")
        case "/subtree":
            guard let selector = selector(from: request.queryItems) else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
            }
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            let depth = request.queryItems["depth"].flatMap(Int.init) ?? 2
            guard let subtree = LoupeSnapshotInspector.subtree(selector, in: snapshot, maxDepth: depth) else {
                return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
            }
            return jsonPayload(subtree, failureCode: "subtree_encoding_failed")
        case "/audit":
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            return jsonPayload(LoupeLayoutAuditor.audit(snapshot), failureCode: "audit_encoding_failed")
        case "/observation":
            let snapshot = try await captureUI(execution) { LoupeAgent().captureSnapshot() }
            return jsonPayload(LoupeObservationCompactor.compact(snapshot), failureCode: "observation_encoding_failed")
        case "/environment":
            if request.method == "POST" {
                do {
                    let mutation = try JSONDecoder().decode(LoupeEnvironmentMutationRequest.self, from: request.body)
                    return jsonPayload(try await captureUI(execution) { try LoupeAgent().setEnvironment(mutation) }, failureCode: "environment_encoding_failed")
                } catch {
                    return ResponsePayload(status: 400, body: errorBody("environment_failed", error: error))
                }
            }
            return jsonPayload(try await captureUI(execution) { LoupeAgent().currentEnvironment() }, failureCode: "environment_encoding_failed")
        case "/state/defaults", "/state/flags":
            if request.method == "POST" {
                do {
                    let mutation = try JSONDecoder().decode(LoupeStateMutationRequest.self, from: request.body)
                    return jsonPayload(try await captureUI(execution) { LoupeAgent().setDefault(mutation) }, failureCode: "state_encoding_failed")
                } catch {
                    return ResponsePayload(status: 400, body: errorBody("state_failed", error: error))
                }
            }
            guard let key = request.queryItems["key"] else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_key"}"#)
            }
            return jsonPayload(try await captureUI(execution) { LoupeAgent().defaultsEntry(key: key) }, failureCode: "state_encoding_failed")
        case "/state/keychain":
            return jsonPayload(try await captureUI(execution) { LoupeAgent().keychainItems() }, failureCode: "keychain_encoding_failed")
        case "/hit-test":
            do {
                let point = try point(from: request.queryItems)
                return jsonPayload(try await captureUI(execution) { LoupeAgent().hitTest(point: point) }, failureCode: "hit_test_encoding_failed")
            } catch {
                return ResponsePayload(status: 400, body: errorBody("hit_test_failed", error: error))
            }
        case "/responder-chain":
            guard let selector = selector(from: request.queryItems) else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
            }
            guard let report = try await captureUI(execution, { LoupeAgent().responderChain(selector: selector) }) else {
                return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
            }
            return jsonPayload(report, failureCode: "responder_chain_encoding_failed")
        case "/mutations":
            return jsonPayload(try await captureUI(execution) { LoupeAgent().mutationCapabilities() }, failureCode: "mutations_encoding_failed")
        case "/mutate":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let mutation = try JSONDecoder().decode(LoupeMutationRequest.self, from: request.body)
                return jsonPayload(try await captureUI(execution) { try LoupeAgent().mutate(mutation) }, failureCode: "mutation_encoding_failed")
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("mutation_failed", error: error))
            }
        case "/activate":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let action = try JSONDecoder().decode(LoupeActivationRequest.self, from: request.body)
                return jsonPayload(try await captureUI(execution) { try LoupeAgent().activate(action) }, failureCode: "activation_encoding_failed")
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("activation_failed", error: error))
            }
        case "/constraint":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let mutation = try JSONDecoder().decode(LoupeConstraintMutationRequest.self, from: request.body)
                return jsonPayload(try await captureUI(execution) { try LoupeAgent().mutateConstraint(mutation) }, failureCode: "constraint_encoding_failed")
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("constraint_mutation_failed", error: error))
            }
        case "/input/focus":
            #if canImport(UIKit) && !os(watchOS)
            guard let testID = request.queryItems["testID"], !testID.isEmpty else {
                return ResponsePayload(status: 400, body: #"{"error":"missing_test_id"}"#)
            }
            guard let focused = try await captureUI(execution, { LoupeAgent().inputFocus(testID: testID) }) else {
                return ResponsePayload(status: 404, body: #"{"error":"input_not_found"}"#)
            }
            return jsonPayload(["focused": focused], failureCode: "input_focus_encoding_failed")
            #else
            return ResponsePayload(status: 404, body: #"{"error":"not_found"}"#)
            #endif
        default:
            return ResponsePayload(status: 404, body: #"{"error":"not_found"}"#)
        }
    }

    private func captureUI<Value: Sendable>(
        _ execution: RequestExecution,
        _ body: @escaping @MainActor @Sendable () throws -> Value
    ) async throws -> Value {
        try await MainActor.run {
            try execution.claimUIExecution()
            return try body()
        }
    }

    private func jsonPayload<Value: Encodable & Sendable>(
        _ value: Value,
        failureCode: String
    ) -> ResponsePayload {
        do {
            let data = try makeLoupeJSONEncoder().encode(value)
            return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
        } catch {
            return ResponsePayload(status: 500, body: errorBody(failureCode, error: error))
        }
    }

    private func errorBody(_ code: String, error: Error) -> String {
        errorBody(code, message: String(describing: error))
    }

    private func errorBody(_ code: String, message: String) -> String {
        let body = ErrorBody(error: code, message: message)
        guard let data = try? makeLoupeJSONEncoder().encode(body) else {
            return #"{"error":"internal_error"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func selector(from queryItems: [String: String]) -> LoupeSelector? {
        if let testID = queryItems["testID"] ?? queryItems["test-id"] {
            return .testID(testID)
        }
        if let ref = queryItems["ref"] {
            return .ref(ref)
        }
        if let text = queryItems["text"] {
            return .text(text, exact: false)
        }
        if let role = queryItems["role"] {
            return .role(role)
        }
        return nil
    }

    private func point(from queryItems: [String: String]) throws -> LoupePoint {
        if let point = queryItems["point"] {
            let parts = point.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0]),
                  let y = Double(parts[1]) else {
                throw LoupeDiagnosticError(message: "Expected point as x,y")
            }
            return LoupePoint(x: x, y: y)
        }

        guard let rawX = queryItems["x"], let rawY = queryItems["y"],
              let x = Double(rawX), let y = Double(rawY) else {
            throw LoupeDiagnosticError(message: "Expected --point x,y or --x <n> --y <n>")
        }
        return LoupePoint(x: x, y: y)
    }
}

private final class RequestExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    private var operation: Task<Void, Never>?
    private var cancelled = false
    /// Claims the synchronous MainActor section.  Cancellation and this claim
    /// share one lock so a deadline that wins the race cannot later permit a
    /// queued mutation to begin.
    func claimUIExecution() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !Task.isCancelled else {
            throw CancellationError()
        }
        didStart = true
    }
    func setOperation(_ operation: Task<Void, Never>) {
        lock.lock()
        self.operation = operation
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { operation.cancel() }
    }
    @discardableResult
    func cancel() -> Bool {
        lock.lock()
        cancelled = true
        let operation = operation
        let didStart = didStart
        lock.unlock()
        operation?.cancel()
        return didStart
    }
}

private final class RequestCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ResponsePayload, Never>?
    private var deadline: Task<Void, Never>?

    init(continuation: CheckedContinuation<ResponsePayload, Never>) {
        self.continuation = continuation
    }

    func setDeadline(_ deadline: Task<Void, Never>) {
        lock.lock()
        self.deadline = deadline
        let complete = continuation == nil
        lock.unlock()
        if complete { deadline.cancel() }
    }

    func resolve(_ payload: ResponsePayload) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let deadline = self.deadline
        self.deadline = nil
        lock.unlock()
        deadline?.cancel()
        continuation?.resume(returning: payload)
    }
}


private struct ErrorBody: Encodable, Sendable {
    var error: String
    var message: String
}

#endif
