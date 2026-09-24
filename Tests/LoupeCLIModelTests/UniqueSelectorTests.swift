@testable import LoupeCLIModel
import Testing

@Suite struct UniqueSelectorTests {
    @Test func rejectsRepeatedGenericValues() throws {
        var selector: String?
        try UniqueSelector.set("first", on: &selector)
        #expect(selector == "first")
        #expect(throws: (any Error).self) {
            try UniqueSelector.set("second", on: &selector)
        }
    }
}
