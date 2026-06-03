import UIKit
import LoupeKit

@main
final class TVAppDelegate: UIResponder, UIApplicationDelegate {
    private var loupeServer: LoupeServer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        startLoupeServer()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    private func startLoupeServer() {
        LoupeRuntime.shared.activateBridge()
        let port = UInt16(ProcessInfo.processInfo.environment["LOUPE_PORT"] ?? "")
            ?? LoupeServer.defaultPort
        let server = LoupeServer()
        do {
            try server.start(port: port)
            loupeServer = server
            Loupe.log("tv_example_server_started", metadata: ["port": .int(Int(port))])
        } catch {
            NSLog("LoupeTVExample failed to start LoupeServer: \(String(describing: error))")
        }
    }
}
