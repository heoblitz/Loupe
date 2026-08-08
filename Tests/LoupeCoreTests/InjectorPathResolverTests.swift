import Foundation
import Testing
@testable import LoupeCore

struct InjectorPathResolverTests {
    @Test func resolvePrefersExplicitEnvironmentPath() {
        let resolver = LoupeInjectorPathResolver(
            environment: ["LOUPE_INJECTOR_PATH": "/tmp/custom/LoupeInjector"],
            executableURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/loupe/0.1.0/bin/loupe"),
            fileExists: { $0 == "/tmp/custom/LoupeInjector" }
        )

        #expect(resolver.resolve() == "/tmp/custom/LoupeInjector")
    }

    @Test func resolveFindsHomebrewCellarRelativeInjector() {
        let expected = "/opt/homebrew/Cellar/loupe/0.1.0/libexec/LoupeInjector.framework/LoupeInjector"
        let resolver = LoupeInjectorPathResolver(
            environment: [:],
            executableURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/loupe/0.1.0/bin/loupe"),
            fileExists: { $0 == expected }
        )

        #expect(resolver.resolve() == expected)
    }

    @Test func resolveFallsBackToHomebrewOptPath() {
        let expected = "/opt/homebrew/opt/loupe/libexec/LoupeInjector.framework/LoupeInjector"
        let resolver = LoupeInjectorPathResolver(
            environment: [:],
            executableURL: nil,
            fileExists: { $0 == expected }
        )

        #expect(resolver.resolve() == expected)
    }

    @Test func resolveFindsMacOSInjectorBesideHomebrewCLI() {
        let expected = "/opt/homebrew/Cellar/loupe/0.1.0/libexec/LoupeInjector.framework/macos/LoupeInjector"
        let resolver = LoupeInjectorPathResolver(
            platform: .macOS,
            environment: [:],
            executableURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/loupe/0.1.0/bin/loupe"),
            fileExists: { $0 == expected }
        )

        #expect(resolver.resolve() == expected)
    }

    @Test func macOSResolvePrefersPlatformSpecificEnvironmentPath() {
        let resolver = LoupeInjectorPathResolver(
            platform: .macOS,
            environment: [
                "LOUPE_INJECTOR_PATH": "/tmp/ios/LoupeInjector",
                "LOUPE_MACOS_INJECTOR_PATH": "/tmp/macos/LoupeInjector",
            ],
            executableURL: nil,
            fileExists: { $0 == "/tmp/macos/LoupeInjector" }
        )

        #expect(resolver.resolve() == "/tmp/macos/LoupeInjector")
    }
}
