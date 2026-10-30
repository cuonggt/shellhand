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

    init(store: HostStore, start: Source = .sshConfig) {
        self.store = store
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

        var about: String {
            switch self {
            case .sshConfig: "The machines OpenSSH already knows about."
            case .csv: "A sheet, or an export from another client."
            case .yaml: "A list exported from Shellhand."
            }
        }
    }

    /// What the preview on screen was made of; Import runs on exactly this.
    @State private var previewed: ImportPlan.Asked?
    @State private var source: Source = .sshConfig
    @State private var configPath = ""
    @State private var configCount: Int?
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
                Section {
                    TextField("Put new hosts in", text: $group, prompt: Text("optional group"))
                        // Looked at again once typing stops, rather than a
                        // preview for every key.
                        .task(id: group) {
                            guard preview != nil else { return }
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            await look()
                        }
                } footer: {
                    Text("A host the file already files somewhere stays there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if source == .csv { sample }
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
        .frame(width: DialogSize.medium, height: 560)
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
            if case let .success(url) = result { note = "Exported to \(url.lastPathComponent)." }
        }
        .task {
            if configPath.isEmpty {
                configPath = Core.shared.defaultSSHConfigPath()
            }
            configCount = store.sshConfigHosts(path: configPath)
            if source == .sshConfig, configCount != nil { await look() }
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
                        // Return looks at the file typed. Import would not
                        // run here anyway: it is off until what is on screen
                        // has been previewed.
                        .onSubmit { Task { await look() } }
                    Button("Choose…") { choosing = true }
                }
            }
            HStack {
                if let configCount {
                    Label("Names \(configCount) machine\(configCount == 1 ? "" : "s").",
                          systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                } else {
                    Label("No file there yet.", systemImage: "questionmark.folder")
                        .foregroundStyle(.secondary)
                }
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
                .textSelection(.enabled)
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
            .disabled(busy)
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
        if source == .sshConfig, configCount != nil { Task { await look() } }
    }

    /// Reads a dropped or chosen file once and previews it. Keeping the text
    /// means the import applies the very bytes that were previewed, and that
    /// the file is reached for once rather than twice.
    private func take(_ url: URL) async {
        if source == .sshConfig {
            configPath = url.path
            configCount = store.sshConfigHosts(path: configPath)
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
            configCount = store.sshConfigHosts(path: asked.path)
            // A missing file read "Nothing to do — everything in that file
            // is already here".
            guard configCount != nil else {
                preview = nil
                previewed = nil
                problem = "There is no file at \(asked.path)."
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
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
