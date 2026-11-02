import AppKit
import QuickLookUI

/// The system Quick Look panel, for a file on this Mac.
///
/// It is the Mac answer to "what is in this file?" — space in Finder, ⌘Y
/// everywhere else — and it costs nothing to offer once a file has been
/// fetched. The panel has to be asked for from an app that is active, or it
/// opens behind whatever is in front.
///
/// **The panel is asked for, not taken**: the window it is opened from
/// accepts control of it (`FilesWindowController`), and is handed it with
/// `take(_:)`. Setting its data source from here, in control or not, is
/// what its header says never to do.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()

    private var url: URL?

    func show(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The panel handed over by the window in control of it.
    func take(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.reloadData()
    }

    /// The panel taken back, by a window that is no longer in control.
    func handBack(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
