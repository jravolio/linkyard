//
//  BrowserinoApp.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI
import Foundation
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var selectorWindow: BrowserinoWindow?
    private var preferencesWindow: NSWindow?
    private var lastSourceApplication: SourceApplicationSnapshot?
    
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("prompt_centerOnScreen") private var centerOnScreen: Bool = false
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    
    var statusMenu: NSMenu!
    var statusBarItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Unit tests run inside the app; skip the setup that changes settings or shows permission prompts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        importBrowserinoSettingsIfNeeded()
        ChromiumProfileUtil.refreshArcProfilesIfNeeded(&arcProfiles, shortcuts: &shortcuts)
        AccessibilityPermission.promptIfNeeded()
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

    /// A new bundle ID starts with empty settings; the Accessibility prompt flag isn't copied since Linkyard needs its own grant.
    private func importBrowserinoSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "browsers") == nil,
              let browserino = defaults.persistentDomain(forName: "xyz.alexstrnik.Browserino")
        else {
            return
        }

        for (key, value) in browserino where !key.hasPrefix("NS") && key != "sourceDetectionAccessibilityPrompted" {
            defaults.set(value, forKey: key)
        }
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
            
            if url.scheme == "linkyard" && url.host == "open" {
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

        if processedUrls.count == 1 && !shouldBypassRules {
            let urlString = processedUrls.first!.absoluteString

            for rule in rules {
                if rule.matches(urlString, sourceBundleID: sourceContext.application?.bundleIdentifier, windowTitle: { sourceContext.windowTitle }) {
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
        
        let promptView = NSHostingView(
            rootView: PromptView(
                urls: processedUrls
            )
        )
        if #available(macOS 14.0, *) {
            promptView.safeAreaRegions = []
        }
        selectorWindow!.contentView = promptView
        selectorWindow!.setFrame(NSRect(origin: selectorWindow!.frame.origin, size: promptView.fittingSize), display: false)

        let screen = getScreenWithMouse()!.visibleFrame
        let size = selectorWindow!.frame.size

        selectorWindow?.setFrameOrigin(
            centerOnScreen
                ? NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
                : NSPoint(
                    x: clamp(
                        min: screen.minX + 20,
                        max: screen.maxX - size.width - 20,
                        value: NSEvent.mouseLocation.x - size.width / 2
                    ),
                    y: clamp(
                        min: screen.minY + 20,
                        max: screen.maxY - size.height - 20,
                        value: NSEvent.mouseLocation.y - (size.height - 30)
                    )
                )
        )
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        selectorWindow!.deactivateDelay()
        
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

    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        
        return screenWithMouse
    }
}

struct SourceApplicationSnapshot {
    let bundleIdentifier: String?
    let processIdentifier: pid_t

    init(application: NSRunningApplication) {
        self.bundleIdentifier = application.bundleIdentifier
        self.processIdentifier = application.processIdentifier
    }
}

/// Reading the title makes blocking Accessibility calls into the source app, so only rules that check it pay for it.
final class SourceRuleContext {
    let application: SourceApplicationSnapshot?
    private let readTitle: (pid_t) -> String?

    lazy var windowTitle: String? = application.flatMap { readTitle($0.processIdentifier) }

    init(application: SourceApplicationSnapshot?, readTitle: @escaping (pid_t) -> String? = WindowTitleProbe.windowTitle) {
        self.application = application
        self.readTitle = readTitle
    }
}

private enum AccessibilityPermission {
    private static let promptedKey = "sourceDetectionAccessibilityPrompted"

    static func promptIfNeeded() {
        guard !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: promptedKey) else {
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(true, forKey: promptedKey)
    }
}

private enum WindowTitleProbe {
    static func windowTitle(processIdentifier: pid_t) -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        return windowTitle(appElement, kAXFocusedWindowAttribute)
            ?? windowTitle(appElement, kAXMainWindowAttribute)
    }

    private static func windowTitle(_ appElement: AXUIElement, _ attribute: String) -> String? {
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &window) == .success,
              let window,
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else {
            return nil
        }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let title
        else {
            return nil
        }

        return String(describing: title)
    }
}
