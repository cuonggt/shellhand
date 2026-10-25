import Foundation

/// What is already at the far end, and what to do about it.
///
/// Carrying a file onto one already there destroyed it, silently, with
/// nothing to undo. A download called `FileManager.createFile`, which
/// truncates; a copy between two local panes removed the destination first;
/// an upload's open-for-write truncates on the server. Three ways to lose a
/// file and no question asked in any of them — and a fourth that failed the
/// other way, a drop from Finder landing on an existing name doing nothing at
/// all because `copyItem` throws there and the `try?` swallowed it.
///
/// The rule lives here rather than with the bytes, so which names clash can
/// be worked out and tested without carrying one.
nonisolated enum Replacing {
    /// What to do about the names already there.
    enum Answer: String, Sendable, Equatable, CaseIterable {
        /// Carry everything, over the top of what is there.
        case replace
        /// Carry only what is not already there.
        case skip
    }

    /// The names being carried that the far end already has.
    ///
    /// `caseInsensitive` because the two ends usually disagree: this Mac's
    /// disk is case-insensitive by default and an SFTP server's usually is
    /// not. `README` arriving beside `readme` replaces it here and sits next
    /// to it there. Asked the wrong way round it either claims a clash where
    /// there is none — and a file silently not carried is as bad as one
    /// silently overwritten — or misses one, which is the bug this exists to
    /// close.
    static func clashes(
        carrying: [String], arriving: [String], caseInsensitive: Bool
    ) -> [String] {
        guard !carrying.isEmpty, !arriving.isEmpty else { return [] }
        let there = Set(caseInsensitive ? arriving.map { $0.lowercased() } : arriving)
        return carrying.filter { there.contains(caseInsensitive ? $0.lowercased() : $0) }
    }

    /// What is left to carry once the question has been answered.
    static func carrying(
        _ wanted: [String], clashes: [String], answer: Answer
    ) -> [String] {
        switch answer {
        case .replace:
            return wanted
        case .skip:
            // Compared as given: `clashes` came out of `wanted`, so the two
            // spellings already agree whatever the far end does about case.
            let leave = Set(clashes)
            return wanted.filter { !leave.contains($0) }
        }
    }

    /// One question for the whole batch rather than one per file: a drag of
    /// forty answered forty times is a dialog nobody reads by the fourth.
    static func question(_ clashes: [String], into place: String) -> String {
        clashes.count == 1
            ? "“\(clashes[0])” is already in \(place)."
            : "\(clashes.count) of these are already in \(place)."
    }
}
