import SwiftUI
import UIKit

@MainActor
enum ShareSheetPresenter {
    static func present(items: [Any], onDismiss: (() -> Void)? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = topVC.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0
        )
        activity.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        topVC.present(activity, animated: true)
    }
}
