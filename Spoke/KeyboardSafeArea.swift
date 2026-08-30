import SwiftUI
import UIKit

extension View {
    func disablesKeyboardSafeArea() -> some View {
        background {
            KeyboardSafeAreaDisabler()
                .frame(width: 0, height: 0)
        }
    }
}

private struct KeyboardSafeAreaDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> KeyboardSafeAreaDisablingViewController {
        KeyboardSafeAreaDisablingViewController()
    }

    func updateUIViewController(
        _ uiViewController: KeyboardSafeAreaDisablingViewController,
        context: Context
    ) {}
}

private final class KeyboardSafeAreaDisablingViewController: UIViewController {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)

        var ancestor = parent
        while let current = ancestor {
            if let hostingController = current as? KeyboardSafeAreaConfiguring {
                hostingController.disableKeyboardSafeArea()
                return
            }
            ancestor = current.parent
        }
    }
}

@MainActor
private protocol KeyboardSafeAreaConfiguring: AnyObject {
    func disableKeyboardSafeArea()
}

extension UIHostingController: KeyboardSafeAreaConfiguring {
    fileprivate func disableKeyboardSafeArea() {
        safeAreaRegions.remove(.keyboard)
    }
}
