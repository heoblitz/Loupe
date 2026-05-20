import Foundation
import LoupeCore

struct BatchMutationResult: Codable {
    var host: String
    var elapsedMs: Int
    var selector: String
    var property: String
    var valueSequence: String
    var visibleOnly: Bool
    var yRange: String?
    var matchedTargets: Int
    var mutationRequests: Int
    var changedMutations: Int
    var verifiedTargets: Int
    var accuracy: Double
    var prevSnapshot: String
    var nextSnapshot: String
    var diff: String
    var targets: String
    var traceDirectory: String
}

struct BatchMutationTargetResult: Codable {
    var targetRef: String
    var mutationRefs: [String]
    var frame: LoupeRect?
    var verified: Bool
}
