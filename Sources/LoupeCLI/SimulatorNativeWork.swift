import Foundation

enum SimulatorNativeWork {
    // SimulatorKit can synchronously wait for Dispatch/XPC callbacks. Suspend
    // the Swift task instead of occupying its cooperative executor while the
    // native call waits. Task.detached still uses that same executor pool.
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }
}
