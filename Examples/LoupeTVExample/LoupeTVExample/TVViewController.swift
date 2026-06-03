import UIKit
import LoupeCore
import LoupeKit

final class TVViewController: UIViewController {
    private let statusLabel = UILabel()

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
        button.setTitle("Refresh snapshot", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 34, weight: .semibold)
        button.addTarget(self, action: #selector(refreshStatus), for: .primaryActionTriggered)

        let list = makeList()
        list.accessibilityIdentifier = "tv.example.collection"

        let stack = UIStackView(arrangedSubviews: [title, statusLabel, button, list])
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

    private func publishRuntimeFixtures() {
        UserDefaults.standard.set(false, forKey: "tv-new-nav")

        Loupe.log(
            "tv_example_visible",
            metadata: [
                "screen": .string("workbench"),
                "platform": .string("tvOS"),
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
}
