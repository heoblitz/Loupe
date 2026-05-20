@testable import LoupeCLI
import Testing

@Suite struct MutationSetOptionsTests {
    @Test func setMutationsAnimateByDefault() throws {
        let options = try MutationSetOptions([
            "--test-id", "example.card",
            "frame",
            "20,120,220,80",
        ])

        #expect(options.request.animation?.duration == 0.25)
        #expect(options.request.animation?.delay == 0)
        #expect(options.request.animation?.curve == "easeInOut")
    }

    @Test func noAnimateDisablesSetMutationAnimation() throws {
        let options = try MutationSetOptions([
            "--test-id", "example.card",
            "text",
            "Updated",
            "--no-animate",
            "--duration", "0.4",
        ])

        #expect(options.request.animation == nil)
    }

    @Test func setMutationAnimationOptionsOverrideDefaults() throws {
        let options = try MutationSetOptions([
            "--test-id", "example.card",
            "alpha",
            "0.5",
            "--duration", "0.4",
            "--delay", "0.1",
            "--curve", "linear",
        ])

        #expect(options.request.animation?.duration == 0.4)
        #expect(options.request.animation?.delay == 0.1)
        #expect(options.request.animation?.curve == "linear")
    }

    @Test func numericTextValuesInferAsStrings() throws {
        let options = try MutationSetOptions([
            "--ref", "n20",
            "text",
            "20260519",
        ])

        #expect(options.request.value == .string("20260519"))
    }
}
