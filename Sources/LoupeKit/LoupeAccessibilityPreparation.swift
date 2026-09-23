#if os(iOS)
import Darwin
import UIKit

@MainActor
enum LoupeAccessibilityPreparation {
    private static var didPrepare = false

    static func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LAZY | RTLD_LOCAL),
              let symbol = dlsym(library, "_AXSApplicationAccessibilitySetEnabled") else {
            return
        }
        typealias EnableAccessibility = @convention(c) (Int8) -> Void
        unsafeBitCast(symbol, to: EnableAccessibility.self)(1)

        let initialize = NSSelectorFromString("_accessibilityInit")
        if UIApplication.shared.responds(to: initialize) {
            _ = UIApplication.shared.perform(initialize)
        }
    }
}
#endif
