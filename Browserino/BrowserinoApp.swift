//
//  BrowserinoApp.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI
import Foundation
import ApplicationServices
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var selectorWindow: BrowserinoWindow?
    private var preferencesWindow: NSWindow?
    private var lastSourceApplication: SourceApplicationSnapshot?
    private let sourceDetectionLogger = SourceDetectionLogger()
    
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    
    var statusMenu: NSMenu!
    var statusBarItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        refreshStoredArcProfilesIfNeeded()
        sourceDetectionLogger.promptForAccessibilityPermissionIfNeeded(reason: "launch")
        rememberSourceApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        setupStatusBar()
        
        UserDefaults.standard.addObserver(self, forKeyPath: "showInMenuBar", options: [.new], context: nil)
        
        if UserDefaults.standard.object(forKey: "browsers") == nil {
            openPreferences()
        }
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        rememberSourceApplication(
            notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        )
    }

    private func rememberSourceApplication(_ application: NSRunningApplication?) {
        guard let application else {
            return
        }

        if application.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        lastSourceApplication = SourceApplicationSnapshot(application: application)
    }

    private func refreshStoredArcProfilesIfNeeded() {
        guard ChromiumProfileUtil.appURL(for: ChromiumProfileUtil.arcSource) != nil else {
            return
        }

        if ChromiumProfileUtil.shouldRefreshProfiles(
            for: ChromiumProfileUtil.arcSource,
            profiles: arcProfiles
        ) {
            arcProfiles = ChromiumProfileUtil.refreshProfiles(
                for: ChromiumProfileUtil.arcSource,
                existing: arcProfiles
            )
        }

        shortcuts = ChromiumProfileUtil.migrateShortcuts(
            shortcuts,
            for: ChromiumProfileUtil.arcSource,
            profiles: arcProfiles
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        self.openPreferences()
        return true
    }
    
    func setupStatusBar() {
        if showInMenuBar {
            if statusBarItem == nil {
                statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let statusButton = statusBarItem!.button
                statusButton!.image = NSImage.menuIcon
                
                let preferences = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: "")
                let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
                
                statusMenu = NSMenu()
                
                statusMenu!.addItem(preferences)
                statusMenu!.addItem(.separator())
                statusMenu!.addItem(quit)
                
                statusBarItem!.menu = statusMenu!
            }
        } else {
            if statusBarItem != nil {
                NSStatusBar.system.removeStatusItem(statusBarItem!)
                statusBarItem = nil
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "showInMenuBar" {
            setupStatusBar()
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "showInMenuBar")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        if userActivityType == NSUserActivityTypeBrowsingWeb {
            return true
        }
        
        return false
    }
    
    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            self.application(application, open: [url])
            return true
        }
        
        return false
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.miniaturizable, .closable, .resizable, .titled],
                backing: .buffered,
                defer: false
            )
        }
        
        preferencesWindow!.center()
        preferencesWindow!.title = "Preferences"
        preferencesWindow!.contentView = NSHostingView(rootView: PreferencesView())
        
        preferencesWindow!.isReleasedWhenClosed = false
        preferencesWindow!.titlebarAppearsTransparent = true
        
        preferencesWindow!.contentMinSize = NSSize(width: 700, height: 500)
        
        preferencesWindow!.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        preferencesWindow!.makeKeyAndOrderFront(nil)
        preferencesWindow!.orderFrontRegardless()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        var processedUrls = urls
        
        if urls.count == 1 {
            let url = urls.first!
            
            if url.scheme == "browserino" && url.host == "open" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let encodedUrl = queryItems.first(where: { $0.name == "url" })?.value,
                   let decodedData = Data(base64Encoded: encodedUrl),
                   let decodedUrlString = String(data: decodedData, encoding: .utf8),
                   let decodedUrl = URL(string: decodedUrlString) {
                    processedUrls = [decodedUrl]
                } else {
                    return
                }
            }
        }

        let sourceContext = SourceRuleContext(application: lastSourceApplication)
        let shouldBypassRules = isCommandKeyPressed()
        sourceDetectionLogger.log(
            urls: processedUrls,
            currentApplication: NSWorkspace.shared.frontmostApplication.map { SourceApplicationSnapshot(application: $0) },
            sourceApplication: lastSourceApplication,
            sourceWindowTitle: sourceContext.windowTitle,
            rulesBypassedByCommand: shouldBypassRules
        )

        if processedUrls.count == 1 && !shouldBypassRules {
            let urlString = processedUrls.first!.absoluteString

            for rule in rules {
                if ruleMatches(rule, urlString: urlString, sourceContext: sourceContext) {
                    BrowserUtil.openURL(
                        processedUrls,
                        app: rule.app,
                        isIncognito: false,
                        profileDirectory: rule.profileDirectory
                    )
                    return
                }
            }
        }
        
        if selectorWindow == nil {
            selectorWindow = BrowserinoWindow()
        }
        
        let screen = getScreenWithMouse()!.visibleFrame
        
        selectorWindow?.setFrameOrigin(
            NSPoint(
                x: clamp(
                    min: screen.minX + 20,
                    max: screen.maxX - selectorWindow!.frame.width - 20,
                    value: NSEvent.mouseLocation.x - selectorWindow!.frame.width / 2
                ),
                y: clamp(
                    min: screen.minY + 20,
                    max: screen.maxY - selectorWindow!.frame.height - 20,
                    value: NSEvent.mouseLocation.y - (selectorWindow!.frame.height - 30)
                )
            )
        )
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        selectorWindow!.deactivateDelay()
        
        selectorWindow!.contentView = NSHostingView(
            rootView: PromptView(
                urls: processedUrls
            )
        )
        
        selectorWindow!.makeKeyAndOrderFront(nil)
        selectorWindow!.isReleasedWhenClosed = false
        selectorWindow!.delegate = self
    }

    private func isCommandKeyPressed() -> Bool {
        NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
    }
    
    func clamp(min: CGFloat, max: CGFloat, value: CGFloat) -> CGFloat {
        CGFloat.minimum(CGFloat.maximum(min, value), max)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if selectorWindow!.hidesOnDeactivate {
            selectorWindow!.contentView = nil
            selectorWindow!.close()
        }
    }

    private func ruleMatches(_ rule: Rule, urlString: String, sourceContext: SourceRuleContext) -> Bool {
        guard let regex = try? Regex(rule.regex).ignoresCase(),
              urlString.firstMatch(of: regex) != nil
        else {
            return false
        }

        if let sourceApp = rule.sourceApp {
            guard let ruleSourceBundleID = Bundle(url: sourceApp)?.bundleIdentifier,
                  sourceContext.application?.bundleIdentifier == ruleSourceBundleID
            else {
                return false
            }
        }

        let sourceWindowTitleRegex = rule.sourceWindowTitleRegex?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sourceWindowTitleRegex, !sourceWindowTitleRegex.isEmpty {
            guard let sourceWindowTitle = sourceContext.windowTitle,
                  let regex = try? Regex(sourceWindowTitleRegex).ignoresCase(),
                  sourceWindowTitle.firstMatch(of: regex) != nil
            else {
                return false
            }
        }

        return true
    }
    
    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        
        return screenWithMouse
    }
}

private struct SourceApplicationSnapshot {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    let executablePath: String?
    let activatedAt: Date

    init(application: NSRunningApplication) {
        self.bundleIdentifier = application.bundleIdentifier
        self.localizedName = application.localizedName
        self.processIdentifier = application.processIdentifier
        self.executablePath = application.executableURL?.path
        self.activatedAt = Date()
    }

    var isSlack: Bool {
        if bundleIdentifier?.localizedCaseInsensitiveContains("slack") == true {
            return true
        }

        return localizedName?.localizedCaseInsensitiveContains("slack") == true
    }

    func dictionary(relativeTo now: Date) -> [String: Any] {
        [
            "bundle_id": bundleIdentifier ?? NSNull(),
            "name": localizedName ?? NSNull(),
            "pid": Int(processIdentifier),
            "executable_path": executablePath ?? NSNull(),
            "age_ms": Int(now.timeIntervalSince(activatedAt) * 1000)
        ]
    }
}

private struct SourceRuleContext {
    let application: SourceApplicationSnapshot?
    let windowTitle: String?

    init(application: SourceApplicationSnapshot?) {
        self.application = application

        if let application, application.isSlack {
            self.windowTitle = SlackAccessibilityProbe.windowTitle(processIdentifier: application.processIdentifier)
        } else {
            self.windowTitle = nil
        }
    }
}

private final class SourceDetectionLogger {
    private let logger = Logger(
        subsystem: "xyz.alexstrnik.Browserino",
        category: "SourceDetection"
    )
    private let accessibilityPromptedKey = "sourceDetectionAccessibilityPrompted"

    private let dateFormatter = ISO8601DateFormatter()
    private lazy var logFileURL: URL? = {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }

        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Browserino", isDirectory: true)
            .appendingPathComponent("source-detection.jsonl")
    }()

    func promptForAccessibilityPermissionIfNeeded(reason: String) {
        let now = Date()
        let axTrustedBeforePrompt = AXIsProcessTrusted()
        let hasPrompted = UserDefaults.standard.bool(forKey: accessibilityPromptedKey)
        let axPrompted = axTrustedBeforePrompt || hasPrompted ? false : promptForAccessibilityPermission()
        let axTrusted = AXIsProcessTrusted()

        if axPrompted {
            UserDefaults.standard.set(true, forKey: accessibilityPromptedKey)
        }

        write([
            "event": "accessibility_permission_check",
            "timestamp": dateFormatter.string(from: now),
            "reason": reason,
            "ax_prompt_previously_shown": hasPrompted,
            "ax_trusted_before_prompt": axTrustedBeforePrompt,
            "ax_prompted": axPrompted,
            "ax_trusted": axTrusted,
            "log_file": logFileURL?.path ?? NSNull()
        ])
    }

    func log(
        urls: [URL],
        currentApplication: SourceApplicationSnapshot?,
        sourceApplication: SourceApplicationSnapshot?,
        sourceWindowTitle: String?,
        rulesBypassedByCommand: Bool = false
    ) {
        let now = Date()
        let axTrustedBeforePrompt = AXIsProcessTrusted()
        let hasPrompted = UserDefaults.standard.bool(forKey: accessibilityPromptedKey)
        let shouldPromptForAccessibility = sourceApplication?.isSlack == true && !axTrustedBeforePrompt && !hasPrompted
        let axPrompted = shouldPromptForAccessibility ? promptForAccessibilityPermission() : false
        let axTrusted = AXIsProcessTrusted()

        if axPrompted {
            UserDefaults.standard.set(true, forKey: accessibilityPromptedKey)
        }

        var event: [String: Any] = [
            "event": "source_detection",
            "timestamp": dateFormatter.string(from: now),
            "url_count": urls.count,
            "url_hosts": urls.map { $0.host ?? "" },
            "url_schemes": urls.map { $0.scheme ?? "" },
            "current_app": currentApplication?.dictionary(relativeTo: now) ?? NSNull(),
            "source_app": sourceApplication?.dictionary(relativeTo: now) ?? NSNull(),
            "source_is_slack": sourceApplication?.isSlack ?? false,
            "source_window_title": sourceWindowTitle ?? NSNull(),
            "rules_bypassed_by_command": rulesBypassedByCommand,
            "ax_prompt_previously_shown": hasPrompted,
            "ax_trusted_before_prompt": axTrustedBeforePrompt,
            "ax_prompted": axPrompted,
            "ax_trusted": axTrusted,
            "log_file": logFileURL?.path ?? NSNull()
        ]

        if let sourceApplication, sourceApplication.isSlack {
            event["slack_ax"] = SlackAccessibilityProbe.probe(
                processIdentifier: sourceApplication.processIdentifier,
                isTrusted: axTrusted
            )
        }

        write(event)
    }

    private func promptForAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return true
    }

    private func write(_ event: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let jsonLine = String(data: data, encoding: .utf8)
        else {
            logger.error("Failed to encode source detection event")
            return
        }

        logger.notice("\(jsonLine, privacy: .public)")
        appendToLogFile(jsonLine)
    }

    private func appendToLogFile(_ jsonLine: String) {
        guard let logFileURL else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            guard let data = "\(jsonLine)\n".data(using: .utf8) else {
                return
            }

            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }

            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
            try fileHandle.close()
        } catch {
            logger.error("Failed to write source detection log file: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private enum SlackAccessibilityProbe {
    static func windowTitle(processIdentifier: pid_t) -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        return windowTitle(appElement, kAXFocusedWindowAttribute)
            ?? windowTitle(appElement, kAXMainWindowAttribute)
    }

    static func probe(processIdentifier: pid_t, isTrusted: Bool) -> [String: Any] {
        guard isTrusted else {
            return ["status": "not_trusted"]
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var result: [String: Any] = [
            "status": "trusted",
            "app_title": attributeDictionary(appElement, kAXTitleAttribute),
            "app_role": attributeDictionary(appElement, kAXRoleAttribute),
            "focused_window": elementAttributeDictionary(appElement, kAXFocusedWindowAttribute),
            "main_window": elementAttributeDictionary(appElement, kAXMainWindowAttribute),
            "focused_element": elementAttributeDictionary(appElement, kAXFocusedUIElementAttribute)
        ]

        result["windows"] = windowDictionaries(appElement)
        return result
    }

    private static func windowDictionaries(_ appElement: AXUIElement) -> [[String: Any]] {
        let value = attributeValue(appElement, kAXWindowsAttribute)
        guard value.error == .success,
              let windows = value.value as? [AXUIElement]
        else {
            return [["error": String(describing: value.error)]]
        }

        return windows.prefix(10).map { elementSummary($0) }
    }

    private static func windowTitle(_ appElement: AXUIElement, _ attribute: String) -> String? {
        let windowValue = attributeValue(appElement, attribute)
        guard windowValue.error == .success,
              let elementValue = windowValue.value,
              CFGetTypeID(elementValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let titleValue = attributeValue(elementValue as! AXUIElement, kAXTitleAttribute)
        guard titleValue.error == .success,
              let title = titleValue.value
        else {
            return nil
        }

        return String(describing: title)
    }

    private static func elementAttributeDictionary(_ element: AXUIElement, _ attribute: String) -> [String: Any] {
        let value = attributeValue(element, attribute)

        guard value.error == .success,
              let elementValue = value.value,
              CFGetTypeID(elementValue) == AXUIElementGetTypeID()
        else {
            return ["error": String(describing: value.error)]
        }

        let element = elementValue as! AXUIElement
        return elementSummary(element)
    }

    private static func elementSummary(_ element: AXUIElement) -> [String: Any] {
        [
            "role": attributeDictionary(element, kAXRoleAttribute),
            "subrole": attributeDictionary(element, kAXSubroleAttribute),
            "title": attributeDictionary(element, kAXTitleAttribute),
            "value": attributeDictionary(element, kAXValueAttribute),
            "description": attributeDictionary(element, kAXDescriptionAttribute)
        ]
    }

    private static func attributeDictionary(_ element: AXUIElement, _ attribute: String) -> [String: Any] {
        let value = attributeValue(element, attribute)
        return [
            "error": String(describing: value.error),
            "value": value.value.map(stringValue) ?? NSNull()
        ]
    }

    private static func attributeValue(_ element: AXUIElement, _ attribute: String) -> (value: AnyObject?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as AnyObject?, error)
    }

    private static func stringValue(_ value: AnyObject) -> String {
        let description = String(describing: value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if description.count <= 300 {
            return description
        }

        return "\(description.prefix(300))..."
    }
}
