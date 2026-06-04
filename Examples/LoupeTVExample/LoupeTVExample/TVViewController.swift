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
        view.subviews.forEach { $0.removeFromSuperview() }
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

        let detailButton = UIButton(type: .system)
        detailButton.accessibilityIdentifier = "tv.example.openDetail"
        detailButton.isAccessibilityElement = true
        detailButton.accessibilityLabel = "Open detail route"
        detailButton.setTitle("Open detail route", for: .normal)
        detailButton.setTitleColor(.white, for: .normal)
        detailButton.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        detailButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        detailButton.addTarget(self, action: #selector(openDetailRoute), for: .primaryActionTriggered)

        let longListButton = UIButton(type: .system)
        longListButton.accessibilityIdentifier = "tv.example.openLongList"
        longListButton.isAccessibilityElement = true
        longListButton.accessibilityLabel = "Open long list route"
        longListButton.setTitle("Open long list route", for: .normal)
        longListButton.setTitleColor(.white, for: .normal)
        longListButton.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        longListButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        longListButton.addTarget(self, action: #selector(openLongListRoute), for: .primaryActionTriggered)

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
            detailButton,
            longListButton,
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

    private func buildRouteView(
        rootTestID: String,
        titleText: String,
        scrollTestID: String,
        rowPrefix: String,
        rows: Int
    ) {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.accessibilityIdentifier = rootTestID
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1)

        let title = UILabel()
        title.accessibilityIdentifier = "\(rootTestID).title"
        title.text = titleText
        title.textColor = .white
        title.font = .systemFont(ofSize: 54, weight: .bold)

        let back = UIButton(type: .system)
        back.accessibilityIdentifier = "\(rootTestID).back"
        back.isAccessibilityElement = true
        back.accessibilityLabel = "Back to workbench"
        back.setTitle("Back to workbench", for: .normal)
        back.setTitleColor(.white, for: .normal)
        back.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        back.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        back.addTarget(self, action: #selector(showWorkbenchRoute), for: .primaryActionTriggered)

        let summary = UILabel()
        summary.accessibilityIdentifier = "\(rootTestID).summary"
        summary.text = "Reached through tvOS remote routing"
        summary.textColor = UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1)
        summary.font = .systemFont(ofSize: 30, weight: .medium)

        let scroll = makeRouteScroll(testID: scrollTestID, rowPrefix: rowPrefix, rows: rows)

        let stack = UIStackView(arrangedSubviews: [title, back, summary, scroll])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 96),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -96),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 520),
        ])
        setNeedsFocusUpdate()
    }

    private func buildErrorRouteView() {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.accessibilityIdentifier = "tv.example.error"
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1)

        let title = UILabel()
        title.accessibilityIdentifier = "tv.example.error.title"
        title.text = "tvOS Error Route"
        title.textColor = .white
        title.font = .systemFont(ofSize: 54, weight: .bold)

        let subtitle = UILabel()
        subtitle.accessibilityIdentifier = "tv.example.error.subtitle"
        subtitle.text = "Workbench reload selected the error route after a 503 response."
        subtitle.textColor = UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1)
        subtitle.font = .systemFont(ofSize: 30, weight: .medium)

        let banner = UILabel()
        banner.accessibilityIdentifier = "tv.example.error.retryBanner"
        banner.text = "Retry available after feed service recovery"
        banner.textColor = UIColor(red: 1, green: 0.67, blue: 0.64, alpha: 1)
        banner.font = .systemFont(ofSize: 30, weight: .semibold)

        let back = UIButton(type: .system)
        back.accessibilityIdentifier = "tv.example.error.back"
        back.isAccessibilityElement = true
        back.accessibilityLabel = "Back to workbench"
        back.setTitle("Back to workbench", for: .normal)
        back.setTitleColor(.white, for: .normal)
        back.setTitleColor(UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1), for: .focused)
        back.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        back.addTarget(self, action: #selector(dismissErrorRoute), for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [title, subtitle, banner, back])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 96),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -96),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
        ])
        setNeedsFocusUpdate()
    }

    private func makeRouteScroll(testID: String, rowPrefix: String, rows: Int) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = testID
        scrollView.backgroundColor = UIColor(white: 1, alpha: 0.08)
        scrollView.layer.cornerRadius = 18

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        for index in 1...rows {
            let label = UILabel()
            label.accessibilityIdentifier = "\(rowPrefix).\(index)"
            label.text = "route row \(index)"
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

        let retry = UILabel()
        retry.accessibilityIdentifier = "tv.example.emptyFeed.retryBanner"
        retry.text = "Retry banner: API returned no rows"
        retry.textColor = UIColor(red: 0.74, green: 0.91, blue: 1, alpha: 1)
        retry.font = .systemFont(ofSize: 24, weight: .semibold)
        retry.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(retry)

        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            placeholder.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
            placeholder.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            placeholder.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),
            retry.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            retry.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
            retry.topAnchor.constraint(equalTo: placeholder.bottomAnchor, constant: 8),
            retry.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            retry.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),
        ])

        return scrollView
    }

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "tv-new-nav")
        UserDefaults.standard.set(true, forKey: "tv-empty-feed")
        UserDefaults.standard.set(false, forKey: "tv-error-route")

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
        triggerNetworkFixtureRequests()
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

    private func triggerNetworkFixtureRequests() {
        LoupeRuntime.shared.activateBridge()
        let session = URLSession(configuration: .default)
        let port = UInt16(ProcessInfo.processInfo.environment["LOUPE_PORT"] ?? "")
            ?? LoupeServer.defaultPort
        let baseURL = "http://127.0.0.1:\(port)/__loupe_network_fixture/tvos"
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
        if UserDefaults.standard.bool(forKey: "tv-error-route") {
            buildErrorRouteView()
            Loupe.log(
                "tv_example_error_route",
                metadata: [
                    "screen": .string("error"),
                    "reason": .string("feed_service_unavailable"),
                    "source": .string("tv-error-route"),
                ]
            )
            return
        }
        let newNavEnabled = UserDefaults.standard.bool(forKey: "tv-new-nav")
        if newNavEnabled {
            statusLabel.text = "New nav active"
            Loupe.log("tv_example_new_nav_flow", metadata: ["screen": .string("workbench")])
        } else {
            statusLabel.text = "Legacy flow active"
            Loupe.log("tv_example_legacy_flow", metadata: ["screen": .string("workbench")])
        }
    }

    @objc private func openDetailRoute() {
        buildRouteView(
            rootTestID: "tv.example.detail",
            titleText: "tvOS Detail Route",
            scrollTestID: "tv.example.detail.scroll",
            rowPrefix: "tv.example.detail.row",
            rows: 18
        )
        Loupe.log("tv_example_detail_route", metadata: ["screen": .string("detail")])
    }

    @objc private func openLongListRoute() {
        buildRouteView(
            rootTestID: "tv.example.longList",
            titleText: "tvOS Long List",
            scrollTestID: "tv.example.longList.scroll",
            rowPrefix: "tv.example.longList.row",
            rows: 42
        )
        Loupe.log("tv_example_long_list_route", metadata: ["screen": .string("longList")])
    }

    @objc private func showWorkbenchRoute() {
        buildView()
        Loupe.log("tv_example_workbench_route", metadata: ["screen": .string("workbench")])
    }

    @objc private func dismissErrorRoute() {
        UserDefaults.standard.set(false, forKey: "tv-error-route")
        showWorkbenchRoute()
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
