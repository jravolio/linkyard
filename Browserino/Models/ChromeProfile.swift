//
//  ChromeProfile.swift
//  Browserino
//

import AppKit
import Foundation
import SwiftUI

struct ChromeProfile: Codable, Hashable {
    var directoryName: String
    var displayName: String
    var isHidden: Bool = false
    var arcSpaceID: String? = nil
    var iconPath: String? = nil

    var selectionID: String {
        arcSpaceID ?? directoryName
    }

    /// Rules saved before Arc spaces were keyed by ID still name the profile folder.
    func matches(_ selection: String) -> Bool {
        selectionID == selection || directoryName == selection
    }
}

enum ProfileSourceKind {
    case chromium
    case arc
    /// Dia refuses `--profile-directory`, so its profiles are opened by name with AppleScript.
    case dia
    case zenContainers
}

struct ChromiumProfileSource: Hashable {
    let bundleID: String
    let displayName: String
    let localStatePath: String
    let profileLabel: String
    let kind: ProfileSourceKind

    var detectsArcSpaces: Bool { kind == .arc }
    var usesAppleEvents: Bool { kind == .arc || kind == .dia }
    var profileNoun: String { String(profileLabel.dropLast()) }
}

class ChromiumProfileUtil {
    static let chromeBundleID = "com.google.Chrome"
    static let arcBundleID = "company.thebrowser.Browser"
    static let diaBundleID = "company.thebrowser.dia"
    static let zenBundleID = "app.zen-browser.zen"
    static let heliumBundleID = "net.imput.helium"

    static let chromeSource = ChromiumProfileSource(
        bundleID: chromeBundleID,
        displayName: "Google Chrome",
        localStatePath: "~/Library/Application Support/Google/Chrome/Local State",
        profileLabel: "profiles",
        kind: .chromium
    )

    static let arcSource = ChromiumProfileSource(
        bundleID: arcBundleID,
        displayName: "Arc",
        localStatePath: "~/Library/Application Support/Arc/User Data/Local State",
        profileLabel: "spaces",
        kind: .arc
    )

    static let diaSource = ChromiumProfileSource(
        bundleID: diaBundleID,
        displayName: "Dia",
        localStatePath: "~/Library/Application Support/Dia/User Data/Local State",
        profileLabel: "profiles",
        kind: .dia
    )

    static let zenSource = ChromiumProfileSource(
        bundleID: zenBundleID,
        displayName: "Zen",
        localStatePath: "~/Library/Application Support/zen",
        profileLabel: "containers",
        kind: .zenContainers
    )

    static let heliumSource = ChromiumProfileSource(
        bundleID: heliumBundleID,
        displayName: "Helium",
        localStatePath: "~/Library/Application Support/net.imput.helium/Local State",
        profileLabel: "profiles",
        kind: .chromium
    )

    static let sources = [chromeSource, arcSource, diaSource, zenSource, heliumSource]

    /// Each browser in `browsers` that Linkyard opens links in through Apple Events, once.
    static func appleEventsBrowsers(in browsers: [URL]) -> [(app: URL, source: ChromiumProfileSource)] {
        var seen: Set<String> = []
        return browsers.compactMap { app in
            guard let source = source(for: Bundle(url: app)?.bundleIdentifier), source.usesAppleEvents, seen.insert(source.bundleID).inserted else {
                return nil
            }
            return (app, source)
        }
    }

    static func source(for bundleID: String?) -> ChromiumProfileSource? {
        guard let bundleID else {
            return nil
        }

        return sources.first { $0.bundleID == bundleID }
    }

    static func appURL(for source: ChromiumProfileSource) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
    }

    static func detectProfiles(for source: ChromiumProfileSource) -> [ChromeProfile] {
        switch source.kind {
        case .arc:
            let spaces = detectArcSpaces()
            if !spaces.isEmpty {
                return spaces
            }
        case .dia:
            return detectDiaProfiles(source: source)
        case .zenContainers:
            return detectZenContainers(source: source)
        case .chromium:
            break
        }

        return localStateProfiles(for: source)
    }

    private static func localStateProfiles(for source: ChromiumProfileSource) -> [ChromeProfile] {
        let localStatePath = NSString(string: source.localStatePath)
            .expandingTildeInPath

        guard let data = FileManager.default.contents(atPath: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileInfo = json["profile"] as? [String: Any],
              let infoCache = profileInfo["info_cache"] as? [String: Any]
        else {
            return []
        }

        return infoCache.compactMap { (dirName, value) in
            guard let profileDict = value as? [String: Any],
                  let name = profileDict["name"] as? String
            else {
                return nil
            }

            return ChromeProfile(
                directoryName: dirName,
                displayName: name
            )
        }
        .sorted { $0.directoryName < $1.directoryName }
    }

    private static func detectDiaProfiles(source: ChromiumProfileSource) -> [ChromeProfile] {
        // `name of every profile of front window`; it fails when Dia has no window.
        if !NSRunningApplication.runningApplications(withBundleIdentifier: diaBundleID).isEmpty,
           let reply = try? AppleEvents.send("core", "getd", to: diaBundleID, [
               "----": AppleEvents.property("pnam", of: AppleEvents.every("DiaP", of: AppleEvents.element("cwin", at: 1))),
           ]),
           let list = reply.paramDescriptor(forKeyword: keyDirectObject) {
            let names = (0..<list.numberOfItems).compactMap { list.atIndex($0 + 1)?.stringValue }
            if !names.isEmpty {
                return names.map { ChromeProfile(directoryName: $0, displayName: $0) }
            }
        }

        // Dia shows its Default profile as "Personal" whatever name Local State still has.
        return localStateProfiles(for: source).map { profile in
            let name = profile.directoryName == "Default" ? "Personal" : profile.displayName
            return ChromeProfile(directoryName: name, displayName: name)
        }
    }

    private static func detectZenContainers(source: ChromiumProfileSource) -> [ChromeProfile] {
        let root = NSString(string: source.localStatePath).expandingTildeInPath
        guard let installs = try? String(contentsOfFile: "\(root)/installs.ini", encoding: .utf8),
              let profilePath = installs.split(separator: "\n")
                .first(where: { $0.hasPrefix("Default=") })?
                .dropFirst("Default=".count),
              let data = FileManager.default.contents(atPath: "\(root)/\(profilePath)/containers.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identities = json["identities"] as? [[String: Any]]
        else {
            return []
        }

        return identities.compactMap { identity in
            guard identity["public"] as? Bool == true,
                  let name = identity["name"] as? String,
                  !name.isEmpty
            else {
                return nil
            }

            return ChromeProfile(directoryName: name, displayName: name)
        }
    }

    /// Shortcuts and picker groups are stored under this ID, so its format can't change.
    static func profileID(_ bundleID: String, _ selectionID: String) -> String {
        "\(bundleID)::\(selectionID)"
    }

    /// Re-detects Arc spaces when they changed, and moves shortcuts saved under a profile folder to the space ID.
    /// Writes only what changed: every write redraws the views that read these settings.
    static func refreshArcProfilesIfNeeded(_ profiles: Binding<[ChromeProfile]>, shortcuts: Binding<[String: String]>) {
        let current = profiles.wrappedValue
        guard shouldRefreshProfiles(for: arcSource, profiles: current) else {
            return
        }

        let refreshed = refreshProfiles(for: arcSource, existing: current)
        let currentShortcuts = shortcuts.wrappedValue
        let migrated = migrateShortcuts(currentShortcuts, for: arcSource, profiles: refreshed)
        if refreshed != current {
            profiles.wrappedValue = refreshed
        }
        if migrated != currentShortcuts {
            shortcuts.wrappedValue = migrated
        }
    }

    static func refreshProfiles(for source: ChromiumProfileSource, existing: [ChromeProfile]) -> [ChromeProfile] {
        mergeProfiles(
            existing: existing,
            detected: detectProfiles(for: source),
            source: source
        )
    }

    static func migrateShortcuts(
        _ shortcuts: [String: String],
        for source: ChromiumProfileSource,
        profiles: [ChromeProfile]
    ) -> [String: String] {
        guard source.detectsArcSpaces else {
            return shortcuts
        }

        var migratedShortcuts = shortcuts

        for profile in profiles where profile.selectionID != profile.directoryName {
            let oldID = profileID(source.bundleID, profile.directoryName)
            let newID = profileID(source.bundleID, profile.selectionID)

            guard migratedShortcuts[newID] == nil,
                  let shortcut = migratedShortcuts[oldID]
            else {
                continue
            }

            migratedShortcuts[newID] = shortcut
            migratedShortcuts[oldID] = nil
        }

        return migratedShortcuts
    }

    static func shouldRefreshProfiles(for source: ChromiumProfileSource, profiles: [ChromeProfile]) -> Bool {
        guard !profiles.isEmpty else {
            return true
        }

        guard source.detectsArcSpaces else {
            return false
        }

        if profiles.contains(where: { $0.arcSpaceID == nil }) {
            return true
        }

        let detectedIDs = Set(detectProfiles(for: source).map(\.selectionID))
        let storedIDs = Set(profiles.map(\.selectionID))

        return detectedIDs != storedIDs
    }

    /// Arc spaces stored under their profile folder (before they were keyed by space ID) take the detected name.
    static func mergeProfiles(
        existing: [ChromeProfile],
        detected: [ChromeProfile],
        source: ChromiumProfileSource
    ) -> [ChromeProfile] {
        detected.map { profile in
            let sameID = existing.first { $0.selectionID == profile.selectionID }
            guard let match = sameID ?? (source.detectsArcSpaces ? existing.first { $0.directoryName == profile.directoryName } : nil) else {
                return profile
            }

            var merged = profile
            merged.isHidden = match.isHidden
            merged.iconPath = match.iconPath
            if sameID != nil {
                merged.displayName = match.displayName
            }
            return merged
        }
    }

    static func arcSpaceID(for selection: String?) -> String? {
        guard let selection else {
            return nil
        }

        return detectArcSpaces().first {
            $0.matches(selection)
        }?.arcSpaceID
    }

    /// StorableSidebar.json can be megabytes and the picker checks it every time it opens.
    private static var arcSpacesCache: (modified: Date, spaces: [ChromeProfile])?

    private static func detectArcSpaces() -> [ChromeProfile] {
        let sidebarPath = NSString(string: "~/Library/Application Support/Arc/StorableSidebar.json")
            .expandingTildeInPath

        guard let modified = (try? FileManager.default.attributesOfItem(atPath: sidebarPath))?[.modificationDate] as? Date else {
            return []
        }
        if let cache = arcSpacesCache, cache.modified == modified {
            return cache.spaces
        }

        guard let data = FileManager.default.contents(atPath: sidebarPath),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

        let spaces = arcSpaces(fromSidebar: json)
        arcSpacesCache = (modified, spaces)
        return spaces
    }

    static func arcSpaces(fromSidebar json: Any) -> [ChromeProfile] {
        var profiles: [ChromeProfile] = []
        var seenSpaceIDs: Set<String> = []
        collectArcSpaces(from: json, profiles: &profiles, seenSpaceIDs: &seenSpaceIDs)

        let order = Dictionary(uniqueKeysWithValues: (findOrderedArcSpaceIDs(in: json) ?? []).enumerated().map { ($0.element, $0.offset) })
        return profiles.sorted {
            (order[$0.arcSpaceID ?? ""] ?? Int.max, $0.displayName) <
                (order[$1.arcSpaceID ?? ""] ?? Int.max, $1.displayName)
        }
    }

    private static func collectArcSpaces(
        from value: Any,
        profiles: inout [ChromeProfile],
        seenSpaceIDs: inout Set<String>
    ) {
        if let dictionary = value as? [String: Any] {
            if let id = dictionary["id"] as? String,
               let title = dictionary["title"] as? String,
               let profile = dictionary["profile"] as? [String: Any],
               dictionary["containerIDs"] != nil,
               let directoryName = arcProfileDirectory(from: profile),
               seenSpaceIDs.insert(id).inserted {
                profiles.append(ChromeProfile(
                    directoryName: directoryName,
                    displayName: title,
                    arcSpaceID: id
                ))
            }

            for child in dictionary.values {
                collectArcSpaces(from: child, profiles: &profiles, seenSpaceIDs: &seenSpaceIDs)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectArcSpaces(from: child, profiles: &profiles, seenSpaceIDs: &seenSpaceIDs)
            }
        }
    }

    private static func arcProfileDirectory(from profile: [String: Any]) -> String? {
        if profile["default"] as? Bool == true {
            return "Default"
        }

        guard let custom = profile["custom"] as? [String: Any],
              let customProfile = custom["_0"] as? [String: Any],
              let directoryName = customProfile["directoryBasename"] as? String
        else {
            return nil
        }

        return directoryName
    }

    private static func findOrderedArcSpaceIDs(in value: Any) -> [String]? {
        if let dictionary = value as? [String: Any] {
            if let orderedSpaceIDs = dictionary["orderedSpaceIDs"] as? [String] {
                return orderedSpaceIDs
            }

            for child in dictionary.values {
                if let orderedSpaceIDs = findOrderedArcSpaceIDs(in: child) {
                    return orderedSpaceIDs
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let orderedSpaceIDs = findOrderedArcSpaceIDs(in: child) {
                    return orderedSpaceIDs
                }
            }
        }

        return nil
    }
}
