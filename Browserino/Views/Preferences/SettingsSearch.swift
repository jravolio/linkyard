//
//  SettingsSearch.swift
//  Browserino
//

import Foundation

/// IDs of rows for things the user set up, shared by the search index and the panes that show them.
enum SettingsItemID {
    static func browser(_ url: URL) -> String { "browser.\(url.path)" }
    static func profiles(_ source: ChromiumProfileSource) -> String { "profiles.\(source.bundleID)" }
    static func profile(_ source: ChromiumProfileSource, _ profile: ChromeProfile) -> String {
        "profile.\(ChromiumProfileUtil.profileID(source.bundleID, profile.selectionID))"
    }
    static func rule(_ index: Int) -> String { "rule.\(index)" }
    static func app(_ index: Int) -> String { "app.\(index)" }
    static func automation(_ source: ChromiumProfileSource) -> String { "permissions.automation.\(source.bundleID)" }
}

struct SettingsSearchItem: Identifiable, Equatable {
    let id: String
    let pane: SettingsPane
    let title: String
    var detail: String? = nil
    var keywords: [String] = []
}

enum SettingsSearch {
    static let settings: [SettingsSearchItem] = [
        SettingsSearchItem(id: "general.defaultBrowser", pane: .general, title: "Default browser", keywords: ["make default"]),
        SettingsSearchItem(id: "general.launchAtLogin", pane: .general, title: "Open at login", keywords: ["launch", "startup", "start"]),
        SettingsSearchItem(id: "general.menuBar", pane: .general, title: "Show in menu bar", keywords: ["icon", "status bar"]),
        SettingsSearchItem(id: "general.backup", pane: .general, title: "Export or import settings", keywords: ["backup", "restore", "file", "json"]),
        SettingsSearchItem(id: "general.reset", pane: .general, title: "Reset all settings", keywords: ["clear", "erase", "delete"]),
        SettingsSearchItem(id: "picker.position", pane: .picker, title: "Where the picker opens", keywords: ["position", "pointer", "cursor", "center", "screen"]),
        SettingsSearchItem(
            id: "picker.animation",
            pane: .picker,
            title: "Animation",
            keywords: ["motion", "effect", "transition", "appear"] + PickerAnimation.allCases.map(\.title)
        ),
        SettingsSearchItem(id: "picker.appsFirst", pane: .picker, title: "Show apps before browsers", keywords: ["order"]),
        SettingsSearchItem(id: "picker.copyShortcut", pane: .picker, title: "Copy link shortcut", keywords: ["copy", "clipboard", "command"]),
        SettingsSearchItem(id: "picker.closeAfterCopy", pane: .picker, title: "Close the picker after copying", keywords: ["copy"]),
        SettingsSearchItem(id: "picker.keyboard", pane: .picker, title: "Keyboard shortcuts", keywords: ["keys", "arrows", "return", "escape", "private"]),
        SettingsSearchItem(id: "browsers.list", pane: .browsers, title: "Browser order", keywords: ["reorder", "hide", "show", "shortcut"]),
        SettingsSearchItem(id: "browsers.rescan", pane: .browsers, title: "Rescan browsers", keywords: ["refresh", "find", "installed"]),
        SettingsSearchItem(id: "browsers.private", pane: .browsers, title: "Private window flags", keywords: ["incognito", "argument"]),
        SettingsSearchItem(id: "browsers.locations", pane: .browsers, title: "Where to look for browsers", keywords: ["folder", "directory", "applications", "locations"]),
        SettingsSearchItem(id: "rules.add", pane: .rules, title: "Add a rule", keywords: ["route", "automatic", "pattern", "regex", "source app", "window title"]),
        SettingsSearchItem(id: "apps.add", pane: .apps, title: "Add an app", keywords: ["open in app", "website", "domain", "scheme"]),
        SettingsSearchItem(id: "permissions.accessibility", pane: .permissions, title: "Accessibility", keywords: ["permission", "privacy", "allow", "window title", "slack"]),
        SettingsSearchItem(id: "about.version", pane: .about, title: "Version", keywords: ["about", "credits", "github", "browserino", "license"]),
    ]

    static func index(
        browsers: [URL],
        profiles: [(source: ChromiumProfileSource, profiles: [ChromeProfile])],
        rules: [Rule],
        apps: [App]
    ) -> [SettingsSearchItem] {
        var items = settings

        for browser in browsers where Bundle(url: browser)?.bundleIdentifier != nil {
            items.append(SettingsSearchItem(id: SettingsItemID.browser(browser), pane: .browsers, title: browser.appDisplayName, detail: "Browser"))
        }

        for (app, source) in ChromiumProfileUtil.appleEventsBrowsers(in: browsers) {
            items.append(SettingsSearchItem(
                id: SettingsItemID.automation(source),
                pane: .permissions,
                title: "Control \(app.appDisplayName)",
                detail: "Permissions",
                keywords: ["permission", "privacy", "allow", "automation", "apple events"]
            ))
        }

        for (source, sourceProfiles) in profiles {
            items.append(SettingsSearchItem(
                id: SettingsItemID.profiles(source),
                pane: .profiles,
                title: "\(source.displayName) \(source.profileLabel)"
            ))
            for profile in sourceProfiles {
                items.append(SettingsSearchItem(
                    id: SettingsItemID.profile(source, profile),
                    pane: .profiles,
                    title: profile.displayName,
                    detail: "\(source.displayName) \(source.profileLabel.dropLast())",
                    keywords: [profile.directoryName]
                ))
            }
        }

        let profilesByBundleID = Dictionary(profiles.map { ($0.source.bundleID, $0.profiles) }, uniquingKeysWith: { first, _ in first })
        for (index, rule) in rules.enumerated() {
            items.append(SettingsSearchItem(
                id: SettingsItemID.rule(index),
                pane: .rules,
                title: rule.title,
                detail: rule.summary(profiles: profilesByBundleID),
                keywords: [rule.regex, rule.sourceWindowTitleRegex ?? ""]
            ))
        }

        for (index, app) in apps.enumerated() {
            items.append(SettingsSearchItem(id: SettingsItemID.app(index), pane: .apps, title: app.title, detail: app.summary))
        }

        return items
    }

    static func results(for query: String, in items: [SettingsSearchItem]) -> [SettingsSearchItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return []
        }

        return items
            .filter { item in
                let text = ([item.title, item.detail ?? "", item.pane.title] + item.keywords).joined(separator: " ")
                return words.allSatisfy { text.localizedStandardContains($0) }
            }
            .enumerated()
            .sorted { lhs, rhs in
                let left = words.allSatisfy { lhs.element.title.localizedStandardContains($0) } ? 0 : 1
                let right = words.allSatisfy { rhs.element.title.localizedStandardContains($0) } ? 0 : 1
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map(\.element)
    }
}
