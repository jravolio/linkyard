//
//  PromptView.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import AppKit
import SwiftUI

struct PickerBrowserItem: Identifiable {
    let id: String
    let appURL: URL
    let displayName: String?
    let profileDirectory: String?
    let shortcutKey: String?
    var iconPath: String? = nil
    var group: String? = nil
}

struct PickerRow: Identifiable {
    let id: String
    let title: String
    var iconPath: String?
    let iconAppURL: URL
    var cells: [String: PickerBrowserItem] = [:]
    var app: App? = nil
    var shortcutKey: String? = nil
}

struct PromptView: View {
    @AppStorage("browsers") private var browsers: [URL] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [URL] = []
    @AppStorage("apps") private var apps: [App] = []
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    @AppStorage("pickerGroups") private var pickerGroups: [String: String] = [:]
    @AppStorage("pickerGroupOrder") private var pickerGroupOrder: [String] = []
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("arcProfilesEnabled") private var arcProfilesEnabled: Bool = true
    @AppStorage("diaProfiles") private var diaProfiles: [ChromeProfile] = []
    @AppStorage("diaProfilesEnabled") private var diaProfilesEnabled: Bool = true
    @AppStorage("zenProfiles") private var zenProfiles: [ChromeProfile] = []
    @AppStorage("zenProfilesEnabled") private var zenProfilesEnabled: Bool = true

    @AppStorage("copy_closeAfterCopy") private var closeAfterCopy: Bool = false
    @AppStorage("copy_alternativeShortcut") private var alternativeShortcut: Bool = false
    @AppStorage("apps_atTop") private var appsAtTop: Bool = true

    let urls: [URL]

    @State private var opacityAnimation = 0.0
    @State private var selectedRow = 0
    @State private var selectedColumn: String?
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 56
    private static let logoSize: CGFloat = 36
    private static let cellSize: CGFloat = 32
    private static let maxListHeight: CGFloat = 520

    var appsForUrls: [App] {
        urls.flatMap { url in
            return apps.filter { app in
                url.matchesHost(app.host)
            }
        }
        .filter {
            !browsers.contains($0.app)
        }
    }

    var visibleBrowsers: [URL] {
        browsers.filter { !hiddenBrowsers.contains($0) }
    }

    private func profileSettings(for bundleID: String) -> (profiles: [ChromeProfile], enabled: Bool)? {
        switch bundleID {
        case ChromiumProfileUtil.chromeBundleID:
            return (chromeProfiles, chromeProfilesEnabled)
        case ChromiumProfileUtil.arcBundleID:
            return (arcProfiles, arcProfilesEnabled)
        case ChromiumProfileUtil.diaBundleID:
            return (diaProfiles, diaProfilesEnabled)
        case ChromiumProfileUtil.zenBundleID:
            return (zenProfiles, zenProfilesEnabled)
        default:
            return nil
        }
    }

    var pickerBrowserItems: [PickerBrowserItem] {
        var items: [PickerBrowserItem] = []

        for browser in visibleBrowsers {
            guard let bundle = Bundle(url: browser) else { continue }
            let bundleID = bundle.bundleIdentifier ?? ""

            if let settings = profileSettings(for: bundleID), settings.enabled {
                let visibleProfiles = settings.profiles.filter { !$0.isHidden }
                if !visibleProfiles.isEmpty {
                    for profile in visibleProfiles {
                        let profileID = "\(bundleID)::\(profile.selectionID)"
                        let browserName = browser.appDisplayName
                        items.append(PickerBrowserItem(
                            id: profileID,
                            appURL: browser,
                            displayName: "\(browserName) - \(profile.displayName)",
                            profileDirectory: profile.selectionID,
                            shortcutKey: shortcuts[profileID],
                            iconPath: profile.iconPath,
                            group: pickerGroups[profileID] ?? profile.displayName
                        ))
                    }
                    continue
                }
            }

            items.append(PickerBrowserItem(
                id: bundleID,
                appURL: browser,
                displayName: nil,
                profileDirectory: nil,
                shortcutKey: shortcuts[bundleID],
                group: pickerGroups[bundleID]
            ))
        }

        return PickerLayout.grouped(items, order: pickerGroupOrder)
    }

    private var browserColumnsOrder: [String] {
        visibleBrowsers.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func pickerRows(from items: [PickerBrowserItem]) -> [PickerRow] {
        let identityRows = PickerLayout.identityRows(from: items, order: pickerGroupOrder)
        let appRows = appsForUrls.enumerated().map { index, app in
            PickerRow(
                id: "app::\(index)",
                title: app.app.appDisplayName,
                iconPath: nil,
                iconAppURL: app.app,
                app: app,
                shortcutKey: shortcuts[Bundle(url: app.app)?.bundleIdentifier ?? ""]
            )
        }

        return appsAtTop ? appRows + identityRows : identityRows + appRows
    }

    func openUrlsInApp(app: App) {
        let urls =
            if app.schemeOverride.isEmpty {
                urls
            } else {
                urls.map {
                    let url = NSURLComponents.init(
                        url: $0,
                        resolvingAgainstBaseURL: true
                    )
                    url!.scheme = app.schemeOverride

                    return url!.url!
                }
            }

        BrowserUtil.openURL(
            urls,
            app: app.app,
            isIncognito: false
        )
    }

    func openBrowserItem(_ item: PickerBrowserItem, isIncognito: Bool) {
        BrowserUtil.openURL(
            urls,
            app: item.appURL,
            isIncognito: isIncognito,
            profileDirectory: item.profileDirectory
        )
    }

    private func openSelected(rows: [PickerRow], columns: [String], isIncognito: Bool) {
        guard rows.indices.contains(selectedRow) else {
            return
        }

        let row = rows[selectedRow]
        open(row, column: PickerLayout.resolvedColumn(in: row, columns: columns, preferring: selectedColumn), isIncognito: isIncognito)
    }

    private func open(_ row: PickerRow, column: String?, isIncognito: Bool) {
        if let app = row.app {
            openUrlsInApp(app: app)
        } else if let column, let item = row.cells[column] {
            openBrowserItem(item, isIncognito: isIncognito)
        }
    }

    private func subtitle(for row: PickerRow, activeColumn: String?) -> String {
        if row.app != nil {
            return "Open in app"
        }
        if let activeColumn, let item = row.cells[activeColumn] {
            return "Open in \(item.appURL.appDisplayName)"
        }
        return row.cells.count == 1 ? row.iconAppURL.appDisplayName : "\(row.cells.count) browsers"
    }

    @ViewBuilder
    private func rowLogo(_ row: PickerRow) -> some View {
        if let iconPath = row.iconPath, let logo = ProfileImageCache.image(atPath: iconPath) {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .padding(4)
                .frame(width: Self.logoSize, height: Self.logoSize)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.iconAppURL.path))
                .resizable()
                .frame(width: Self.logoSize, height: Self.logoSize)
        }
    }

    private func rowView(_ row: PickerRow, index: Int, columns: [String]) -> some View {
        let isSelected = index == selectedRow
        let activeColumn = isSelected ? PickerLayout.resolvedColumn(in: row, columns: columns, preferring: selectedColumn) : nil

        return HStack(spacing: 12) {
            rowLogo(row)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle(for: row, activeColumn: activeColumn))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 130, alignment: .leading)

            Spacer(minLength: 8)

            if row.app == nil {
                HStack(spacing: 4) {
                    ForEach(columns, id: \.self) { column in
                        if let item = row.cells[column] {
                            PickerCell(item: item, isActive: column == activeColumn, size: Self.cellSize) {
                                openBrowserItem(item, isIncognito: NSEvent.modifierFlags.contains(.shift))
                            }
                        } else {
                            Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
                        }
                    }
                }
            }

            Text(index < 9 ? "\(index + 1)" : " ")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(index < 9 ? 0.08 : 0)))
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            open(
                row,
                column: activeColumn ?? PickerLayout.resolvedColumn(in: row, columns: columns, preferring: nil),
                isIncognito: NSEvent.modifierFlags.contains(.shift)
            )
        }
    }

    @ViewBuilder
    private func shortcutButtons(rows: [PickerRow], columns: [String]) -> some View {
        ForEach(Array(rows.prefix(9).enumerated()), id: \.element.id) { index, row in
            Button(action: {
                open(row, column: PickerLayout.resolvedColumn(in: row, columns: columns, preferring: nil), isIncognito: false)
            }) {}
            .opacity(0)
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        }

        ForEach(PickerLayout.shortcuts(for: rows, columns: columns), id: \.self) { shortcut in
            ForEach([EventModifiers(), .shift], id: \.rawValue) { modifiers in
                Button(action: {
                    open(rows[shortcut.row], column: shortcut.column, isIncognito: NSEvent.modifierFlags.contains(.shift))
                }) {}
                .opacity(0)
                .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: modifiers)
            }
        }
    }

    var body: some View {
        let items = pickerBrowserItems
        let columns = PickerLayout.columns(for: items, browserOrder: browserColumnsOrder)
        let rows = pickerRows(from: items)
        let listHeight = min(CGFloat(rows.count) * (Self.rowHeight + 2), Self.maxListHeight)

        VStack(spacing: 8) {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, index: index, columns: columns)
                                .id(index)
                        }
                    }
                }
                .frame(height: listHeight)
                .focusable()
                .focusEffectDisabledCompat()
                .focused($focused)
                .onMoveCommand { command in
                    guard rows.indices.contains(selectedRow) else {
                        return
                    }

                    switch command {
                    case .up:
                        selectedRow = max(0, selectedRow - 1)
                    case .down:
                        selectedRow = min(rows.count - 1, selectedRow + 1)
                    case .left, .right:
                        let row = rows[selectedRow]
                        let available = PickerLayout.availableColumns(in: row, columns: columns)
                        guard let current = PickerLayout.resolvedColumn(in: row, columns: columns, preferring: selectedColumn),
                              let position = available.firstIndex(of: current)
                        else {
                            return
                        }
                        let next = command == .left ? max(0, position - 1) : min(available.count - 1, position + 1)
                        selectedColumn = available[next]
                    @unknown default:
                        break
                    }
                    scrollViewProxy.scrollTo(selectedRow, anchor: .center)
                }
                .background {
                    Button(action: {
                        openSelected(rows: rows, columns: columns, isIncognito: false)
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.defaultAction)

                    Button(action: {
                        openSelected(rows: rows, columns: columns, isIncognito: true)
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.return, modifiers: [.shift])

                    Button(action: {
                        NSApplication.shared.keyWindow?.close()
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.cancelAction)

                    shortcutButtons(rows: rows, columns: columns)
                }
                .onAppear {
                    ChromiumProfileUtil.refreshArcProfilesIfNeeded(&arcProfiles, shortcuts: &shortcuts)
                    focused.toggle()
                    withAnimation(.interactiveSpring(duration: 0.3)) {
                        opacityAnimation = 1
                    }
                }
                .scrollEdgeEffectDisabledCompat()
            }

            Divider()

            HStack {
                if let host = urls.first?.host() {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.declareTypes([.string], owner: nil)
                        pasteboard.setString(urls.first?.absoluteString ?? "", forType: .string)

                        if closeAfterCopy {
                            NSApplication.shared.keyWindow?.close()
                        }
                    }) {
                        Text(host)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(
                        KeyEquivalent("c"),
                        modifiers: alternativeShortcut ? [.command] : [.command, .option]
                    )
                    .toolTip(urls.first?.absoluteString ?? "")
                }

                Spacer()

                Text("↑↓ identity · ←→ browser · ↵ open")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 268 + CGFloat(columns.count) * (Self.cellSize + 4))
        .background(BlurredView())
        .opacity(opacityAnimation)
        .edgesIgnoringSafeArea(.all)
    }
}

private struct PickerCell: View {
    let item: PickerBrowserItem
    let isActive: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.appURL.path))
                .resizable()
                .frame(width: size - 8, height: size - 8)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white.opacity(isActive ? 0.18 : isHovered ? 0.1 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(isActive ? 0.85 : 0), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.displayName ?? "")
        .accessibilityLabel(item.displayName ?? item.appURL.appDisplayName)
    }
}

/// The picker's layout rules, kept out of the view so they can be unit tested.
enum PickerLayout {
    /// Group names match ignoring case and spaces, so a profile named slightly differently in another browser still joins its group.
    static func groupKey(_ group: String?) -> String? {
        group.map { $0.lowercased().filter { !$0.isWhitespace } }
    }

    static func grouped(_ items: [PickerBrowserItem], order: [String]) -> [PickerBrowserItem] {
        var keys = order.compactMap(groupKey)
        for key in items.compactMap({ groupKey($0.group) }) where !keys.contains(key) {
            keys.append(key)
        }

        return items.enumerated().sorted { lhs, rhs in
            let left = groupKey(lhs.element.group).flatMap { keys.firstIndex(of: $0) } ?? keys.count
            let right = groupKey(rhs.element.group).flatMap { keys.firstIndex(of: $0) } ?? keys.count
            return (left, lhs.offset) < (right, rhs.offset)
        }
        .map(\.element)
    }

    static func groupTitle(_ group: String?, order: [String]) -> String? {
        guard let key = groupKey(group) else {
            return nil
        }

        return order.first { groupKey($0) == key } ?? group
    }

    static func bundleID(of item: PickerBrowserItem) -> String {
        Bundle(url: item.appURL)?.bundleIdentifier ?? item.appURL.absoluteString
    }

    static func columns(for items: [PickerBrowserItem], browserOrder: [String]) -> [String] {
        let present = Set(items.map(bundleID))
        return browserOrder.filter { present.contains($0) }
    }

    static func identityRows(from items: [PickerBrowserItem], order: [String]) -> [PickerRow] {
        var rows: [PickerRow] = []
        var rowIndexByGroup: [String: Int] = [:]

        for item in items {
            let column = bundleID(of: item)
            let key = groupKey(item.group)
            if let key,
               let index = rowIndexByGroup[key],
               rows[index].cells[column] == nil {
                rows[index].cells[column] = item
                rows[index].iconPath = rows[index].iconPath ?? item.iconPath
                continue
            }

            if let key, rowIndexByGroup[key] == nil {
                rowIndexByGroup[key] = rows.count
            }
            rows.append(PickerRow(
                id: item.id,
                title: groupTitle(item.group, order: order) ?? item.displayName ?? item.appURL.appDisplayName,
                iconPath: item.iconPath,
                iconAppURL: item.appURL,
                cells: [column: item]
            ))
        }

        return rows
    }

    struct Shortcut: Hashable {
        let key: Character
        let row: Int
        let column: String?
    }

    static func shortcuts(for rows: [PickerRow], columns: [String]) -> [Shortcut] {
        rows.enumerated().flatMap { index, row -> [Shortcut] in
            if let key = row.shortcutKey?.lowercased().first {
                return [Shortcut(key: key, row: index, column: nil)]
            }

            return columns.compactMap { column in
                row.cells[column]?.shortcutKey?.lowercased().first.map { Shortcut(key: $0, row: index, column: column) }
            }
        }
    }

    static func availableColumns(in row: PickerRow, columns: [String]) -> [String] {
        columns.filter { row.cells[$0] != nil }
    }

    static func resolvedColumn(in row: PickerRow, columns: [String], preferring preferred: String?) -> String? {
        guard let preferred, let target = columns.firstIndex(of: preferred) else {
            return availableColumns(in: row, columns: columns).first
        }

        return columns.indices
            .filter { row.cells[columns[$0]] != nil }
            .min { abs($0 - target) < abs($1 - target) }
            .map { columns[$0] }
    }
}

#Preview {
    PromptView(urls: [])
}
