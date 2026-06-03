import AppKit
import LoupeCore
import LoupeKit
import Security

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
    private var flagPollTimer: Timer?
    private var lastNewNavValue = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        startLoupeServer()
        buildWindow()
        publishRuntimeFixtures()
        startFlagMonitor()
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
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
        stack.addArrangedSubview(makeDiagnosticControls())
        stack.addArrangedSubview(makeNativeAccessibilityFixture())
        stack.addArrangedSubview(makeBadContrastLabel())
        stack.addArrangedSubview(list)
        stack.addArrangedSubview(makeEmptyFeed())

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
            list.heightAnchor.constraint(equalToConstant: 220),
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

    private func makeEmptyFeed() -> NSScrollView {
        let placeholder = NSTextField(labelWithString: "No feed items")
        placeholder.testID("mac.example.emptyFeed.placeholder")
        placeholder.font = .systemFont(ofSize: 14, weight: .medium)
        placeholder.textColor = .secondaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.testID("mac.example.emptyFeed")
        scroll.hasVerticalScroller = false
        scroll.documentView = placeholder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 52).isActive = true

        NSLayoutConstraint.activate([
            placeholder.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -18),
        ])

        return scroll
    }

    private func makeBadContrastLabel() -> NSView {
        let host = NSView()
        host.testID("mac.example.dark.badContrast.host")
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).cgColor
        host.translatesAutoresizingMaskIntoConstraints = false
        host.heightAnchor.constraint(equalToConstant: 24).isActive = true
        host.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let label = NSTextField(labelWithString: "Dark contrast sentinel")
        label.testID("mac.example.dark.badContrast")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.11, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])

        return host
    }

    private func makeDiagnosticControls() -> NSStackView {
        let segmented = NSSegmentedControl(labels: ["List", "Detail"], trackingMode: .selectOne, target: nil, action: nil)
        segmented.testID("mac.example.segmented")
        segmented.selectedSegment = 1

        let slider = NSSlider(value: 42, minValue: 0, maxValue: 100, target: nil, action: nil)
        slider.testID("mac.example.slider")
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let stepper = NSStepper(frame: .zero)
        stepper.testID("mac.example.stepper")
        stepper.minValue = 0
        stepper.maxValue = 10
        stepper.increment = 2
        stepper.doubleValue = 4

        let progress = NSProgressIndicator(frame: .zero)
        progress.testID("mac.example.progress")
        progress.isIndeterminate = false
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 65
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let image = NSImage(size: NSSize(width: 24, height: 24))
        let imageView = NSImageView(image: image)
        imageView.testID("mac.example.image")
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let row = NSStackView(views: [segmented, slider, stepper, progress, imageView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.testID("mac.example.diagnostics")
        return row
    }

    private func makeNativeAccessibilityFixture() -> NSView {
        let host = NativeAccessibilityHostView(actionTestID: "mac.example.nativeAX.action")
        host.testID("mac.example.nativeAX.host")
        host.widthAnchor.constraint(equalToConstant: 220).isActive = true
        host.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return host
    }

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "mac-new-nav")
        UserDefaults.standard.set(true, forKey: "mac-empty-feed")
        UserDefaults.standard.set(false, forKey: "mac-logout")
        lastNewNavValue = UserDefaults.standard.bool(forKey: "mac-new-nav")

        Loupe.log(
            "mac_example_visible",
            metadata: [
                "screen": .string("workbench"),
                "platform": .string("macOS"),
            ]
        )
        Loupe.log(
            "mac_example_empty_feed",
            metadata: [
                "screen": .string("feed"),
                "reason": .string("api_returned_empty_items"),
                "flag": .string("mac-empty-feed"),
            ]
        )
        Loupe.recordNetwork(
            url: "https://api.example.test/macos/workbench",
            method: "GET",
            statusCode: 200,
            responseBody: #"{"platform":"macOS","status":"ok"}"#,
            metadata: ["screen": .string("workbench")]
        )
        Loupe.recordNetwork(
            url: "https://api.example.test/macos/feed",
            method: "GET",
            statusCode: 204,
            responseBody: #"{"items":[]}"#,
            metadata: [
                "screen": .string("feed"),
                "empty": .bool(true),
            ]
        )
        Loupe.recordReference(
            owner: "MacWorkbenchController",
            target: "DeviceActuationService",
            kind: "strong",
            label: "fixture service reference",
            metadata: ["screen": .string("workbench")]
        )
        Loupe.recordReference(
            owner: "MacLegacyFlowCoordinator",
            target: "DeviceActuationService",
            kind: "weak",
            label: "legacy flow service observer",
            metadata: ["screen": .string("workbench")]
        )
        upsertKeychainFixture()
    }

    @objc private func refreshStatus() {
        statusLabel.stringValue = "Snapshot refreshed"
        Loupe.log("mac_example_refresh_tapped", metadata: ["screen": .string("workbench")])
    }

    private func startFlagMonitor() {
        flagPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyFlagDrivenRuntimeState()
            }
        }
    }

    private func applyFlagDrivenRuntimeState() {
        let newNavValue = UserDefaults.standard.bool(forKey: "mac-new-nav")
        if newNavValue != lastNewNavValue {
            lastNewNavValue = newNavValue
            if newNavValue {
                statusLabel.stringValue = "New nav active"
                Loupe.log("mac_example_new_nav_flow", metadata: ["screen": .string("workbench")])
            } else {
                statusLabel.stringValue = "Legacy flow active"
                Loupe.log("mac_example_legacy_flow", metadata: ["screen": .string("workbench")])
            }
        }

        if UserDefaults.standard.bool(forKey: "mac-logout") {
            UserDefaults.standard.set(false, forKey: "mac-logout")
            clearKeychainFixture()
            statusLabel.stringValue = "Logged out"
            Loupe.log("mac_example_logout_cleared_keychain", metadata: ["screen": .string("workbench")])
        }
    }

    private func upsertKeychainFixture() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.loupe.macos-example",
            kSecAttrAccount as String: "fixture",
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data("fixture-token".utf8),
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data("fixture-token".utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func clearKeychainFixture() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.loupe.macos-example",
            kSecAttrAccount as String: "fixture",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private final class NativeAccessibilityHostView: NSView {
    private let actionElement = NSAccessibilityElement()

    init(actionTestID: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        actionElement.setAccessibilityIdentifier(actionTestID)
        actionElement.setAccessibilityLabel("Native AX Action")
        actionElement.setAccessibilityValue("available")
        actionElement.setAccessibilityHelp("Runs the native accessibility fixture")
        actionElement.setAccessibilityRole(.button)
        actionElement.setAccessibilityElement(true)
        actionElement.setAccessibilityEnabled(true)
        actionElement.setAccessibilityParent(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        [actionElement]
    }

    override func layout() {
        super.layout()
        updateAccessibilityFrame()
    }

    private func updateAccessibilityFrame() {
        guard let window else {
            return
        }
        let localFrame = NSRect(x: 12, y: 6, width: max(bounds.width - 24, 1), height: max(bounds.height - 12, 1))
        let frameInWindow = convert(localFrame, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        actionElement.setAccessibilityFrame(frameInScreen)
        actionElement.setAccessibilityActivationPoint(NSPoint(x: frameInScreen.midX, y: frameInScreen.midY))
    }
}
