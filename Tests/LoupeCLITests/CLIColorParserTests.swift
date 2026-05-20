@testable import LoupeCLI
import Testing

@Suite struct CLIColorParserTests {
    @Test func parsesHexColors() throws {
        let color = try CLIColorParser.color("#FDE2E4")

        #expect(abs(color.red - 253.0 / 255.0) < 0.001)
        #expect(abs(color.green - 226.0 / 255.0) < 0.001)
        #expect(abs(color.blue - 228.0 / 255.0) < 0.001)
        #expect(color.alpha == 1)
    }

    @Test func parsesBareHexColorsWithAlphaSuffix() throws {
        let color = try CLIColorParser.color("FFE4E6_0.5")

        #expect(color.red == 1)
        #expect(abs(color.green - 228.0 / 255.0) < 0.001)
        #expect(abs(color.blue - 230.0 / 255.0) < 0.001)
        #expect(color.alpha == 0.5)
    }

    @Test func parsesCommaSeparatedColors() throws {
        let color = try CLIColorParser.color("128,255,64,0.5")

        #expect(abs(color.red - 128.0 / 255.0) < 0.001)
        #expect(color.green == 1)
        #expect(abs(color.blue - 64.0 / 255.0) < 0.001)
        #expect(color.alpha == 0.5)
    }
}
