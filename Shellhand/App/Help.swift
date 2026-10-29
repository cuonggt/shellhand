import Foundation

/// Where the Help menu sends somebody: the README, and a new issue on the
/// repository already holding what a report needs.
///
/// The link is made here rather than in the menu so what it carries can be
/// checked without opening a browser — and what it carries is deliberately
/// little: the version, the build and the system. Nothing about anybody's
/// hosts goes into a URL that a browser keeps in its history.
nonisolated enum Help {
    static let readme = URL(string: "https://github.com/cuonggt/shellhand#readme")!

    /// A new issue, its body asking the two questions every report needs
    /// answered and signed with what the app knows about itself. No title:
    /// GitHub asks for one, and a title written here would be a guess.
    static func report(version: String, build: String, system: String) -> URL {
        var link = URLComponents(string: "https://github.com/cuonggt/shellhand/issues/new")!
        link.queryItems = [URLQueryItem(name: "body", value: """
            What happened:


            What you expected instead:


            Shellhand \(version) (\(build)) on macOS \(system)
            """)]
        return link.url!
    }

    /// The same, for this copy on this Mac.
    static var reportFromHere: URL {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return report(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
}
