import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        if ProcessInfo.processInfo.environment["LOUPE_EXAMPLE_ROUTE"] == "bookmarks" {
            window.rootViewController = BookmarkTabController()
            window.makeKeyAndVisible()
            self.window = window
            return
        }

        let navigationController = UINavigationController(rootViewController: ViewController())
        navigationController.navigationBar.prefersLargeTitles = true
        applyInitialRoute(to: navigationController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }

    private func applyInitialRoute(to navigationController: UINavigationController) {
        let route = ProcessInfo.processInfo.environment["LOUPE_EXAMPLE_ROUTE"] ?? ""
        switch route {
        case "touch":
            navigationController.setViewControllers([TouchFixtureViewController()], animated: false)
        case "touch.swiftui":
            let controller = UIHostingController(rootView: TouchSwiftUIFixture())
            controller.navigationItem.largeTitleDisplayMode = .never
            navigationController.setViewControllers([controller], animated: false)
        case "detail":
            navigationController.pushViewController(
                DetailViewController(
                    item: ExampleItem(
                        index: 1,
                        title: "Customer 1",
                        subtitle: "Ready for review",
                        status: "Draft"
                    )
                ),
                animated: false
            )
        case "components":
            navigationController.pushViewController(ComponentsViewController(), animated: false)
        case "components.alert":
            navigationController.pushViewController(ComponentsViewController(presentAlertAfterAppear: true), animated: false)
        case "bottomSheet":
            navigationController.pushViewController(BottomSheetFixtureViewController(), animated: false)
        case "fixtures":
            navigationController.pushViewController(FixtureTabController(), animated: false)
        case "fixtures.swiftui":
            navigationController.pushViewController(FixtureTabController(initialSelectedIndex: 0), animated: false)
        case "fixtures.web":
            navigationController.pushViewController(FixtureTabController(initialSelectedIndex: 1), animated: false)
        case "fixtures.keyboard":
            navigationController.pushViewController(
                FixtureTabController(initialSelectedIndex: 2, autoFocusKeyboard: true),
                animated: false
            )
        case "fixtures.nested":
            navigationController.pushViewController(FixtureTabController(initialSelectedIndex: 3), animated: false)
        default:
            break
        }
    }
}
