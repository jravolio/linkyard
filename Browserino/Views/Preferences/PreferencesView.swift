//
//  PreferencesView.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import AppKit
import SwiftUI

extension NSTableView {
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        backgroundColor = NSColor.clear
        enclosingScrollView?.drawsBackground = false
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, picker, browsers, profiles, rules, apps, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .picker: "Picker"
        case .browsers: "Browsers"
        case .profiles: "Profiles"
        case .rules: "Rules"
        case .apps: "Apps"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .picker: "rectangle.stack.fill"
        case .browsers: "globe"
        case .profiles: "person.2.fill"
        case .rules: "arrow.triangle.branch"
        case .apps: "square.grid.2x2.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general, .about: .gray
        case .picker, .permissions: .blue
        case .browsers: .teal
        case .profiles: .purple
        case .rules: .orange
        case .apps: .green
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralTab()
        case .picker: PickerTab()
        case .browsers: BrowsersTab()
        case .profiles: ProfilesTab()
        case .rules: RulesTab()
        case .apps: AppsTab()
        case .permissions: PermissionsTab()
        case .about: AboutTab()
        }
    }
}

struct PreferencesView: View {
    @State private var selection: SettingsPane = .general
    @State private var query = ""
    @State private var highlight: SettingsHighlight?

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, query: $query) { result in
                open(result.pane, item: result.id)
            }
            .settingsSidebarPinned()
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            selection.content
                .environment(\.settingsHighlight, highlight)
                .environment(\.openSettingsItem, open)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func open(_ pane: SettingsPane, item: String) {
        let opened = SettingsHighlight(id: item)
        selection = pane
        highlight = opened
        // Cleared so revisiting the pane later doesn't scroll and flash the row again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if highlight == opened {
                highlight = nil
            }
        }
    }
}

private extension View {
    /// Settings has no use for a collapsed sidebar.
    @ViewBuilder
    func settingsSidebarPinned() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

struct SettingsPaneIcon: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    init(pane: SettingsPane) {
        self.init(symbol: pane.symbol, tint: pane.tint)
    }

    init(symbol: String, tint: Color, size: CGFloat = 20) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 4, style: .continuous).fill(tint.gradient))
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @Binding var query: String
    let open: (SettingsSearchItem) -> Void

    @AppStorage("browsers") private var browsers: [URL] = []
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("apps") private var apps: [App] = []
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("diaProfiles") private var diaProfiles: [ChromeProfile] = []
    @AppStorage("zenProfiles") private var zenProfiles: [ChromeProfile] = []

    private var results: [SettingsSearchItem] {
        SettingsSearch.results(
            for: query,
            in: SettingsSearch.index(
                browsers: browsers,
                profiles: [
                    (ChromiumProfileUtil.chromeSource, chromeProfiles),
                    (ChromiumProfileUtil.arcSource, arcProfiles),
                    (ChromiumProfileUtil.diaSource, diaProfiles),
                    (ChromiumProfileUtil.zenSource, zenProfiles),
                ].filter { ChromiumProfileUtil.appURL(for: $0.0) != nil },
                rules: rules,
                apps: apps
            )
        )
    }

    var body: some View {
        List(selection: $selection) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsPaneIcon(pane: pane)
                    }
                    .tag(pane)
                }
            } else {
                let results = results
                if results.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                }
                ForEach(SettingsPane.allCases) { pane in
                    let matches = results.filter { $0.pane == pane }
                    if !matches.isEmpty {
                        Section(pane.title) {
                            ForEach(matches) { result in
                                Button {
                                    open(result)
                                } label: {
                                    SearchResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
    }
}

private struct SearchResultRow: View {
    let result: SettingsSearchItem

    var body: some View {
        HStack(spacing: 8) {
            SettingsPaneIcon(pane: result.pane)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                if let detail = result.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

enum ListEditor: Hashable, Identifiable {
    case new
    case existing(Int)

    var id: Self { self }
}

struct SettingsSheetFooter: View {
    let saveTitle: String
    let canSave: Bool
    var deleteTitle = "Delete"
    var onDelete: (() -> Void)?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            if let onDelete {
                Button(deleteTitle, role: .destructive, action: onDelete)
            }

            Spacer()

            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(saveTitle, action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(16)
    }
}

private struct PreviewPickerKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var previewPicker: () -> Void {
        get { self[PreviewPickerKey.self] }
        set { self[PreviewPickerKey.self] = newValue }
    }
}

/// A search result the user opened; a new token re-runs the highlight even for the same setting.
struct SettingsHighlight: Equatable {
    let id: String
    let token = UUID()
}

private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: SettingsHighlight? = nil
}

extension EnvironmentValues {
    var settingsHighlight: SettingsHighlight? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }

    var openSettingsItem: (SettingsPane, String) -> Void {
        get { self[OpenSettingsItemKey.self] }
        set { self[OpenSettingsItemKey.self] = newValue }
    }
}

private struct OpenSettingsItemKey: EnvironmentKey {
    static let defaultValue: (SettingsPane, String) -> Void = { _, _ in }
}

extension View {
    func settingsItem(_ id: String) -> some View {
        modifier(SettingsItemModifier(id: id))
    }

    /// The picker becomes key on every link; this runs only when the Settings window becomes key again.
    func onSettingsWindowKey(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if !(notification.object is BrowserinoWindow) {
                action()
            }
        }
    }
}

private struct SettingsItemModifier: ViewModifier {
    let id: String

    @Environment(\.settingsHighlight) private var highlight
    @State private var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.22 : 0))
                    .padding(-5)
            )
            .onAppear { flashIfNeeded(highlight) }
            .onChange(of: highlight) { flashIfNeeded($0) }
    }

    private func flashIfNeeded(_ highlight: SettingsHighlight?) {
        guard highlight?.id == id else {
            return
        }

        withAnimation(.easeOut(duration: 0.15)) {
            isHighlighted = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.6)) {
                isHighlighted = false
            }
        }
    }
}

struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                content
            }
            .formStyle(.grouped)
            .onAppear { scroll(proxy, to: highlight) }
            .onChange(of: highlight) { scroll(proxy, to: $0) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to highlight: SettingsHighlight?) {
        guard let id = highlight?.id else {
            return
        }

        // The pane may have just been switched in; scroll once its rows exist.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

#Preview {
    PreferencesView()
}
