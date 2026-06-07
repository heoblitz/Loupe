import Foundation
import LoupeCore

struct ApplyDesignSuggestionApplication: Codable, Equatable {
    var index: Int
    var issueKind: LoupeDesignComparisonIssueKind
    var designID: String?
    var designName: String?
    var originalRef: String
    var appliedRef: String?
    var appliedSelectorKind: String?
    var appliedSelectorValue: String?
    var property: String
    var valueType: String
    var valueLabel: String
    var changed: Bool?
    var warning: String?
    var response: String?
    var error: String?
}

struct ApplyDesignSuggestionsResult: Codable, Equatable {
    var host: String?
    var dryRun: Bool
    var compareDesign: String
    var referenceSnapshot: String?
    var outputDirectory: String
    var selectedSuggestions: Int
    var mutationRequests: Int
    var changedMutations: Int
    var failedMutations: Int
    var beforeSnapshot: String?
    var afterSnapshot: String?
    var diff: String?
    var responses: String?
    var applications: [ApplyDesignSuggestionApplication]
}
