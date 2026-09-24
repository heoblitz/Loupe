import Testing
@testable import LoupeCLI

struct TreeOutputTests {
    @Test func defaultBudgetBoundsWideTreesAndReportsOmissions() throws {
        let input = (1...250).map { "node \($0)" }.joined(separator: "\n")
        let output = TreeOutput.bounded(input, limit: try TreeOptions([]).limit)
        #expect(output.split(separator: "\n").count == 81)
        #expect(output.contains("node 80\n"))
        #expect(!output.contains("node 81\n"))
        #expect(output.contains("omitted 170 lines"))
        #expect(TreeOutput.bounded(input, limit: try TreeOptions(["--all"]).limit) == input)
    }

    @Test func longLinesAreBoundedWithoutLosingFullOutputOption() throws {
        let input = "n1 " + String(repeating: "가", count: 1000)
        let output = TreeOutput.bounded(input, limit: 80)
        #expect(output.split(separator: "\n").first?.count == 240)
        #expect(output.contains("long lines shortened"))
        #expect(TreeOutput.bounded(input, limit: nil) == input)
        #expect(try TreeOptions(["--limit", "5"]).limit == 5)
        #expect(throws: (any Error).self) { try TreeOptions(["--limit", "0"]) }
        #expect(throws: (any Error).self) { try TreeOptions(["--all", "--limit", "5"]) }
    }
}
