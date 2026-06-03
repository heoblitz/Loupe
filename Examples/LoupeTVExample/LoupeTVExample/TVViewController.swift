import UIKit
import LoupeCore
import LoupeKit
import Security

final class TVViewController: UIViewController {
    private let statusLabel = UILabel()
    private let legacyButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildView()
        publishRuntimeFixtures()
    }

    private func buildView() {
        view.accessibilityIdentifier = "tv.example.root"
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1)

        let title = UILabel()
        title.accessibilityIdentifier = "tv.example.title"
        title.text = "tvOS Loupe Workbench"
        title.textColor = .white
        title.font = .systemFont(ofSize: 54, weight: .bold)

        statusLabel.accessibilityIdentifier = "tv.example.status"
        statusLabel.text = "Runtime online"
        statusLabel.textColor = UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1)
        statusLabel.font = .systemFont(ofSize: 32, weight: .semibold)

        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "tv.example.refresh"
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Refresh snapshot"
        button.setTitle("Refresh snapshot", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        button.titleLabel?.font = .systemFont(ofSize: 34, weight: .semibold)
        button.addTarget(self, action: #selector(refreshStatus), for: .primaryActionTriggered)

        let secondaryButton = UIButton(type: .system)
        secondaryButton.accessibilityIdentifier = "tv.example.secondary"
        secondaryButton.isAccessibilityElement = true
        secondaryButton.accessibilityLabel = "Secondary action"
        secondaryButton.setTitle("Secondary action", for: .normal)
        secondaryButton.setTitleColor(.white, for: .normal)
        secondaryButton.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        secondaryButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)

        let logoutButton = UIButton(type: .system)
        logoutButton.accessibilityIdentifier = "tv.example.logout"
        logoutButton.isAccessibilityElement = true
        logoutButton.accessibilityLabel = "Logout"
        logoutButton.setTitle("Logout", for: .normal)
        logoutButton.setTitleColor(.white, for: .normal)
        logoutButton.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        logoutButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        logoutButton.addTarget(self, action: #selector(logout), for: .primaryActionTriggered)

        legacyButton.accessibilityIdentifier = "tv.example.legacyFlow"
        legacyButton.isAccessibilityElement = true
        legacyButton.accessibilityLabel = "Open legacy flow"
        legacyButton.setTitle("Open legacy flow", for: .normal)
        legacyButton.setTitleColor(.white, for: .normal)
        legacyButton.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        legacyButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        legacyButton.addTarget(self, action: #selector(openLegacyFlow), for: .primaryActionTriggered)

        let list = makeList()
        list.accessibilityIdentifier = "tv.example.collection"

        let emptyFeed = makeEmptyFeed()
        let badContrast = UILabel()
        badContrast.accessibilityIdentifier = "tv.example.dark.badContrast"
        badContrast.text = "Dark contrast sentinel"
        badContrast.textColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1)
        badContrast.font = .systemFont(ofSize: 28, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [
            title,
            statusLabel,
            button,
            secondaryButton,
            logoutButton,
            legacyButton,
            badContrast,
            list,
            emptyFeed,
        ])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 96),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -96),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
            list.heightAnchor.constraint(equalToConstant: 360),
            emptyFeed.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyFeed.heightAnchor.constraint(equalToConstant: 96),
        ])
    }

    private func makeList() -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(white: 1, alpha: 0.08)
        scrollView.layer.cornerRadius = 18

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        for index in 1...10 {
            let label = UILabel()
            label.accessibilityIdentifier = "tv.example.row.\(index)"
            label.text = "tvOS row \(index) - focus fixture"
            label.textColor = .white
            label.font = .systemFont(ofSize: 28, weight: .medium)
            content.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),
        ])

        return scrollView
    }

    private func makeEmptyFeed() -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "tv.example.emptyFeed"
        scrollView.backgroundColor = UIColor(white: 1, alpha: 0.08)
        scrollView.layer.cornerRadius = 18

        let placeholder = UILabel()
        placeholder.accessibilityIdentifier = "tv.example.emptyFeed.placeholder"
        placeholder.text = "No feed items"
        placeholder.textColor = UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1)
        placeholder.font = .systemFont(ofSize: 26, weight: .medium)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            placeholder.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
            placeholder.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            placeholder.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            placeholder.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),
        ])

        return scrollView
    }

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "tv-new-nav")
        UserDefaults.standard.set(true, forKey: "tv-empty-feed")

        Loupe.log(
            "tv_example_visible",
            metadata: [
                "screen": .string("workbench"),
                "platform": .string("tvOS"),
            ]
        )
        Loupe.log(
            "tv_example_empty_feed",
            metadata: [
                "screen": .string("feed"),
                "reason": .string("api_returned_empty_items"),
                "flag": .string("tv-empty-feed"),
            ]
        )
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.viewMetadata"),
            object: view,
            userInfo: [
                "metadata": [
                    "platform": "tvOS",
                    "fixture": true,
                ],
            ]
        )
        Loupe.recordNetwork(
            url: "https://api.example.test/tvos/workbench",
            method: "GET",
            statusCode: 200,
            responseBody: #"{"platform":"tvOS","status":"ok"}"#,
            metadata: ["screen": .string("workbench")]
        )
        Loupe.recordNetwork(
            url: "https://api.example.test/tvos/feed",
            method: "GET",
            statusCode: 204,
            responseBody: #"{"items":[]}"#,
            metadata: [
                "screen": .string("feed"),
                "empty": .bool(true),
            ]
        )
        Loupe.recordReference(
            owner: "TVWorkbenchController",
            target: "DeviceActuationService",
            kind: "strong",
            label: "fixture service reference",
            metadata: ["screen": .string("workbench")]
        )
        Loupe.recordReference(
            owner: "TVLegacyFlowCoordinator",
            target: "DeviceActuationService",
            kind: "weak",
            label: "legacy flow service observer",
            metadata: ["screen": .string("workbench")]
        )
        upsertKeychainFixture()
    }

    @objc private func refreshStatus() {
        statusLabel.text = "Snapshot refreshed"
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.log"),
            object: nil,
            userInfo: [
                "level": "info",
                "message": "tv_example_refresh_triggered",
                "metadata": ["screen": "workbench"],
            ]
        )
    }

    @objc private func logout() {
        deleteKeychainFixture()
        statusLabel.text = "Logged out"
        Loupe.log("tv_example_logout_cleared_keychain", metadata: ["screen": .string("workbench")])
    }

    @objc private func openLegacyFlow() {
        let newNavEnabled = UserDefaults.standard.bool(forKey: "tv-new-nav")
        if newNavEnabled {
            statusLabel.text = "New nav active"
            Loupe.log("tv_example_new_nav_flow", metadata: ["screen": .string("workbench")])
        } else {
            statusLabel.text = "Legacy flow active"
            Loupe.log("tv_example_legacy_flow", metadata: ["screen": .string("workbench")])
        }
    }

    private func upsertKeychainFixture() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.loupe.tvos-example",
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

    private func deleteKeychainFixture() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.loupe.tvos-example",
            kSecAttrAccount as String: "fixture",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
