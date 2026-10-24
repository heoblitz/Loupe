import AppKit
import Security
import SwiftUI

private let loupeDefaultPort: UInt16 = 8765

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
    private var window: NSWindow?
    private let deviceActuationService = DeviceActuationService()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private var flagPollTimer: Timer?
    private var lastNewNavValue = false
    private var lastErrorRouteValue = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        publishRuntimeFixtures()
        startFlagMonitor()
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
        window.contentView = makeWorkbenchView()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func makeWorkbenchView() -> NSView {
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
        if statusLabel.stringValue == "Ready" {
            statusLabel.stringValue = "Runtime online"
        }
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)

        let button = NSButton(title: "Refresh snapshot", target: self, action: #selector(refreshStatus))
        button.testID("mac.example.refresh")
        button.bezelStyle = .rounded

        let detailButton = NSButton(title: "Open detail route", target: self, action: #selector(openDetailRoute))
        detailButton.testID("mac.example.openDetail")
        detailButton.bezelStyle = .rounded

        let longListButton = NSButton(title: "Open long list", target: self, action: #selector(openLongListRoute))
        longListButton.testID("mac.example.openLongList")
        longListButton.bezelStyle = .rounded

        let swiftUIButton = NSButton(title: "Open SwiftUI route", target: self, action: #selector(openSwiftUIRoute))
        swiftUIButton.testID("mac.example.openSwiftUI")
        swiftUIButton.bezelStyle = .rounded

        let list = makeList()
        list.testID("mac.example.list")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(button)
        stack.addArrangedSubview(NSStackView(views: [detailButton, longListButton, swiftUIButton]))
        stack.addArrangedSubview(makeDiagnosticControls())
        stack.addArrangedSubview(makeNativeAccessibilityFixture())
        stack.addArrangedSubview(makeSwiftUIFixture())
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

        return root
    }

    private func makeDetailView() -> NSView {
        let root = routeRoot(testID: "mac.example.detail")
        let stack = routeStack(in: root)

        let title = NSTextField(labelWithString: "macOS Detail Route")
        title.testID("mac.example.detail.title")
        title.font = .systemFont(ofSize: 26, weight: .semibold)

        let back = NSButton(title: "Back to workbench", target: self, action: #selector(showWorkbenchRoute))
        back.testID("mac.example.detail.back")
        back.bezelStyle = .rounded

        let summary = NSTextField(labelWithString: "Detail screen reached through runtime activation")
        summary.testID("mac.example.detail.summary")
        summary.font = .systemFont(ofSize: 16, weight: .medium)

        let scroll = makeRouteScroll(testID: "mac.example.detail.scroll", rowPrefix: "mac.example.detail.row", rows: 18)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(back)
        stack.addArrangedSubview(summary)
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 300),
        ])
        return root
    }

    private func makeLongListView() -> NSView {
        let root = routeRoot(testID: "mac.example.longList")
        let stack = routeStack(in: root)

        let title = NSTextField(labelWithString: "macOS Long List")
        title.testID("mac.example.longList.title")
        title.font = .systemFont(ofSize: 26, weight: .semibold)

        let back = NSButton(title: "Back to workbench", target: self, action: #selector(showWorkbenchRoute))
        back.testID("mac.example.longList.back")
        back.bezelStyle = .rounded

        let scroll = makeRouteScroll(testID: "mac.example.longList.scroll", rowPrefix: "mac.example.longList.row", rows: 36)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(back)
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 420),
        ])
        return root
    }

    private func makeSwiftUIRouteView() -> NSView {
        let root = routeRoot(testID: "mac.example.swiftuiRoute")
        let stack = routeStack(in: root)

        let back = NSButton(title: "Back to workbench", target: self, action: #selector(showWorkbenchRoute))
        back.testID("mac.example.swiftuiRoute.back")
        back.bezelStyle = .rounded

        let host = NSHostingView(rootView: MacSwiftUIScreenView())
        host.testID("mac.example.swiftuiRoute.host")
        host.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(back)
        stack.addArrangedSubview(host)
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalTo: stack.widthAnchor),
            host.heightAnchor.constraint(equalToConstant: 430),
        ])
        return root
    }

    private func makeErrorView() -> NSView {
        let root = routeRoot(testID: "mac.example.error")
        let stack = routeStack(in: root)

        let title = NSTextField(labelWithString: "macOS Error Route")
        title.testID("mac.example.error.title")
        title.font = .systemFont(ofSize: 26, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Workbench reload selected the error route after a 503 response.")
        subtitle.testID("mac.example.error.subtitle")
        subtitle.font = .systemFont(ofSize: 16, weight: .medium)

        let banner = NSTextField(labelWithString: "Retry available after feed service recovery")
        banner.testID("mac.example.error.retryBanner")
        banner.font = .systemFont(ofSize: 15, weight: .semibold)
        banner.textColor = .systemRed

        let back = NSButton(title: "Back to workbench", target: self, action: #selector(dismissErrorRoute))
        back.testID("mac.example.error.back")
        back.bezelStyle = .rounded

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(back)
        return root
    }

    private func routeRoot(testID: String) -> NSView {
        let root = NSView()
        root.testID(testID)
        root.testProperty("platform", "macOS")
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return root
    }

    private func routeStack(in root: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
        ])
        return stack
    }

    private func makeRouteScroll(testID: String, rowPrefix: String, rows: Int) -> NSScrollView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        for index in 1...rows {
            let row = NSTextField(labelWithString: "route row \(index)")
            row.identifier = NSUserInterfaceItemIdentifier("\(rowPrefix).\(index)")
            row.font = .systemFont(ofSize: 15)
            content.addArrangedSubview(row)
        }

        let scroll = NSScrollView()
        scroll.testID(testID)
        scroll.hasVerticalScroller = true
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -18),
        ])

        return scroll
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
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false

        let placeholder = NSTextField(labelWithString: "No feed items")
        placeholder.testID("mac.example.emptyFeed.placeholder")
        placeholder.font = .systemFont(ofSize: 14, weight: .medium)
        placeholder.textColor = .secondaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let retry = NSTextField(labelWithString: "Retry banner: API returned no rows")
        retry.testID("mac.example.emptyFeed.retryBanner")
        retry.font = .systemFont(ofSize: 13, weight: .semibold)
        retry.textColor = .secondaryLabelColor
        retry.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(placeholder)
        content.addArrangedSubview(retry)

        let scroll = NSScrollView()
        scroll.testID("mac.example.emptyFeed")
        scroll.hasVerticalScroller = false
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -18),
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

    private func makeSwiftUIFixture() -> NSView {
        let host = NSHostingView(rootView: MacSwiftUIFixtureView())
        host.testID("mac.example.swiftui.host")
        host.widthAnchor.constraint(equalToConstant: 280).isActive = true
        host.heightAnchor.constraint(equalToConstant: 92).isActive = true
        return host
    }

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "mac-new-nav")
        UserDefaults.standard.set(true, forKey: "mac-empty-feed")
        UserDefaults.standard.set(false, forKey: "mac-error-route")
        UserDefaults.standard.set(false, forKey: "mac-logout")
        lastNewNavValue = UserDefaults.standard.bool(forKey: "mac-new-nav")
        lastErrorRouteValue = UserDefaults.standard.bool(forKey: "mac-error-route")

        loupeLog(
            "mac_example_visible",
            metadata: [
                "screen": "workbench",
                "platform": "macOS",
            ]
        )
        loupeLog(
            "mac_example_empty_feed",
            metadata: [
                "screen": "feed",
                "reason": "api_returned_empty_items",
                "flag": "mac-empty-feed",
            ]
        )
        triggerNetworkFixtureRequests()
        loupeReference(
            owner: "MacWorkbenchController",
            target: "DeviceActuationService",
            kind: "strong",
            label: "fixture service reference",
            metadata: ["screen": "workbench"]
        )
        loupeReference(
            owner: "MacLegacyFlowCoordinator",
            target: "DeviceActuationService",
            kind: "weak",
            label: "legacy flow service observer",
            metadata: ["screen": "workbench"]
        )
        loupeLifetimeProbe(
            deviceActuationService,
            name: "DeviceActuationService",
            expectedDeallocated: true,
            metadata: [
                "owner": "MacWorkbenchController",
                "screen": "workbench",
            ]
        )
        upsertKeychainFixture()
    }

    private func triggerNetworkFixtureRequests() {
        let session = URLSession(configuration: .default)
        let port = UInt16(ProcessInfo.processInfo.environment["LOUPE_PORT"] ?? "")
            ?? loupeDefaultPort
        let baseURL = "http://127.0.0.1:\(port)/__loupe_network_fixture/macos"
        [
            "\(baseURL)/workbench",
            "\(baseURL)/feed",
            "\(baseURL)/error-route",
        ].forEach { rawURL in
            guard let url = URL(string: rawURL) else {
                return
            }
            session.dataTask(with: url).resume()
        }
    }

    @objc private func refreshStatus() {
        statusLabel.stringValue = "Snapshot refreshed"
        loupeLog("mac_example_refresh_tapped", metadata: ["screen": "workbench"])
    }

    @objc private func openDetailRoute() {
        window?.contentView = makeDetailView()
        loupeLog("mac_example_detail_route", metadata: ["screen": "detail"])
    }

    @objc private func openLongListRoute() {
        window?.contentView = makeLongListView()
        loupeLog("mac_example_long_list_route", metadata: ["screen": "longList"])
    }

    @objc private func openSwiftUIRoute() {
        window?.contentView = makeSwiftUIRouteView()
        loupeLog("mac_example_swiftui_route", metadata: ["screen": "swiftUI"])
    }

    @objc private func showWorkbenchRoute() {
        window?.contentView = makeWorkbenchView()
        loupeLog("mac_example_workbench_route", metadata: ["screen": "workbench"])
    }

    @objc private func dismissErrorRoute() {
        UserDefaults.standard.set(false, forKey: "mac-error-route")
        lastErrorRouteValue = false
        showWorkbenchRoute()
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
                loupeLog("mac_example_new_nav_flow", metadata: ["screen": "workbench"])
            } else {
                statusLabel.stringValue = "Legacy flow active"
                loupeLog("mac_example_legacy_flow", metadata: ["screen": "workbench"])
            }
        }

        if UserDefaults.standard.bool(forKey: "mac-logout") {
            UserDefaults.standard.set(false, forKey: "mac-logout")
            clearKeychainFixture()
            statusLabel.stringValue = "Logged out"
            loupeLog("mac_example_logout_cleared_keychain", metadata: ["screen": "workbench"])
        }

        let errorRouteValue = UserDefaults.standard.bool(forKey: "mac-error-route")
        if errorRouteValue != lastErrorRouteValue {
            lastErrorRouteValue = errorRouteValue
            if errorRouteValue {
                window?.contentView = makeErrorView()
                loupeLog(
                    "mac_example_error_route",
                    metadata: [
                        "screen": "error",
                        "reason": "feed_service_unavailable",
                        "source": "mac-error-route",
                    ]
                )
            } else {
                showWorkbenchRoute()
            }
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

private extension NSView {
    func testID(_ id: String) {
        identifier = NSUserInterfaceItemIdentifier(id)
        setAccessibilityIdentifier(id)
    }

    func testProperty(_ key: String, _ value: String) {
        guard let id = identifier?.rawValue else {
            return
        }
        loupeViewMetadata(testID: id, metadata: [key: value])
    }

    func testProperty(_ key: String, _ value: Bool) {
        guard let id = identifier?.rawValue else {
            return
        }
        loupeViewMetadata(testID: id, metadata: [key: value])
    }
}

private func loupeLog(_ message: String, metadata: [String: Any] = [:]) {
    NotificationCenter.default.post(
        name: Notification.Name("dev.loupe.log"),
        object: nil,
        userInfo: [
            "level": "info",
            "message": message,
            "metadata": metadata,
        ]
    )
}

private func loupeViewMetadata(testID: String, metadata: [String: Any]) {
    NotificationCenter.default.post(
        name: Notification.Name("dev.loupe.viewMetadata"),
        object: nil,
        userInfo: [
            "testID": testID,
            "metadata": metadata,
        ]
    )
}

private func loupeReference(
    owner: String,
    target: String,
    kind: String,
    label: String,
    metadata: [String: Any] = [:]
) {
    NotificationCenter.default.post(
        name: Notification.Name("dev.loupe.reference"),
        object: nil,
        userInfo: [
            "owner": owner,
            "target": target,
            "kind": kind,
            "label": label,
            "metadata": metadata,
        ]
    )
}

private func loupeLifetimeProbe(
    _ object: AnyObject,
    name: String,
    expectedDeallocated: Bool,
    metadata: [String: Any] = [:]
) {
    NotificationCenter.default.post(
        name: Notification.Name("dev.loupe.lifetimeProbe"),
        object: object,
        userInfo: [
            "name": name,
            "expectedDeallocated": expectedDeallocated,
            "metadata": metadata,
        ]
    )
}

@objc(DeviceActuationService)
private final class DeviceActuationService: NSObject {}

private extension View {
    func localLoupeProbe(_ id: String, label: String? = nil) -> some View {
        background {
            LoupeFallbackProbeView(id: id, label: label)
        }
    }
}

private struct LoupeFallbackProbeView: NSViewRepresentable {
    let id: String
    let label: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(id)
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel(label ?? id)
        view.setAccessibilityRole(.group)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        publishSwiftUIMetadata(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(id)
        nsView.setAccessibilityElement(true)
        nsView.setAccessibilityLabel(label ?? id)
        nsView.setAccessibilityRole(.group)
        nsView.wantsLayer = true
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
        publishSwiftUIMetadata(for: nsView)
    }

    private func publishSwiftUIMetadata(for view: NSView) {
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.viewMetadata"),
            object: view,
            userInfo: [
                "metadata": [
                    "loupe.swiftUI": true,
                ],
            ]
        )
    }
}

private struct MacSwiftUIFixtureView: View {
    @State private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macOS SwiftUI Fixture")
                .font(.headline)
                .accessibilityIdentifier("mac.example.swiftui.title")

            Button(enabled ? "SwiftUI enabled" : "SwiftUI disabled") {
                enabled.toggle()
            }
            .accessibilityIdentifier("mac.example.swiftui.button")
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac.example.swiftui")
        .localLoupeProbe("mac.example.swiftui.probe", label: "macOS SwiftUI probe")
    }
}

private struct MacSwiftUIScreenView: View {
    @State private var enabled = true
    @State private var value = 0.42
    @State private var mode: String

    init() {
        // Keep this reflection fixture eager across SDKs that otherwise defer
        // default @State values in an opaque LazyState initializer closure.
        _mode = State(initialValue: "Inspect")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("macOS SwiftUI Route")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("mac.example.swiftuiRoute.title")

            Text("Private hierarchy and accessibility probe coverage")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mac.example.swiftuiRoute.subtitle")

            MacSwiftUIRouteControls(enabled: $enabled, value: $value, mode: $mode)

            Button(enabled ? "Disable route" : "Enable route") {
                enabled.toggle()
            }
            .accessibilityIdentifier("mac.example.swiftuiRoute.button")

            MacSwiftUIRouteRows()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac.example.swiftuiRoute.screen")
        .localLoupeProbe("mac.example.swiftuiRoute.probe", label: "macOS SwiftUI route probe")
    }
}

private struct MacSwiftUIRouteControls: View {
    @Binding var enabled: Bool
    @Binding var value: Double
    @Binding var mode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Route toggle", isOn: $enabled)
                .accessibilityIdentifier("mac.example.swiftuiRoute.toggle")

            Slider(value: $value)
                .frame(width: 220)
                .accessibilityIdentifier("mac.example.swiftuiRoute.slider")

            Picker("Mode", selection: $mode) {
                Text("Inspect").tag("Inspect")
                Text("Act").tag("Act")
                Text("Trace").tag("Trace")
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .accessibilityIdentifier("mac.example.swiftuiRoute.mode")

            ProgressView(value: value)
                .frame(width: 220)
                .accessibilityIdentifier("mac.example.swiftuiRoute.progress")
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("mac.example.swiftuiRoute.controls")
        .localLoupeProbe("mac.example.swiftuiRoute.controls", label: "macOS SwiftUI route controls")
    }
}

private struct MacSwiftUIRouteRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(1...3, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: index == 1 ? "checkmark.circle" : "circle")
                    Text("SwiftUI route row \(index)")
                }
                .accessibilityIdentifier("mac.example.swiftuiRoute.row.\(index)")
                .localLoupeProbe("mac.example.swiftuiRoute.row.\(index)", label: "macOS SwiftUI route row \(index)")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("mac.example.swiftuiRoute.rows")
        .localLoupeProbe("mac.example.swiftuiRoute.rows", label: "macOS SwiftUI route rows")
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
