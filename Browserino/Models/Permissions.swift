//
//  Permissions.swift
//  Browserino
//

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    private static let promptedKey = "sourceDetectionAccessibilityPrompted"

    /// Releases are ad-hoc signed, so macOS drops the permission each update; the version check runs before the slow AXIsProcessTrusted.
    static func promptIfNeeded(rules: [Rule]) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard shouldPrompt(rules: rules, promptedVersion: UserDefaults.standard.string(forKey: promptedKey), version: version) else {
            return
        }

        UserDefaults.standard.set(version, forKey: promptedKey)
        if !isGranted {
            request()
        }
    }

    static func shouldPrompt(rules: [Rule], promptedVersion: String?, version: String?) -> Bool {
        promptedVersion != version && rules.contains(where: \.readsWindowTitle)
    }

    static var isGranted: Bool { AXIsProcessTrusted() }

    /// After an update, System Settings can keep the old build switched on, which no longer counts; clearing it lets the new one be added.
    static func request() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let bundleID = Bundle.main.bundleIdentifier {
                try? Process.run(URL(fileURLWithPath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", bundleID])
                    .waitUntilExit()
            }
            DispatchQueue.main.async {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }
}

enum AutomationPermission {
    enum Status {
        case allowed, notAsked, denied, notRunning
    }

    /// Blocks, and with `ask` until answered, so call it off the main thread; for some apps that aren't running, like Arc, it never returns.
    static func status(of bundleID: String, ask: Bool = false) -> Status {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
              let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc
        else {
            return .notRunning
        }

        switch AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// macOS asks only while the browser is running, so this starts it in the background first.
    static func request(_ app: URL, bundleID: String) -> Status {
        BrowserUtil.launchIfNeeded(app, bundleID: bundleID, activates: false)

        // A browser that has just started takes a moment to accept Apple Events.
        for _ in 0..<20 {
            let status = status(of: bundleID, ask: true)
            if status != .notRunning {
                return status
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return .notRunning
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}
