import Foundation

/// Where the Help menu sends somebody: the README, and the repository's
/// problem form with what the app knows about itself already filled in.
///
/// The link is made here rather than in the menu so what it carries can be
/// checked without opening a browser — and what it carries is deliberately
/// little: the version, the build and the system. Nothing about anybody's
/// hosts goes into a URL that a browser keeps in its history.
nonisolated enum Help {
    static let readme = URL(string: "https://github.com/cuonggt/shellhand#readme")!

    /// The problem form, `.github/ISSUE_TEMPLATE/problem.yml`, with its
    /// version and macOS fields filled in: GitHub fills a form's field from
    /// the query item named for its `id`. The form asks the two questions
    /// every report needs answered. No title: GitHub asks for one, and a
    /// title written here would be a guess.
    ///
    /// **Those ids are as permanent as the feed's URL.** A build opens the
    /// link it was born with for ever, so renaming a field in the form
    /// leaves it empty in every report from a copy already out — `HelpTests`
    /// reads the form and holds the two to each other. 0.1.0 shipped a blank
    /// issue with the questions in its body instead, which is why the
    /// template config keeps blank issues allowed.
    static func report(version: String, build: String, system: String) -> URL {
        var link = URLComponents(string: "https://github.com/cuonggt/shellhand/issues/new")!
        link.queryItems = [
            URLQueryItem(name: "template", value: "problem.yml"),
            URLQueryItem(name: "version", value: "\(version) (\(build))"),
            URLQueryItem(name: "macos", value: system),
        ]
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
