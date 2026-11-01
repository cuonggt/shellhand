import Testing
@testable import Shellhand

/// When the import sheet's Import may run, and what its plan says.
@Suite("What Import runs on")
nonisolated struct ImportPlanTests {
    private let previewed = ImportPlan.Asked(source: "sshConfig", path: "~/.ssh/config")

    @Test("Import runs on exactly what was previewed, and only with something to do")
    func onWhatWasPreviewed() {
        #expect(ImportPlan.mayImport(previewed: previewed, asking: previewed, changes: 3, busy: false))
        #expect(!ImportPlan.mayImport(previewed: previewed, asking: previewed, changes: 0, busy: false))
        #expect(!ImportPlan.mayImport(previewed: previewed, asking: previewed, changes: 3, busy: true))
        #expect(!ImportPlan.mayImport(previewed: nil, asking: previewed, changes: 3, busy: false))
    }

    /// A path edited since the preview and Returned imported a file nobody
    /// had looked at, and a group typed after it imported into a group the
    /// preview had not shown.
    @Test("a path, a group or a file changed since the preview stops it")
    func changedSince() {
        var path = previewed
        path.path = "~/.ssh/other"
        var group = previewed
        group.group = "Imported"
        var text = previewed
        text.text = "web,10.0.0.1"
        for asking in [path, group, text] {
            #expect(!ImportPlan.mayImport(previewed: previewed, asking: asking, changes: 3, busy: false))
        }
    }

    /// The welcome said "No ~/.ssh/config here", and the sheet "No file
    /// there yet." under its field and "There is no file at …" along its
    /// foot — and a file naming no machine was said to be no file at all.
    @Test("a config is said one way: not there, naming none, or naming some")
    func configWording() {
        #expect(ImportPlan.configSays(nil, at: "~/.ssh/config") == "No file at ~/.ssh/config")
        #expect(ImportPlan.configSays(0, at: "/etc/ssh/ssh_config")
            == "/etc/ssh/ssh_config names no machines")
        #expect(ImportPlan.configSays(1, at: "~/.ssh/config") == "~/.ssh/config names 1 machine")
        #expect(ImportPlan.configSays(12, at: "~/.ssh/config") == "~/.ssh/config names 12 machines")
    }

    /// It said "5 added" over a plan nothing had carried out.
    @Test("the plan says what it would do, not what it did")
    func planWording() {
        #expect(MergeResult(added: 5, updated: 2, unchanged: 3).plan
            == "Would add 5 and update 2 · 3 already here")
        #expect(MergeResult(added: 1).plan == "Would add 1")
        #expect(MergeResult(unchanged: 4).plan == "Nothing to add or update · 4 already here")
    }
}
