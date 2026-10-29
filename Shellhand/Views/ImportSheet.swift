import SwiftUI
import UniformTypeIdentifiers

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
                        .onChange(of: group) { _, _ in if preview != nil { Task { await look() } } }
                } footer: {
                    Text("A host the file already files somewhere stays there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if source == .csv { sample }
                if let problem { trouble(problem) }
                if let preview { plan(preview) }
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
        Section(result.summary) {
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
                .disabled(busy || preview == nil || preview?.changes.isEmpty == true)
        }
        .padding(12)
    }

    private var importTitle: String {
        guard let preview, !preview.changes.isEmpty else { return "Import" }
        return "Import \(preview.added + preview.updated)"
    }

    // MARK: doing it

    private func reset() {
        preview = nil
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
        await run(dryRun: true)
    }

    private func bring() async {
        busy = true
        defer { busy = false }
        problem = nil
        let before = preview
        await run(dryRun: false)
        if problem == nil, let before {
            note = "Imported \(before.added + before.updated) record"
                + (before.added + before.updated == 1 ? "." : "s.")
            if source == .sshConfig { configCount = store.sshConfigHosts(path: configPath) }
        }
    }

    private func run(dryRun: Bool) async {
        switch source {
        case .sshConfig:
            let result = await store.importSSHConfig(
                path: configPath, group: group, dryRun: dryRun)
            settle(result)
        case .csv:
            guard !text.isEmpty else { return }
            let reading = await store.importCSV(text, group: group, dryRun: dryRun)
            columns = reading
            settle(reading?.result)
        case .yaml:
            guard !text.isEmpty else { return }
            settle(await store.importYAML(text, group: group, dryRun: dryRun))
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
