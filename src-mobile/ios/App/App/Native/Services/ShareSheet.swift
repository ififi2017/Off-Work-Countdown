import UIKit
import LinkPresentation

/// Carries the share text and supplies the sheet's own header preview.
///
/// It deliberately never sets `LPLinkMetadata.url`. Setting it makes
/// UIActivityViewController go and fetch a rich preview over the network, and
/// until that returns the header is blank — which is why the first share of
/// every launch showed a white sheet with no icon and the second one, served
/// from cache, looked fine. Title plus a local image is all the header needs,
/// and it is ready synchronously.
final class ShareMetadataItemSource: NSObject, UIActivityItemSource {
    private let title: String
    private let text: String
    private let icon: UIImage

    init(title: String, text: String, icon: UIImage) {
        self.title = title
        self.text = text
        self.icon = icon
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: icon)
        metadata.iconProvider = NSItemProvider(object: icon)
        return metadata
    }
}

enum SystemShare {
    /// Presents the activity sheet on top of whatever is already showing.
    ///
    /// The composer is itself a sheet, and presenting `UIActivityViewController`
    /// from a nested SwiftUI `.sheet` is what produced the blank first sheet:
    /// the second presentation raced the first one's transition and came up
    /// before it had content. Handing it to UIKit's own top-most presenter
    /// sidesteps that entirely.
    @MainActor
    static func present(items: [Any]) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX,
            y: top.view.bounds.maxY - 80,
            width: 1,
            height: 1
        )
        top.present(controller, animated: true)
    }
}
