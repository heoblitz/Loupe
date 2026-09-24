@testable import LoupeCLI
import Testing

@Suite struct SelectorUniquenessTests {
    @Test func subtreeRejectsRepeatedSelectors() {
        #expect(throws: (any Error).self) {
            try SubtreeOptions(["/tmp/snapshot.json", "--ref", "n1", "--ref", "n2"])
        }
    }

    @Test func constraintsRejectsMixedSelectors() {
        #expect(throws: (any Error).self) {
            try ConstraintListOptions(["/tmp/snapshot.json", "--ref", "n1", "--role", "button"])
        }
    }

    @Test func mutationsRejectsMixedSelectors() {
        #expect(throws: (any Error).self) {
            try MutationListOptions(["--test-id", "card", "--text", "Pay"])
        }
    }

    @Test func setRejectsRepeatedSelectors() {
        #expect(throws: (any Error).self) {
            try MutationSetOptions(["--ref", "n1", "--ref", "n2", "alpha", "1"])
        }
    }

    @Test func setManyRejectsMixedSelectors() {
        #expect(throws: (any Error).self) {
            try BatchMutationOptions(["--refs", "n1,n2", "--role", "button", "alpha", "1"])
        }
    }
}
