import SwiftUI
import UIKit

struct SpokeBackSwipeSupport: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BackSwipeController {
        BackSwipeController()
    }

    func updateUIViewController(_ controller: BackSwipeController, context: Context) {
        controller.enableBackSwipe()
    }
}

final class BackSwipeController: UIViewController {
    private weak var originalDelegate: UIGestureRecognizerDelegate?
    private weak var gesture: UIGestureRecognizer?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableBackSwipe()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        gesture?.delegate = originalDelegate
    }

    func enableBackSwipe() {
        guard let navigationController,
              navigationController.viewControllers.count > 1,
              let backGesture = navigationController.interactivePopGestureRecognizer
        else { return }

        if backGesture.delegate != nil {
            originalDelegate = backGesture.delegate
        }
        gesture = backGesture
        // The system disables swipe-back when its automatic back button is hidden.
        backGesture.delegate = nil
        backGesture.isEnabled = true
    }
}
