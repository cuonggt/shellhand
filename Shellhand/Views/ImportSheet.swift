import SwiftUI
import UniformTypeIdentifiers

/// When Import may run: on exactly what the preview on screen was made of.
///
/// The preview and the import were two readings of the window, and they
/// could disagree. A path edited since the preview, or typed and Returned,
/// imported a file nobody had looked at; a group typed after it imported into
/// a group the preview had not shown; and pressing Import again once it was
/// done reported the first import's count a second time.
nonisolated enum ImportPlan {
    /// What a preview was made of, or would be: the source, its file or its
    /// text, and the group new hosts go in.
    struct Asked: Equatable, Sendable {
        var source: String
        var path = ""
        var text = ""
        var group = ""
    }

    static func mayImport(previewed: Asked?, asking: Asked, changes: Int, busy: Bool) -> Bool {
        !busy && changes > 0 && previewed == asking
    }

    /// What the ssh config at `path` holds, in the same words wherever it is
    /// said: the welcome said "No ~/.ssh/config here", and this sheet "No
    /// file there yet." under its field with "There is no file at …" along
    /// its foot at once — and a file naming no machine was said to be none.
    static func configSays(_ count: Int?, at path: String) -> String {
        let shown = NSString(string: path).abbreviatingWithTildeInPath
        return switch count {
        case nil: "No file at \(shown)"
        case 0?: "\(shown) names no machines"
        case let named?: "\(shown) names \(named) machine\(named == 1 ? "" : "s")"
        }
    }
}

/// Moving a host list in and out, through the same code the CLI uses: records
/// match by name, so importing the same list twice changes nothing the second
/// time.
///
/// Every source is shown the same way — pick a file, see exactly what it would
/// do, then do it. The preview is not a prediction: it is the plan the import
/// applies, worked out by the same function, so what is listed is what lands.
struct ImportSheet: View {
    let store: HostStore
    /// The room below the toolbar of the window this opens over, which it
    /// fits in — `SheetHeight`.
    let room: SheetRoom

    init(store: HostStore, start: Source = .sshConfig, room: SheetRoom = SheetRoom()) {
        self.store = store
        self.room = room
        // From the first frame rather than from `task`, so the picker does
        // not visibly flip from one tab to another on the way in.
        _source = State(initialValue: start)
    }

    nonisolated enum Source: String, CaseIterable, Identifiable {
        case sshConfig, csv, yaml
        var id: Self { self }

        var title: String {
            switch self {
            case .sshConfig: "SSH Config"
            case .csv: "CSV"
            case .yaml: "YAML"
            }
        }

        var types: [UTType] {
            switch self {
            case .sshConfig: [.plainText, .data]
            case .csv: [.commaSeparatedText, .tabSeparatedText, .plainText]
            case .yaml: [.yaml, .plainText]
            }
        }

        /// What each is, in the same words here and on the welcome: the CSV
        /// tab said "A sheet, or an export from another client." — inside a
        /// sheet — where the welcome said a spreadsheet. The ssh config's
        /// line on the welcome is what the file holds, which this tab says
        /// under its field, so its heading is the welcome's name for it: it
        /// said "The machines OpenSSH already knows about", which the welcome
        /// never did.
        var about: String {
            switch self {
            case .sshConfig: "Your SSH config"
            case .csv: "From a spreadsheet, or another client's export"
            case .yaml: "A list exported from Shellhand"
            }
        }
    }

    /// What the preview on screen was made of; Import runs on exactly this.
    @State private var previewed: ImportPlan.Asked?
    @State private var source: Source = .sshConfig
    @State private var configPath = ""
    @State private var configCount: Int?
    /// The file `configCount` is about, which the field may have moved on from.
    @State private var configCounted = ""
    @State private var picked: URL?
    @State private var text = ""
    @State private var group = ""
    @State private var preview: MergeResult?
    @State private var columns: CSVImport?
    @State private var busy = false
    @State private var note: String?
    @State private var problem: String?
    @State private var choosing = false
    @State private var exporting = false
    @State private var exportText = ""
    @State private var targeted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                Section { sourceFields } header: {
                    Text(source.about)
                }
                // What a CSV's columns should be, beside the file it is about:
                // it came after the group field, between them.
                if source == .csv { sample }
                Section {
                    // A field beside its label, as every other in the app: a
                    // bare one in a grouped form sits right-aligned against
                    // the label, and "optional group" read as a group chosen.
                    LabeledContent("Put new hosts in") {
                        TextField("", text: $group, prompt: Text("optional group"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            // Looked at again once typing stops, rather than a
                            // preview for every key.
                            .task(id: group) {
                                guard preview != nil else { return }
                                try? await Task.sleep(for: .milliseconds(400))
                                guard !Task.isCancelled else { return }
                                await look()
                            }
                    }
                } footer: {
                    // What `Portable.merge(newHostsIn:)` does, by source: an
                    // ssh config names no groups, so nothing in it moves a
                    // host; a CSV or YAML file can, and a host it names one for
                    // goes there, in your list already or not. It said hosts
                    // already in your list stayed, whatever the file said —
                    // and "already in it", under "this group", read as the group.
                    Text(source == .sshConfig
                         ? "Hosts new to your list go into this group. Hosts already in your list stay where they are."
                         : "Hosts new to your list go into this group, unless the file names one for them. "
                           + "A host the file names a group for goes into that group, even one already in your list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem { trouble(problem) }
                if let preview {
                    if previewed != asking {
                        Section {
                            Label("Changed since this was looked at. Look again to see what "
                                    + "it would bring in.",
                                  systemImage: "arrow.clockwise")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    plan(preview)
                }
                if let note {
                    Section {
                        Label(note, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: DialogSize.medium, height: SheetHeight.fitted(560, in: room.height))
        .fileImporter(isPresented: $choosing, allowedContentTypes: source.types) { result in
            guard case let .success(url) = result else { return }
            Task { await take(url) }
        }
        .fileExporter(
            isPresented: $exporting,
            document: YAMLDocument(text: exportText),
            contentType: .yaml,
            defaultFilename: YAMLDocument.defaultFilename
        ) { result in
            switch result {
            case let .success(url):
                note = "Exported to \(url.lastPathComponent)."
            // Said here, as File ▸ Export… says it over the window: a save
            // the disk refused went without a word.
            case let .failure(error):
                if let failure = YAMLDocument.failure(error) { problem = failure }
            }
        }
        .task {
            // Spelled as the line under it spells it, and as its own example
            // does: "~/.ssh/config", which is read settled. It held the
            // whole of /Users/…/.ssh/config over "~/.ssh/config names 12".
            if configPath.isEmpty {
                configPath = NSString(string: Core.shared.defaultSSHConfigPath())
                    .abbreviatingWithTildeInPath
            }
            countConfig(at: configPath)
            if source == .sshConfig, (configCount ?? 0) > 0 { await look() }
        }
    }

    // MARK: the parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $source) {
                ForEach(Source.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: source) { _, _ in reset() }
        }
        .padding(12)
    }

    @ViewBuilder
    private var sourceFields: some View {
        if source == .sshConfig {
            LabeledContent("File") {
                HStack {
                    TextField("", text: $configPath, prompt: Text("~/.ssh/config"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        // Return looks at the file typed. Import would not
                        // run here anyway: it is off until what is on screen
                        // has been previewed.
                        .onSubmit { Task { await look() } }
                        // Asking for a modest width and taking what there is:
                        // asking for the whole path's, the field put the form
                        // in two lines, "File" above it, where every other
                        // field has its label beside it.
                        .frame(idealWidth: 220, maxWidth: .infinity)
                    Button("Choose…") { choosing = true }
                }
            }
            HStack {
                // The one place this sheet says what the file holds, in the
                // welcome's words.
                Label(ImportPlan.configSays(configCount, at: configCounted),
                      systemImage: configCount == nil ? "questionmark.folder" : "doc.text")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Look") { Task { await look() } }
                    .disabled(busy || configPath.isEmpty)
            }
            .font(.callout)
        } else {
            well
        }
    }

    /// Somewhere to drop a file, which is how a file that is already in front
    /// of someone in the Finder gets here fastest.
    private var well: some View {
        VStack(spacing: 8) {
            Image(systemName: picked == nil ? "arrow.down.doc" : "doc.text.fill")
                .font(.system(size: 26))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            if let picked {
                Text(picked.lastPathComponent).font(.callout.weight(.medium))
            } else {
                Text("Drop a \(source.title) file here").font(.callout)
            }
            Button(picked == nil ? "Choose…" : "Choose another…") { choosing = true }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(targeted ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.clear)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await take(url) }
            return true
        } isTargeted: { targeted = $0 }
    }

    /// What a sheet has to look like, because nobody can guess and the answer
    /// is three words long.
    private var sample: some View {
        Section {
            DisclosureGroup("What the columns should be") {
                Text(
                    """
                    name,address,port,user,identity,group,tags,jump
                    bastion,10.0.0.1,22,deploy,~/.ssh/id_ed25519,Production,edge,
                    web-1,10.0.1.7,,deploy,,Production,web;live,bastion
                    """
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(.vertical, 4)
                Text(
                    "Only one of name or address is needed. Columns can be in any order, and "
                        + "ones that are not on that list are passed over — the import says which."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func trouble(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .selectable(message)
        }
    }

    @ViewBuilder
    private func plan(_ result: MergeResult) -> some View {
        if let columns, !columns.ignored.isEmpty {
            Section {
                Label(
                    "Used \(columns.used.joined(separator: ", ")). Passed over "
                        + "\(columns.ignored.joined(separator: ", ")).",
                    systemImage: "tablecells")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        // The same shape as the CSV's ignored columns, and for the same
        // reason: a file this app wrote before keys,
        // credentials and snippets were cut, still carries them. They are
        // accepted rather than refusing the file, and said rather than
        // dropped in silence — dropping a credential can leave a host
        // without the user it logged in as.
        if !result.passedOver.isEmpty {
            Section {
                Label(
                    "Passed over \(result.passedOver.joined(separator: ", ")) — "
                        + "Shellhand no longer keeps them.",
                    systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        Section(result.plan) {
            if result.changes.isEmpty {
                Text("Nothing to do — everything in that file is already here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(result.changes.prefix(300)) { change in
                HStack(spacing: 8) {
                    Image(systemName: change.action == "add"
                        ? "plus.circle.fill" : "pencil.circle.fill")
                        .foregroundStyle(change.action == "add" ? .green : .blue)
                    Text(change.name)
                    Spacer()
                    Text(change.kind).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if result.changes.count > 300 {
                Text("…and \(result.changes.count - 300) more.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Export…") {
                Task {
                    exportText = await store.exportYAML() ?? ""
                    exporting = !exportText.isEmpty
                }
            }
            // Greyed with nothing to export, as File ▸ Export… is: from the
            // welcome it wrote a file holding nothing.
            .disabled(busy || !store.canExport)
            Spacer()
            // Escape. Nothing has been brought in until `note` says so, and
            // until then leaving is cancelling.
            Button(note == nil ? "Cancel" : "Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(importTitle) { Task { await bring() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!mayImport)
        }
        .padding(12)
    }

    /// What the window asks for now — what Import would run on.
    private var asking: ImportPlan.Asked {
        ImportPlan.Asked(
            source: source.rawValue,
            path: source == .sshConfig ? configPath : "",
            text: source == .sshConfig ? "" : text,
            group: group)
    }

    private var mayImport: Bool {
        ImportPlan.mayImport(
            previewed: previewed, asking: asking, changes: preview?.changes.count ?? 0, busy: busy)
    }

    private var importTitle: String {
        guard let preview, !preview.changes.isEmpty else { return "Import" }
        return "Import \(preview.added + preview.updated)"
    }

    // MARK: doing it

    private func reset() {
        preview = nil
        previewed = nil
        columns = nil
        note = nil
        problem = nil
        picked = nil
        text = ""
        if source == .sshConfig, (configCount ?? 0) > 0 { Task { await look() } }
    }

    private func countConfig(at path: String) {
        configCount = store.sshConfigHosts(path: path)
        // An empty field is counted as the config in use, and named so.
        configCounted = path.isEmpty ? Core.shared.defaultSSHConfigPath() : path
    }

    /// Reads a dropped or chosen file once and previews it. Keeping the text
    /// means the import applies the very bytes that were previewed, and that
    /// the file is reached for once rather than twice.
    private func take(_ url: URL) async {
        if source == .sshConfig {
            configPath = NSString(string: url.path).abbreviatingWithTildeInPath
            countConfig(at: configPath)
            await look()
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            problem = "\(url.lastPathComponent) could not be read as text."
            return
        }
        picked = url
        text = raw
        await look()
    }

    /// The dry run: the plan, without writing it.
    private func look() async {
        busy = true
        defer { busy = false }
        note = nil
        problem = nil
        await look(at: asking)
    }

    /// Previews `asked`, and remembers it as what the preview was made of —
    /// unless the window moved on while it looked, when the answer is about
    /// something no longer on screen and is let go.
    private func look(at asked: ImportPlan.Asked) async {
        if source == .sshConfig {
            countConfig(at: asked.path)
            // Nothing to preview, which the line under the field says: a
            // missing file read "Nothing to do — everything in that file is
            // already here", and then was said there and along the foot,
            // two ways at once.
            guard let named = configCount, named > 0 else {
                preview = nil
                previewed = nil
                return
            }
        } else if asked.text.isEmpty {
            return
        }
        let (result, reading) = await outcome(of: asked, dryRun: true)
        guard asked == asking else { return }
        columns = reading
        settle(result)
        previewed = result == nil ? nil : asked
    }

    /// Brings in what the preview showed and nothing else: the file, the text
    /// and the group it was made of, which Import is on for only while they
    /// are what is on screen.
    private func bring() async {
        guard mayImport, let asked = previewed else { return }
        busy = true
        defer { busy = false }
        problem = nil
        let (result, _) = await outcome(of: asked, dryRun: false)
        guard let result else {
            problem = store.lastError ?? "That could not be imported."
            return
        }
        let count = result.added + result.updated
        note = "Imported \(count) record" + (count == 1 ? "." : "s.")
        // Looked at again, so the plan is the list as it now stands — nothing
        // left to do — and a second press has nothing to bring.
        await look(at: asked)
    }

    private func outcome(
        of asked: ImportPlan.Asked, dryRun: Bool
    ) async -> (MergeResult?, CSVImport?) {
        switch source {
        case .sshConfig:
            return (await store.importSSHConfig(path: asked.path, group: asked.group, dryRun: dryRun),
                    nil)
        case .csv:
            let reading = await store.importCSV(asked.text, group: asked.group, dryRun: dryRun)
            return (reading?.result, reading)
        case .yaml:
            return (await store.importYAML(asked.text, group: asked.group, dryRun: dryRun), nil)
        }
    }

    private func settle(_ result: MergeResult?) {
        if let result {
            preview = result
        } else {
            preview = nil
            problem = store.lastError ?? "That could not be read."
        }
    }
}

/// The export, written as the CLI writes it.
struct YAMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yaml, .text] }
    /// What an export is called until somebody names it — one name for the
    /// import sheet's Export… and the File menu's, so the two cannot drift.
    static let defaultFilename = "shellhand-hosts"

    /// What an export the disk refused says, in the sheet as over the window,
    /// and nothing for Cancel, which is an answer rather than a failure. The
    /// sheet's Export… dropped every refusal without a word.
    nonisolated static func failure(_ error: Error) -> String? {
        guard (error as? CocoaError)?.code != .userCancelled else { return nil }
        return "The list could not be exported: \(error.localizedDescription)"
    }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
