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

        let kind = ChromiumProfileUtil.source(for: bundle.bundleIdentifier)?.kind

        switch kind {
        case .arc:
            if profileDirectory != nil || isIncognito,
               openArcURLs(urls, isIncognito: isIncognito, profileDirectory: profileDirectory) {
                return
            }

            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return
        case .dia:
            if let profileDirectory, !isIncognito {
                openDiaURLs(urls, app: app, profileName: profileDirectory)
                return
            }
        case .zenContainers:
            if let profileDirectory, !isIncognito {
                NSWorkspace.shared.open(
                    urls.compactMap { zenContainerURL(for: $0, container: profileDirectory) },
                    withApplicationAt: app,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        case .chromium, nil:
            break
        }

        let configuration = NSWorkspace.OpenConfiguration()
        let supportsProfiles = kind == .chromium

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
            \(tabCommands(for: urls))
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
        \(tabCommands(for: urls))
            end tell
        end tell
        """)
    }

    /// Each event waits for Dia's reply (~100 ms a link, as long as the first Automation prompt stays up), so they're
    /// sent off the main thread. One serial queue keeps links in the order they were clicked.
    private static let diaQueue = DispatchQueue(label: "Dia Apple Events", qos: .userInitiated)

    private static func openDiaURLs(_ urls: [URL], app: URL, profileName: String) {
        diaQueue.async {
            // Launching happens on the queue too, so links clicked while Dia starts still open in click order.
            if NSRunningApplication.runningApplications(withBundleIdentifier: ChromiumProfileUtil.diaBundleID).isEmpty {
                let launched = DispatchSemaphore(value: 0)
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    launched.signal()
                }
                launched.wait()
            }

            let remaining = sendDiaURLs(urls, profileName: profileName)
            if !remaining.isEmpty {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(remaining, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    typealias AppleEventSender = (
        _ eventClass: String,
        _ eventID: String,
        _ parameters: [String: NSAppleEventDescriptor],
        _ waitsForReply: Bool
    ) throws -> NSAppleEventDescriptor

    /// The events AppleScript sends for `activate` and `make new tab at end of tabs of (first profile whose name is …)
    /// of front window`. Making a tab in a profile already switches the window to that profile and focuses the tab.
    /// Returns the links it couldn't open, which the caller opens in Dia without picking a profile.
    static func sendDiaURLs(
        _ urls: [URL],
        profileName: String,
        send: AppleEventSender = { try AppleEvents.send($0, $1, to: ChromiumProfileUtil.diaBundleID, $2, waitsForReply: $3) }
    ) -> [URL] {
        let tabs = AppleEvents.every("DiaT", of: AppleEvents.named("DiaP", profileName, of: AppleEvents.element("cwin", at: 1)))
        var opened = 0
        func makeTabs() throws {
            for url in urls[opened...] {
                _ = try send("core", "crel", [
                    "kocl": AppleEvents.type("DiaT"),
                    "insh": AppleEvents.end(of: tabs),
                    "prdt": AppleEvents.record(["URL ": NSAppleEventDescriptor(string: url.absoluteString)]),
                ], true)
                opened += 1
            }
        }

        do {
            _ = try send("misc", "actv", [:], false)
            do {
                try makeTabs()
            } catch {
                // Counting windows first would cost an event on every link; Dia only has none after its last window closed.
                let windows = try send("core", "cnte", ["kocl": AppleEvents.type("cwin"), "----": .null()], true)
                guard windows.paramDescriptor(forKeyword: keyDirectObject)?.int32Value == 0 else {
                    throw error
                }
                _ = try send("core", "crel", ["kocl": AppleEvents.type("cwin")], true)
                try makeTabs()
            }
            return []
        } catch {
            print("Failed to open Dia with Apple Events: \(error)")
            return Array(urls[opened...])
        }
    }

    /// Handled by the "Open external links in a container" Firefox add-on, which must be installed in Zen.
    static func zenContainerURL(for url: URL, container: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let name = container.addingPercentEncoding(withAllowedCharacters: allowed),
              let target = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
            return nil
        }

        return URL(string: "ext+container:name=\(name)&url=\(target)")
    }

    private static func tabCommands(for urls: [URL]) -> String {
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

    static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
