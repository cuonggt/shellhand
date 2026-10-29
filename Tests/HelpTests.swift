import Foundation
import Testing
@testable import Shellhand

/// Where the Help menu sends somebody, and what a report carries.
@Suite("Help")
nonisolated struct HelpTests {
    @Test("Shellhand Help opens the README")
    func readme() {
        #expect(Help.readme.absoluteString == "https://github.com/cuonggt/shellhand#readme")
    }

    @Test("a report opens a new issue on this repository")
    func reportGoesToIssues() {
        let link = URLComponents(
            url: Help.report(version: "0.0.12", build: "12", system: "26.1.0"),
            resolvingAgainstBaseURL: false)
        #expect(link?.scheme == "https")
        #expect(link?.host == "github.com")
        #expect(link?.path == "/cuonggt/shellhand/issues/new")
    }

    /// The questions to answer and the version it came from — and nothing
    /// else, since a URL lives on in a browser's history.
    @Test("a report carries the questions and the version, and nothing more")
    func reportCarries() {
        let link = URLComponents(
            url: Help.report(version: "0.0.12", build: "12", system: "26.1.0"),
            resolvingAgainstBaseURL: false)
        #expect(link?.queryItems?.map(\.name) == ["body"])
        let body = link?.queryItems?.first?.value ?? ""
        #expect(body.contains("What happened:"))
        #expect(body.contains("What you expected instead:"))
        #expect(body.hasSuffix("Shellhand 0.0.12 (12) on macOS 26.1.0"))
    }

    @Test("what a report carries is encoded, not written raw into the link")
    func reportIsEncoded() {
        let text = Help.report(version: "0.0.12", build: "12", system: "26.1.0").absoluteString
        #expect(!text.contains(" "))
        #expect(!text.contains("\n"))
        #expect(text.contains("%0A"))
    }

    @Test("this copy reports its own version")
    func fromHere() {
        let body = URLComponents(url: Help.reportFromHere, resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        #expect(body.contains("Shellhand \(version) ("))
    }
}
