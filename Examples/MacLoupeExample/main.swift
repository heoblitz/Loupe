import AppKit
import LoupeCore
import LoupeKit

@main
enum MacLoupeExample {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        _ = delegate
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: LoupeServer?
    private var window: NSWindow?
    private let statusLabel = NSTextField(labelWithString: "Ready")

    func applicationDidFinishLaunching(_ notification: Notification) {
        startLoupeServer()
        buildWindow()
        publishRuntimeFixtures()
    }

    private func startLoupeServer() {
        let port = UInt16(ProcessInfo.processInfo.environment["LOUPE_PORT"] ?? "")
            ?? LoupeServer.defaultPort
        let server = LoupeServer()
        do {
            try server.start(port: port)
            self.server = server
            Loupe.log("mac_example_server_started", metadata: ["port": .int(Int(port))])
        } catch {
            fputs("MacLoupeExample failed to start LoupeServer: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("mac.example.window")
        window.title = "Mac Loupe Example"
        window.center()

        let root = NSView()
        root.testID("mac.example.root")
        root.testProperty("platform", "macOS")
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Mac Loupe Workbench")
        title.testID("mac.example.title")
        title.font = .systemFont(ofSize: 28, weight: .semibold)

        statusLabel.testID("mac.example.status")
        statusLabel.stringValue = "Runtime online"
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)

        let button = NSButton(title: "Refresh snapshot", target: self, action: #selector(refreshStatus))
        button.testID("mac.example.refresh")
        button.bezelStyle = .rounded

        let list = makeList()
        list.testID("mac.example.list")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(button)
        stack.addArrangedSubview(list)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
            list.heightAnchor.constraint(equalToConstant: 260),
        ])

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func makeList() -> NSScrollView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        for index in 1...12 {
            let row = NSTextField(labelWithString: "macOS row \(index) - runtime fixture")
            row.identifier = NSUserInterfaceItemIdentifier("mac.example.row.\(index)")
            row.font = .systemFont(ofSize: 15)
            content.addArrangedSubview(row)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -18),
        ])

        return scroll
    }

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "mac-new-nav")

        Loupe.log(
            "mac_example_visible",
            metadata: [
                "screen": .string("workbench"),
                "platform": .string("macOS"),
            ]
        )
        Loupe.recordNetwork(
            url: "https://api.example.test/macos/workbench",
            method: "GET",
            statusCode: 200,
            responseBody: #"{"platform":"macOS","status":"ok"}"#,
            metadata: ["screen": .string("workbench")]
        )
    }

    @objc private func refreshStatus() {
        statusLabel.stringValue = "Snapshot refreshed"
        Loupe.log("mac_example_refresh_tapped", metadata: ["screen": .string("workbench")])
    }
}
