package enum UniqueSelector {
    package static func set<Value>(_ value: Value, on selector: inout Value?) throws {
        guard selector == nil else {
            throw CLIError("Provide exactly one selector; selector options cannot be combined or repeated")
        }
        selector = value
    }
}
