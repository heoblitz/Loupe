import Foundation
import LoupeCLIModel
import LoupeCore

struct LoupeTraceSummary: Codable {
    var directory: String
    var command: String?
    var phase: String?
    var selector: String?
    var target: ActionTargetTrace?
    var error: String?
    var diff: LoupeSnapshotDiff?
    var batchMutation: BatchMutationResult?
    var newLogs: [LoupeRuntimeLog]
    var failureLogs: [LoupeRuntimeLog]
    var targetCropPath: String?
}
