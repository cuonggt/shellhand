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

    /// The form, the version and the system — and nothing else, since a URL
    /// lives on in a browser's history.
    @Test("a report fills in the version and the system, and nothing more")
    func reportCarries() {
        let items = Self.items(of: Help.report(version: "0.0.12", build: "12", system: "26.1.0"))
        #expect(items.map(\.name) == ["template", "version", "macos"])
        #expect(Self.value("template", in: items) == "problem.yml")
        #expect(Self.value("version", in: items) == "0.0.12 (12)")
        #expect(Self.value("macos", in: items) == "26.1.0")
    }

    @Test("what a report carries is encoded, not written raw into the link")
    func reportIsEncoded() {
        let text = Help.report(version: "0.0.12", build: "12", system: "26.1.0").absoluteString
        #expect(!text.contains(" "))
        #expect(text.contains("%20"))
    }

    @Test("this copy reports its own version")
    func fromHere() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        #expect(Self.value("version", in: Self.items(of: Help.reportFromHere)) == "\(version) (\(build))")
    }

    // MARK: the form the link opens

    /// GitHub serves the form from `main`, and the only copy the suite can
    /// see is this tree's, beside this file.
    private static let templates = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".github/ISSUE_TEMPLATE")

    /// **A field the form lacks cannot be filled**, and a link is as
    /// permanent as the build carrying it, so this is the moment to catch
    /// it. GitHub fills only text fields from a link.
    @Test("every field a report fills is a text field on the form it opens")
    func reportMatchesForm() throws {
        let items = Self.items(of: Help.report(version: "0.0.12", build: "12", system: "26.1.0"))
        let name = try #require(Self.value("template", in: items))
        let fields = Self.fields(of: try Self.document(named: name))
        #expect(fields.count > 1, "read no fields, so this checks nothing")
        for item in items where item.name != "template" {
            let field = fields.first { $0.id == item.name }
            #expect(field != nil, "the form has no field called \(item.name)")
            #expect(field.map { ["input", "textarea"].contains($0.type) } ?? false,
                    "\(item.name) is not a text field, so a link cannot fill it")
        }
    }

    /// 0.1.0's Report a Problem… opens a blank issue with its questions in
    /// the body, and every copy of it will go on doing so.
    @Test("blank issues stay allowed, for the link 0.1.0 shipped")
    func blankIssuesStay() throws {
        let config = try Self.document(named: "config.yml")
        #expect(config["blank_issues_enabled"] as? Bool == true)
    }

    // MARK: reading them

    private static func items(of url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private static func value(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }

    /// A template, read the way the app reads YAML, so one that is not YAML
    /// at all fails here, with Yams's own line and column, rather than on
    /// GitHub.
    private static func document(named name: String) throws -> [String: Any] {
        let text = try String(contentsOf: templates.appendingPathComponent(name), encoding: .utf8)
        let documents = try YAMLDocuments.read(text)
        return try #require(documents.first as? [String: Any], "\(name) is not a mapping")
    }

    /// Each field of a form, its type and its id, in order.
    private static func fields(of form: [String: Any]) -> [(type: String, id: String)] {
        (form["body"] as? [[String: Any]] ?? []).compactMap { field in
            guard let type = field["type"] as? String, let id = field["id"] as? String else { return nil }
            return (type, id)
        }
    }
}
