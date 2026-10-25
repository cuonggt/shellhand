import AppKit
import SwiftUI

/// What Settings is divided into.
///
/// Three, named for what they act on, the way the menus are: a pane is the
/// settings for a thing, not a drawer of leftovers. There is deliberately
/// little here — almost everything about a connection belongs to the host,
/// the group or the config file, and saying it twice would give two places
/// to set one thing.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case terminal
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .terminal: "Terminal"
        case .files: "SFTP"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .terminal: "apple.terminal"
        case .files: "arrow.left.arrow.right"
        }
    }
}

/// Which pane is open, outside the view so the window controller can be asked
/// to open on one.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = .general
    private init() {}
}

/// Settings: the panes down the side, the one chosen beside them.
///
/// The back and forward buttons are not only navigation — a `ToolbarItemGroup`
/// is what makes AppKit give the window an `NSToolbar` at all, and without
/// one the title bar does not get the glass treatment.
struct SettingsRootView: View {
    let storePath: String
    let configPath: String

    @State private var navigation = SettingsNavigation.shared
    @State private var history: [SettingsTab] = [.general]
    @State private var position = 0
    /// Set while a back or forward button is doing the moving, so the move
    /// is not then recorded as somewhere new to come back from.
    @State private var retracing = false

    private var tab: SettingsTab { navigation.selectedTab ?? .general }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(
                tab: tab, storePath: storePath, configPath: configPath)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(position == 0)
                    .accessibilityLabel("Back")
                    .help("Back")
                Button { goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(position >= history.count - 1)
                    .accessibilityLabel("Forward")
                    .help("Forward")
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in record() }
    }

    private var sidebar: some View {
        List(selection: $navigation.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle("Settings")
        // Under the list rather than a row in it: a list row is indented for
        // a selection it will never have, and the inset left so little width
        // that the build number fell off the end.
        .safeAreaInset(edge: .bottom) { version }
    }

    /// Down in the corner, where you go looking for it when something is
    /// wrong rather than when you are changing a setting.
    private var version: some View {
        Text(Self.version)
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }()

    // MARK: where you have been

    private func goBack() {
        guard position > 0 else { return }
        retracing = true
        position -= 1
        navigation.selectedTab = history[position]
        Task { @MainActor in retracing = false }
    }

    private func goForward() {
        guard position < history.count - 1 else { return }
        retracing = true
        position += 1
        navigation.selectedTab = history[position]
        Task { @MainActor in retracing = false }
    }

    private func record() {
        guard !retracing, let tab = navigation.selectedTab, history.last != tab
        else { return }
        // Going somewhere new from halfway back drops what was ahead, the way
        // a browser does.
        if position < history.count - 1 {
            history = Array(history.prefix(position + 1))
        }
        history.append(tab)
        position = history.count - 1
    }
}

/// The pane itself.
private struct SettingsDetailView: View {
    let tab: SettingsTab
    let storePath: String
    let configPath: String

    var body: some View {
        SwiftUI.Group {
            switch tab {
            case .general: GeneralSettingsPane(storePath: storePath, configPath: configPath)
            case .terminal: TerminalSettingsPane()
            case .files: FilesSettingsPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
