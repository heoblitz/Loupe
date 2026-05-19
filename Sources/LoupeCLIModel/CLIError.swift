package struct CLIError: Error, CustomStringConvertible, Equatable {
    package var description: String

    package init(_ description: String) {
        self.description = description
    }
}
