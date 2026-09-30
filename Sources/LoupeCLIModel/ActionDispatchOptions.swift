import Foundation
import LoupeCore

package protocol ActionDispatchOptions {
    var backend: String { get }
    var udid: String { get }
    var timeout: TimeInterval { get }
    var endPoint: LoupePoint? { get }
    var duration: Double? { get }
    var text: String? { get }
    var press: String? { get }
    var startSpread: Double? { get }
    var endSpread: Double? { get }
    var traceDirectory: URL? { get }
}

package extension ActionDispatchOptions {
    func requireEndPoint(command: String) throws -> LoupePoint {
        guard let endPoint else {
            throw CLIError("\(command) requires --to x,y")
        }
        return endPoint
    }
}
