//
//  BrowserinoApp.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI
import Foundation
import ApplicationServices
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var selectorWindow: BrowserinoWindow?
    /// Built at launch and kept between links: building the picker's views was most of the time it took to appear.
    private var promptView: NSHostingView<PromptView>?
    private var promptOpenCount = 0
    private var preferencesWindow: NSWindow?
    private var lastSourceApplication: SourceApplicationSnapshot?
    
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("prompt_centerOnScreen") private var centerOnScreen: Bool = false
    @AppStorage("prompt_animation") private var pickerAnimation: PickerAnimation = .none
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    
    var statusMenu: NSMenu!
    let updates = Updates()
    var statusBarItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Unit tests run inside the app; skip the setup that changes settings or shows permission prompts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        BrowserinoImport.importIfNeeded()
        ChromiumProfileUtil.refreshArcProfilesIfNeeded($arcProfiles, shortcuts: $shortcuts)
        AccessibilityPermission.promptIfNeeded(rules: rules)
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

        // A link that launched the app has already built the picker.
        DispatchQueue.main.async {
            if self.promptView == nil {
                _ = self.preparePicker(urls: []).fittingSize
                DispatchQueue.global(qos: .utility).async {
                    malloc_zone_pressure_relief(nil, 0)
                }
            }
        }
        if pickerAnimation.effect != nil {
            PickerEffectRenderer.prewarm()
        }
        // After launch work, so a link that launched the app reaches the picker first.
        DispatchQueue.main.async {
            self.updates.start()
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // While an update waits, the Dock icon is there for it.
        if updates.updater.sessionInProgress {
            updates.controller.checkForUpdates(nil)
        } else {
            self.openPreferences()
        }
        return true
    }
    
    func setupStatusBar() {
        if showInMenuBar {
            if statusBarItem == nil {
                statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let statusButton = statusBarItem!.button
                statusButton!.image = NSImage.menuIcon
                
                let preferences = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: "")
                let checkForUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
                checkForUpdates.target = updates.controller
                let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
                
                statusMenu = NSMenu()
                
                statusMenu!.addItem(preferences)
                statusMenu!.addItem(checkForUpdates)
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
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.miniaturizable, .closable, .resizable, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            preferencesWindow!.toolbarStyle = .unified
            // A closed Settings window would keep its whole view tree in memory; it's rebuilt on every open anyway.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: preferencesWindow, queue: .main) { notification in
                guard let window = notification.object as? NSWindow else {
                    return
                }
                DispatchQueue.main.async {
                    if !window.isVisible {
                        window.contentView = nil
                        DispatchQueue.global(qos: .utility).async {
                            malloc_zone_pressure_relief(nil, 0)
                        }
                    }
                }
            }
        }
        
        preferencesWindow!.center()
        preferencesWindow!.title = "Settings"
        let settingsView = NSHostingView(rootView: PreferencesView().environment(\.updateSettings, updates.settings).environment(\.previewPicker) { [weak self] in
            self?.previewPicker()
        })
        // The default sizing rewrites the window's min and max size on every pane switch, so the window would jump.
        settingsView.sizingOptions = [.minSize]
        preferencesWindow!.contentView = settingsView
        
        preferencesWindow!.isReleasedWhenClosed = false
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
        
        showPicker(urls: processedUrls, isPreview: false)
    }

    /// Opens the picker with a sample link, without rules, so Settings can preview the animation.
    private func previewPicker() {
        showPicker(urls: [URL(string: "https://github.com/jravolio/linkyard")!], isPreview: true)
    }

    private func showPicker(urls: [URL], isPreview: Bool) {
        let animation = pickerAnimation.resolved
        let promptView = preparePicker(urls: urls, isPreview: isPreview, showsGlow: animation == .glow && selectorWindow?.isVisible != true)
        selectorWindow!.setFrame(NSRect(origin: selectorWindow!.frame.origin, size: promptView.fittingSize), display: false)

        let screen = Self.pickerArea(
            at: NSEvent.mouseLocation,
            screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) },
            mainVisibleFrame: NSScreen.main?.visibleFrame
        ) ?? selectorWindow!.frame
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
        
        selectorWindow!.orderFront(animation: animation)
        // When a link launches the app, the rest of launch runs before the next frame; draw the picker first.
        CATransaction.flush()
    }

    private func preparePicker(urls: [URL], isPreview: Bool = false, showsGlow: Bool = false) -> NSHostingView<PromptView> {
        promptOpenCount += 1
        let rootView = PromptView(urls: urls, openID: promptOpenCount, showsGlow: showsGlow) { [weak self] open in
            // Closed first: the browser takes a moment to come forward, and Arc's AppleScript blocks the main thread.
            self?.selectorWindow?.close()
            CATransaction.flush()
            if !isPreview {
                open()
            }
        }
        if let promptView {
            promptView.rootView = rootView
            return promptView
        }

        let window = BrowserinoWindow()
        window.isReleasedWhenClosed = false
        window.delegate = self
        let view = NSHostingView(rootView: rootView)
        if #available(macOS 14.0, *) {
            view.safeAreaRegions = []
        }
        window.setPicker(view)
        selectorWindow = window
        promptView = view
        return view
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
            selectorWindow!.close()
        }
    }

    /// The visible frame of the screen under the pointer. While displays are connected or disconnected, the pointer
    /// can be outside every screen AppKit knows about.
    static func pickerArea(
        at pointer: NSPoint,
        screens: [(frame: NSRect, visibleFrame: NSRect)],
        mainVisibleFrame: NSRect?
    ) -> NSRect? {
        screens.first { NSMouseInRect(pointer, $0.frame, false) }?.visibleFrame ?? mainVisibleFrame ?? screens.first?.visibleFrame
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
