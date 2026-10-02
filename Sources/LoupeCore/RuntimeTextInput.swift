public struct LoupeRuntimeTextInputRequest: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct LoupeRuntimeTextInputResponse: Codable, Equatable, Sendable {
    public var inserted: Bool

    public init(inserted: Bool) {
        self.inserted = inserted
    }
}
