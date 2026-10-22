//  BrowserUtil.swift
//  Browserino
//
//  Created by byt3m4st3r.
//

import AppKit
import Foundation
import SwiftUI

class BrowserUtil {
    @AppStorage("directories") private static var directories: [Directory] = []
    @AppStorage("privateArgs") private static var privateArgs: [String: String] = [:]

    static func loadBrowsers(
        oldBrowsers: [URL]
    ) -> [URL] {
        if directories.isEmpty {
            let defaultDirectory = Directory(directoryPath: "/Applications")
            directories.append(defaultDirectory)
        }
        
        let validDirectories = directories.map { $0.directoryPath }

        guard let url = URL(string: "https:") else {
            return []
        }

        let urlsForApplications = NSWorkspace.shared.urlsForApplications(toOpen: url)

        var filteredUrlsForApplications = urlsForApplications.filter { urlsForApplication in
            validDirectories.contains { urlsForApplication.path.hasPrefix($0) }
        }
        
        if let browserino = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.jravolio.Linkyard") {
            filteredUrlsForApplications.removeAll { $0 == browserino }
        }

        if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            if !filteredUrlsForApplications.contains(safari) {
                filteredUrlsForApplications.append(safari)
            }
        }
        
        var oldPositions: [URL: Int] = [:]
        for (index, browser) in oldBrowsers.enumerated() {
            oldPositions[browser] = index
        }
        
        filteredUrlsForApplications.sort { browser1, browser2 in
            if let pos1 = oldPositions[browser1], let pos2 = oldPositions[browser2] {
                return pos1 < pos2
            }
            else if oldPositions[browser1] != nil {
                return true
            }
            else if oldPositions[browser2] != nil {
                return false
            }
            
            return true
        }
        
        return filteredUrlsForApplications
    }
    
    static func openURL(_ urls: [URL], app: URL, isIncognito: Bool, profileDirectory: String? = nil) {
        guard let bundle = Bundle(url: app) else {
            return
        }

        if bundle.bundleIdentifier == ChromiumProfileUtil.arcBundleID {
            if profileDirectory != nil || isIncognito {
                if openArcURLs(urls, isIncognito: isIncognito, profileDirectory: profileDirectory) {
                    return
                }
            }

            NSWorkspace.shared.open(
                urls,
                withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        if bundle.bundleIdentifier == ChromiumProfileUtil.diaBundleID,
           let profileDirectory,
           !isIncognito,
           openDiaURLs(urls, profileName: profileDirectory) {
            return
        }

        if bundle.bundleIdentifier == ChromiumProfileUtil.zenBundleID, let profileDirectory, !isIncognito {
            NSWorkspace.shared.open(
                urls.compactMap { zenContainerURL(for: $0, container: profileDirectory) },
                withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        let supportsProfiles = ChromiumProfileUtil.source(for: bundle.bundleIdentifier)?.kind == .chromium

        var args: [String] = []

        if let profileDirectory, supportsProfiles {
            args.append("--profile-directory=\(profileDirectory)")
        }

        if isIncognito, let privateArg = privateArgs[bundle.bundleIdentifier!] {
            args.append(privateArg)
        }

        if !args.isEmpty {
            configuration.createsNewApplicationInstance = true
            configuration.arguments = args + urls.map(\.absoluteString)
        }

        NSWorkspace.shared.open(
            args.isEmpty ? urls : [],
            withApplicationAt: app,
            configuration: configuration
        )
    }

    private static func openArcURLs(_ urls: [URL], isIncognito: Bool, profileDirectory: String?) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        if isIncognito {
            return runAppleScript("""
            tell application id "\(ChromiumProfileUtil.arcBundleID)"
                activate
                make new window with properties {incognito:true}
                tell front window
            \(arcTabCommands(for: urls))
                end tell
            end tell
            """)
        }

        guard let spaceID = ChromiumProfileUtil.arcSpaceID(for: profileDirectory) else {
            return false
        }

        return runAppleScript("""
        tell application id "\(ChromiumProfileUtil.arcBundleID)"
            activate
            if (count of windows) is 0 then make new window
            tell front window
                set didFocus to false
                repeat with arcSpace in spaces
                    if id of arcSpace is "\(escapeAppleScriptString(spaceID))" then
                        tell arcSpace to focus
                        set didFocus to true
                        exit repeat
                    end if
                end repeat
                if didFocus is false then error "Arc space not found"
        \(arcTabCommands(for: urls))
            end tell
        end tell
        """)
    }

    private static func openDiaURLs(_ urls: [URL], profileName: String) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        let tabCommands = urls.map {
            "                set newTab to make new tab at end of tabs with properties {URL:\"\(escapeAppleScriptString($0.absoluteString))\"}"
        }
        .joined(separator: "\n")

        return runAppleScript("""
        tell application id "\(ChromiumProfileUtil.diaBundleID)"
            activate
            if (count of windows) is 0 then make new window
            tell front window
                set targetProfile to missing value
                repeat with diaProfile in profiles
                    if name of diaProfile is "\(escapeAppleScriptString(profileName))" then set targetProfile to diaProfile
                end repeat
                if targetProfile is missing value then error "Dia profile not found"
                tell targetProfile
                    focus
        \(tabCommands)
                end tell
                tell newTab to focus
            end tell
        end tell
        """)
    }

    /// Handled by the "Open external links in a container" Firefox add-on, which must be installed in Zen.
    private static func zenContainerURL(for url: URL, container: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let name = container.addingPercentEncoding(withAllowedCharacters: allowed),
              let target = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
            return nil
        }

        return URL(string: "ext+container:name=\(name)&url=\(target)")
    }

    private static func arcTabCommands(for urls: [URL]) -> String {
        urls.map {
            "                make new tab with properties {URL:\"\(escapeAppleScriptString($0.absoluteString))\"}"
        }
        .joined(separator: "\n")
    }

    private static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error {
            print("Failed to open browser with AppleScript: \(error)")
            return false
        }

        return true
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
