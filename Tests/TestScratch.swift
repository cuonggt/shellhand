import Foundation

/// Somewhere for a test to put a file, taken away when the run ends.
///
/// Every scratch store and scratch directory in the suite goes under **one**
/// root, and that root is removed by `atexit`. Each test used to leave its own
/// directory in the temporary one for ever: a day of runs left **4,843 of them
/// and 185MB**, which is harmless right up until somebody goes looking for
/// where the disk went. A crash skips `atexit`, so the worst case now is one
/// directory per run rather than one per test.
///
/// `nonisolated` so that any suite can reach it, MainActor or not.
nonisolated enum TestScratch {
    /// One directory for the whole run.
    static let root: String = {
        let path = NSTemporaryDirectory() + "shellhand-tests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)
        // `atexit` takes a C function and so captures nothing; the reference
        // below is to the global, which is initialised by the time it fires.
        atexit { try? FileManager.default.removeItem(atPath: TestScratch.root) }
        return path
    }()

    /// A directory of its own under that root, made and ready to be written in.
    static func directory(_ called: String = "d") -> String {
        let path = root + "/\(called)-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// A path for a database of its own, in a directory of its own — which is
    /// what GRDB wants, since it puts its journal beside the file.
    static func database(_ named: String = "shellhand.sqlite") -> String {
        directory("store") + "/" + named
    }
}
