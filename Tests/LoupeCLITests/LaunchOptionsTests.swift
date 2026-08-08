@testable import LoupeCLI
import Foundation
import LoupeCore
import Testing

@Suite struct LaunchOptionsTests {
    @Test func udidAliasesDevice() throws {
        let options = try LaunchOptions([
            "--bundle-id", "com.apple.Preferences",
            "--udid", "SIM-UDID",
        ])

        #expect(options.device == "SIM-UDID")
    }

    @Test func linkedLaunchParsesPhysicalDeviceRuntimeOptions() throws {
        let options = try LaunchOptions([
            "--bundle-id", "dev.loupe.readingnow",
            "--device", "DEVICE-1",
            "--linked",
            "--host", "http://192.168.1.25:8765",
            "--port", "8765",
            "--bind-host", "0.0.0.0",
        ])

        #expect(options.shouldInject == false)
        #expect(options.device == "DEVICE-1")
        #expect(options.host?.absoluteString == "http://192.168.1.25:8765")
        #expect(options.port == 8765)
        #expect(options.bindHost == "0.0.0.0")
    }

    @Test func linkedLaunchRejectsInjectionModeMixing() {
        #expect(throws: Error.self) {
            _ = try LaunchOptions([
                "--bundle-id", "dev.loupe.readingnow",
                "--linked",
                "--inject",
            ])
        }
    }

    @Test func macOSLaunchParsesAppBundle() throws {
        let options = try LaunchOptions([
            "--bundle-id", "dev.loupe.macos-example",
            "--macos-app", "/Applications/LoupeExample.app",
            "--port", "28746",
        ])

        #expect(options.macOSAppPath == "/Applications/LoupeExample.app")
        #expect(options.shouldInject == false)
        #expect(options.port == 28746)
    }

    @Test func macOSLaunchRejectsSimulatorDeviceSelection() {
        #expect(throws: Error.self) {
            _ = try LaunchOptions([
                "--bundle-id", "dev.loupe.macos-example",
                "--macos-app", "/Applications/LoupeExample.app",
                "--device", "SIM-UDID",
            ])
        }
    }

    @Test func linkedRuntimeRecordUsesDeviceIdentifierWhenSimulatorUDIDIsAbsent() {
        let state = LoupeRuntimeState(
            identity: LoupeRuntimeIdentity(
                platform: "iOS",
                deviceIdentifier: "DEVICE-1",
                deviceName: "iPhone",
                bundleIdentifier: "dev.loupe.readingnow",
                processIdentifier: 42
            )
        )
        let host = URL(string: "http://192.168.1.25:8765")!

        let record = LoupeCLI.runtimeHostRecord(
            state: state,
            host: host,
            fallbackDeviceID: "fallback-device",
            fallbackBundleID: "fallback.bundle"
        )

        #expect(record.udid == "DEVICE-1")
        #expect(record.bundleID == "dev.loupe.readingnow")
        #expect(LoupeCLI.runtimeState(state, matches: record))
    }

    @Test func linkedRuntimeMatchCanFallBackToBundleWhenDeviceIdentifierIsUnknown() {
        let state = LoupeRuntimeState(
            identity: LoupeRuntimeIdentity(
                platform: "iOS",
                bundleIdentifier: "dev.loupe.readingnow",
                processIdentifier: 42
            )
        )
        let record = LoupeRuntimeHostRecord(
            udid: "DEVICE-1",
            bundleID: "dev.loupe.readingnow",
            host: "http://192.168.1.25:8765",
            updatedAt: Date()
        )

        #expect(LoupeCLI.runtimeState(state, matches: record))
    }

    @Test func bootedResolutionPrefersIPhoneWhenMultiplePlatformsAreBooted() throws {
        let device = try #require(LoupeCLI.preferredBootedDevice(in: [
            "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [
                ["name": "Apple TV 4K", "state": "Booted", "udid": "TV-UDID"],
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                ["name": "iPhone 16 Pro", "state": "Booted", "udid": "PHONE-UDID"],
            ],
        ]))

        #expect(device["udid"] as? String == "PHONE-UDID")
    }

    @Test func bootedResolutionKeepsSingleBootedNonIPhoneDevice() throws {
        let device = try #require(LoupeCLI.preferredBootedDevice(in: [
            "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [
                ["name": "Apple TV 4K", "state": "Booted", "udid": "TV-UDID"],
            ],
        ]))

        #expect(device["udid"] as? String == "TV-UDID")
    }

    @Test func bootedResolutionRejectsMultipleBootedPhones() {
        let device = LoupeCLI.preferredBootedDevice(in: [
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                ["name": "iPhone 16 Pro", "state": "Booted", "udid": "PHONE-1"],
                ["name": "iPhone 15", "state": "Booted", "udid": "PHONE-2"],
            ],
            "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [
                ["name": "Apple TV 4K", "state": "Booted", "udid": "TV-UDID"],
            ],
        ])

        #expect(device == nil)
    }

    @Test func terminateTimeoutDefaultsToLaunchTimeout() {
        #expect(LoupeCLI.simctlTerminateTimeout(launchTimeout: 12, environment: [:]) == 12)
    }

    @Test func terminateTimeoutCanUseEnvironmentOverride() {
        #expect(
            LoupeCLI.simctlTerminateTimeout(
                launchTimeout: 12,
                environment: ["LOUPE_SIMCTL_TERMINATE_TIMEOUT": "25"]
            ) == 25
        )
    }

    @Test func invalidTerminateTimeoutFallsBackToLaunchTimeout() {
        #expect(
            LoupeCLI.simctlTerminateTimeout(
                launchTimeout: 12,
                environment: ["LOUPE_SIMCTL_TERMINATE_TIMEOUT": "0"]
            ) == 12
        )
        #expect(
            LoupeCLI.simctlTerminateTimeout(
                launchTimeout: 12,
                environment: ["LOUPE_SIMCTL_TERMINATE_TIMEOUT": "nope"]
            ) == 12
        )
    }
}
