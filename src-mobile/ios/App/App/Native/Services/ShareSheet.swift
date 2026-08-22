import SwiftUI
import UIKit
import LinkPresentation

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class ShareMetadataItemSource: NSObject, UIActivityItemSource {
    private let title: String
    private let text: String
    private let url: URL
    private let icon: UIImage

    init(title: String, text: String, url: URL, icon: UIImage) {
        self.title = title
        self.text = text
        self.url = url
        self.icon = icon
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        "\(text) \(url.absoluteString)"
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        "\(text) \(url.absoluteString)"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        metadata.iconProvider = NSItemProvider(object: icon)
        return metadata
    }
}
