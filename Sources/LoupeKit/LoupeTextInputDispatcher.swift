import LoupeCore

#if canImport(UIKit) && os(iOS) && (DEBUG || targetEnvironment(simulator))
import UIKit

@MainActor
enum LoupeTextInputDispatcher {
    static func perform(_ request: LoupeRuntimeTextInputRequest) throws -> LoupeRuntimeTextInputResponse {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0 }
        guard let input = windows.lazy.compactMap({ firstResponder(in: $0) }).first else {
            throw LoupeMutationError(code: "text_input_not_focused", message: "A foreground text input must be first responder.")
        }
        // Insert literal text through the input protocol, preserving selection,
        // validation, and editing notifications without depending on key layout.
        input.insertText(request.text)
        return LoupeRuntimeTextInputResponse(inserted: true)
    }

    private static func firstResponder(in view: UIView) -> (any UIKeyInput)? {
        // Containers such as UISearchBar forward isFirstResponder to their
        // child without implementing UIKeyInput themselves.
        if view.isFirstResponder, let input = view as? any UIKeyInput { return input }
        return view.subviews.lazy.compactMap { firstResponder(in: $0) }.first
    }
}
#endif
