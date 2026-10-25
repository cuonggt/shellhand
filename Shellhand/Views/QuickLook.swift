import AppKit
import QuickLookUI

/// The system Quick Look panel, for a file on this Mac.
///
/// It is the Mac answer to "what is in this file?" — space in Finder, ⌘Y
/// everywhere else — and it costs nothing to offer once a file has been
/// fetched. The panel has to be asked for from an app that is active, or it
/// opens behind whatever is in front.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()

    private var url: URL?

    func show(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
