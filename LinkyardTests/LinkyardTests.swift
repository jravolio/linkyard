import Metal
import XCTest
@testable import Linkyard

final class ProfileMergeTests: XCTestCase {
    private let chrome = ChromiumProfileUtil.chromeSource
    private let arc = ChromiumProfileUtil.arcSource

    func testKeepsTheUsersNameVisibilityAndLogoForAProfileThatIsStillThere() {
        let stored = ChromeProfile(directoryName: "Profile 1", displayName: "Work", isHidden: true, iconPath: "/logos/work.png")
        let detected = ChromeProfile(directoryName: "Profile 1", displayName: "Person 2")

        let merged = ChromiumProfileUtil.mergeProfiles(existing: [stored], detected: [detected], source: chrome)

        XCTAssertEqual(merged, [ChromeProfile(directoryName: "Profile 1", displayName: "Work", isHidden: true, iconPath: "/logos/work.png")])
    }

    func testDropsProfilesThatAreGoneAndAddsNewOnes() {
        let stored = [ChromeProfile(directoryName: "Profile 9", displayName: "Old")]
        let detected = [ChromeProfile(directoryName: "Default", displayName: "Personal")]

        XCTAssertEqual(ChromiumProfileUtil.mergeProfiles(existing: stored, detected: detected, source: chrome), detected)
    }

    func testAnArcSpaceStoredUnderItsFolderTakesTheDetectedNameButKeepsItsSettings() {
        let stored = ChromeProfile(directoryName: "Profile 1", displayName: "Old name", isHidden: true, iconPath: "/logos/work.png")
        let detected = ChromeProfile(directoryName: "Profile 1", displayName: "Work", arcSpaceID: "SPACE-WORK")

        let merged = ChromiumProfileUtil.mergeProfiles(existing: [stored], detected: [detected], source: arc)

        XCTAssertEqual(merged, [ChromeProfile(directoryName: "Profile 1", displayName: "Work", isHidden: true, arcSpaceID: "SPACE-WORK", iconPath: "/logos/work.png")])
    }

    func testShortcutsSavedUnderAnArcFolderMoveToTheSpaceID() {
        let profiles = [ChromeProfile(directoryName: "Profile 1", displayName: "Work", arcSpaceID: "SPACE-WORK")]
        let bundle = ChromiumProfileUtil.arcBundleID

        let migrated = ChromiumProfileUtil.migrateShortcuts(["\(bundle)::Profile 1": "w"], for: arc, profiles: profiles)

        XCTAssertEqual(migrated, ["\(bundle)::SPACE-WORK": "w"])
    }

    func testAShortcutAlreadyOnTheSpaceIDIsNotOverwritten() {
        let profiles = [ChromeProfile(directoryName: "Profile 1", displayName: "Work", arcSpaceID: "SPACE-WORK")]
        let bundle = ChromiumProfileUtil.arcBundleID
        let shortcuts = ["\(bundle)::Profile 1": "w", "\(bundle)::SPACE-WORK": "k"]

        XCTAssertEqual(ChromiumProfileUtil.migrateShortcuts(shortcuts, for: arc, profiles: profiles), shortcuts)
    }
}

final class ArcSidebarTests: XCTestCase {
    func testReadsSpacesWithTheirProfileFolderInSidebarOrder() throws {
        let sidebar = """
        {"sidebar":{"containers":[{"global":{}},{"spaces":[
         {"id":"WORK","title":"Work","profile":{"custom":{"_0":{"directoryBasename":"Profile 1"}}},"containerIDs":[]},
         {"id":"HOME","title":"Personal","profile":{"default":true},"containerIDs":[]},
         "WORK"
        ],"orderedSpaceIDs":["HOME","WORK"]}]}}
        """
        let json = try JSONSerialization.jsonObject(with: Data(sidebar.utf8))

        XCTAssertEqual(ChromiumProfileUtil.arcSpaces(fromSidebar: json), [
            ChromeProfile(directoryName: "Default", displayName: "Personal", arcSpaceID: "HOME"),
            ChromeProfile(directoryName: "Profile 1", displayName: "Work", arcSpaceID: "WORK"),
        ])
    }
}

final class BrowserLinkTests: XCTestCase {
    func testZenContainerLinksDecodeBackToTheContainerAndURL() throws {
        let link = try XCTUnwrap(URL(string: "https://example.com/a+b?q=1&r=two%20words#top"))

        let url = try XCTUnwrap(BrowserUtil.zenContainerURL(for: link, container: "Side Project"))
        XCTAssertTrue(url.absoluteString.hasPrefix("ext+container:"))

        let query = String(url.absoluteString.dropFirst("ext+container:".count))
        let items = try XCTUnwrap(URLComponents(string: "?\(query)")?.queryItems)
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Side Project")
        XCTAssertEqual(items.first { $0.name == "url" }?.value, link.absoluteString)
    }

    func testAppleScriptStringsEscapeQuotesAndBackslashes() {
        XCTAssertEqual(BrowserUtil.escapeAppleScriptString(#"say "hi" \ bye"#), #"say \"hi\" \\ bye"#)
    }
}

final class PickerLayoutTests: XCTestCase {
    private func item(_ id: String, app: String, group: String?, icon: String? = nil) -> PickerBrowserItem {
        PickerBrowserItem(id: id, appURL: URL(fileURLWithPath: "/Nonexistent/\(app).app"), displayName: id, profileDirectory: nil, shortcutKey: nil, iconPath: icon, group: group)
    }

    func testGroupsFollowTheConfiguredOrderThenFirstAppearanceWithUngroupedLast() {
        let items = [
            item("plain", app: "Safari", group: nil),
            item("dia-work", app: "Dia", group: "Work"),
            item("dia-home", app: "Dia", group: "Personal"),
            item("zen-side", app: "Zen", group: "Side Project"),
            item("zen-work", app: "Zen", group: "work"),
        ]

        let ordered = PickerLayout.grouped(items, order: ["Personal"]).map(\.id)

        XCTAssertEqual(ordered, ["dia-home", "dia-work", "zen-work", "zen-side", "plain"])
    }

    func testOneRowPerIdentityWithEachBrowserInItsColumn() {
        let items = [
            item("dia-work", app: "Dia", group: "Work"),
            item("zen-work", app: "Zen", group: "Work ", icon: "/logos/work.png"),
            item("zen-work-2", app: "Zen", group: "Work"),
        ]

        let rows = PickerLayout.identityRows(from: items, order: [])

        XCTAssertEqual(rows.count, 2, "a second Zen profile in the same group gets its own row")
        XCTAssertEqual(Set(rows[0].cells.values.map(\.id)), ["dia-work", "zen-work"])
        XCTAssertEqual(rows[0].iconPath, "/logos/work.png")
        XCTAssertEqual(rows[1].cells.values.map(\.id), ["zen-work-2"])
    }

    func testNoProfilesMeansNoRowsAndNoSelection() {
        let empty = PickerRow(id: "app::0", title: "Zoom", iconPath: nil, iconAppURL: URL(fileURLWithPath: "/Nonexistent/zoom.us.app"))

        XCTAssertTrue(PickerLayout.identityRows(from: [], order: ["Personal"]).isEmpty)
        XCTAssertNil(PickerLayout.resolvedColumn(in: empty, columns: [], preferring: "anything"))
    }

    func testShortcutsCoverAppRowsAndBrowserCells() {
        let dia = PickerBrowserItem(id: "dia-work", appURL: URL(fileURLWithPath: "/Nonexistent/Dia.app"), displayName: nil, profileDirectory: "Work", shortcutKey: "W")
        let zen = PickerBrowserItem(id: "zen-work", appURL: URL(fileURLWithPath: "/Nonexistent/Zen.app"), displayName: nil, profileDirectory: "Work", shortcutKey: nil)
        let columns = [dia, zen].map(PickerLayout.bundleID)
        let rows = [
            PickerRow(id: "app::0", title: "Zoom", iconPath: nil, iconAppURL: URL(fileURLWithPath: "/Nonexistent/zoom.us.app"), shortcutKey: "Z"),
            PickerRow(id: "work", title: "Work", iconPath: nil, iconAppURL: dia.appURL, cells: [columns[0]: dia, columns[1]: zen]),
        ]

        XCTAssertEqual(PickerLayout.shortcuts(for: rows, columns: columns), [
            PickerLayout.Shortcut(key: "z", row: 0, column: nil),
            PickerLayout.Shortcut(key: "w", row: 1, column: columns[0]),
        ])
    }

    func testTheSelectedColumnFallsBackToTheNearestBrowserTheRowHas() {
        let dia = item("dia", app: "Dia", group: "Work")
        let chrome = item("chrome", app: "Chrome", group: "Work")
        let columns = [dia, item("zen", app: "Zen", group: nil), item("arc", app: "Arc", group: nil), chrome].map(PickerLayout.bundleID)
        let row = PickerRow(id: "work", title: "Work", iconPath: nil, iconAppURL: dia.appURL, cells: [
            columns[0]: dia,
            columns[3]: chrome,
        ])

        XCTAssertEqual(PickerLayout.resolvedColumn(in: row, columns: columns, preferring: nil), columns[0])
        XCTAssertEqual(PickerLayout.resolvedColumn(in: row, columns: columns, preferring: columns[3]), columns[3])
        XCTAssertEqual(PickerLayout.resolvedColumn(in: row, columns: columns, preferring: columns[1]), columns[0])
        XCTAssertEqual(PickerLayout.resolvedColumn(in: row, columns: columns, preferring: columns[2]), columns[3])
    }
}

final class RuleMatchingTests: XCTestCase {
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private let browser = URL(fileURLWithPath: "/Applications/Safari.app")

    func testMatchesTheURLPatternIgnoringCase() {
        let rule = Rule(regex: "github\\.com/acme/", app: browser)

        XCTAssertTrue(rule.matches("https://GitHub.com/acme/site", sourceBundleID: nil, windowTitle: { nil }))
        XCTAssertFalse(rule.matches("https://github.com/other/site", sourceBundleID: nil, windowTitle: { nil }))
    }

    func testOnlyMatchesLinksFromTheRulesSourceApp() {
        let rule = Rule(regex: ".*", app: browser, sourceApp: textEdit)

        XCTAssertTrue(rule.matches("https://example.com", sourceBundleID: "com.apple.TextEdit", windowTitle: { nil }))
        XCTAssertFalse(rule.matches("https://example.com", sourceBundleID: "com.tinyspeck.slackmacgap", windowTitle: { nil }))
    }

    func testChecksTheWindowTitleOnlyWhenTheRuleHasATitlePattern() {
        var titleReads = 0
        let readTitle = { () -> String? in
            titleReads += 1
            return "Acme - Slack"
        }

        XCTAssertTrue(Rule(regex: ".*", app: browser).matches("https://example.com", sourceBundleID: nil, windowTitle: readTitle))
        XCTAssertEqual(titleReads, 0)

        XCTAssertTrue(Rule(regex: ".*", app: browser, sourceWindowTitleRegex: "acme").matches("https://example.com", sourceBundleID: nil, windowTitle: readTitle))
        XCTAssertFalse(Rule(regex: ".*", app: browser, sourceWindowTitleRegex: "Northwind").matches("https://example.com", sourceBundleID: nil, windowTitle: readTitle))
        XCTAssertEqual(titleReads, 2)
    }

    func testAnInvalidPatternNeverMatches() {
        XCTAssertFalse(Rule(regex: "(", app: browser).matches("https://example.com", sourceBundleID: nil, windowTitle: { nil }))
    }
}

final class SourceRuleContextTests: XCTestCase {
    func testReadsTheWindowTitleOfAnySourceAppNotJustSlack() {
        let teams = SourceApplicationSnapshot(application: NSRunningApplication.current)
        let context = SourceRuleContext(application: teams, readTitle: { _ in "Acme | Microsoft Teams" })

        XCTAssertEqual(context.windowTitle, "Acme | Microsoft Teams")
    }
}

final class AppIconCacheTests: XCTestCase {
    private let calculator = "/System/Applications/Calculator.app"

    func testRendersTheIconAtTheDisplaysPixelSize() throws {
        let retina = AppIconCache.icon(forApp: calculator, size: 24, scale: 2, colorScheme: .dark)
        let standard = AppIconCache.icon(forApp: calculator, size: 24, scale: 1, colorScheme: .dark)

        XCTAssertEqual(retina.size, NSSize(width: 24, height: 24))
        XCTAssertEqual(try XCTUnwrap(retina.cgImage(forProposedRect: nil, context: nil, hints: nil)).width, 48)
        XCTAssertEqual(try XCTUnwrap(standard.cgImage(forProposedRect: nil, context: nil, hints: nil)).width, 24)
    }

    func testReusesTheRenderedIconUntilTheSizeScaleOrAppearanceChanges() {
        let icon = AppIconCache.icon(forApp: calculator, size: 32, scale: 2, colorScheme: .light)

        XCTAssertTrue(icon === AppIconCache.icon(forApp: calculator, size: 32, scale: 2, colorScheme: .light))
        XCTAssertFalse(icon === AppIconCache.icon(forApp: calculator, size: 32, scale: 2, colorScheme: .dark))
        XCTAssertFalse(icon === AppIconCache.icon(forApp: calculator, size: 36, scale: 2, colorScheme: .light))
    }
}

final class AppleEventsTests: XCTestCase {
    func testFourCharacterCodes() {
        XCTAssertEqual(AppleEvents.code("DiaP"), 0x4469_6150)
        XCTAssertEqual(AppleEvents.code("end "), 0x656E_6420)
    }

    func testFirstProfileWhoseNameIsMatchesWhatAppleScriptSends() throws {
        let window = AppleEvents.element("cwin", at: 1)
        let profile = AppleEvents.named("DiaP", "Work", of: window)

        XCTAssertEqual(profile.descriptorType, AppleEvents.code("obj "))
        let first = try XCTUnwrap(profile.coerce(toDescriptorType: AppleEvents.code("reco")))
        XCTAssertEqual(first.forKeyword(AppleEvents.code("want"))?.typeCodeValue, AppleEvents.code("DiaP"))
        XCTAssertEqual(first.forKeyword(AppleEvents.code("form"))?.enumCodeValue, AppleEvents.code("indx"))
        XCTAssertEqual(first.forKeyword(AppleEvents.code("seld"))?.int32Value, 1)

        let matching = try XCTUnwrap(first.forKeyword(AppleEvents.code("from"))?.coerce(toDescriptorType: AppleEvents.code("reco")))
        XCTAssertEqual(matching.forKeyword(AppleEvents.code("form"))?.enumCodeValue, AppleEvents.code("test"))
        let test = try XCTUnwrap(matching.forKeyword(AppleEvents.code("seld"))?.coerce(toDescriptorType: AppleEvents.code("reco")))
        XCTAssertEqual(test.forKeyword(AppleEvents.code("relo"))?.enumCodeValue, AppleEvents.code("=   "))
        XCTAssertEqual(test.forKeyword(AppleEvents.code("obj2"))?.stringValue, "Work")
    }

    func testAnAppThatIsNotRunningIsAnError() {
        XCTAssertThrowsError(try AppleEvents.send("misc", "actv", to: "io.github.jravolio.linkyard-tests.not-running"))
    }
}

final class SettingsSearchTests: XCTestCase {
    private let dia = URL(fileURLWithPath: "/Applications/Dia.app")
    private let slack = URL(fileURLWithPath: "/Applications/Slack.app")

    private var index: [SettingsSearchItem] {
        SettingsSearch.index(
            browsers: [],
            profiles: [(ChromiumProfileUtil.diaSource, [ChromeProfile(directoryName: "Work", displayName: "Work")])],
            rules: [Rule(regex: ".*", app: dia, profileDirectory: "Work", sourceApp: slack, sourceWindowTitleRegex: "Acme")],
            apps: [App(host: "figma.com", schemeOverride: "", app: URL(fileURLWithPath: "/Applications/Figma.app"))]
        )
    }

    func testFindsSettingsByTitleAndKeywords() {
        XCTAssertEqual(SettingsSearch.results(for: "login", in: index).first?.id, "general.launchAtLogin")
        XCTAssertTrue(SettingsSearch.results(for: "incognito", in: index).contains { $0.id == "browsers.private" })
        XCTAssertTrue(SettingsSearch.results(for: "glow", in: index).contains { $0.id == "picker.animation" })
    }

    func testFindsWhatTheUserSetUp() {
        let work = SettingsSearch.results(for: "work", in: index)
        XCTAssertTrue(work.contains { $0.id == "profile.\(ChromiumProfileUtil.diaBundleID)::Work" })
        XCTAssertTrue(work.contains { $0.id == "rule.0" })
        XCTAssertEqual(SettingsSearch.results(for: "figma", in: index).first?.id, "app.0")
        XCTAssertTrue(SettingsSearch.results(for: "acme", in: index).contains { $0.id == "rule.0" })
    }

    func testEveryWordMustMatchAndCaseDoesNotMatter() {
        XCTAssertTrue(SettingsSearch.results(for: "SLACK work", in: index).contains { $0.id == "rule.0" })
        XCTAssertTrue(SettingsSearch.results(for: "slack nothing", in: index).isEmpty)
        XCTAssertTrue(SettingsSearch.results(for: "   ", in: index).isEmpty)
    }

    func testTitleMatchesComeFirst() {
        let results = SettingsSearch.results(for: "browser", in: index)
        let firstTitleMiss = results.firstIndex { !$0.title.localizedStandardContains("browser") } ?? results.count
        XCTAssertFalse(results[firstTitleMiss...].contains { $0.title.localizedStandardContains("browser") })
    }
}

final class PickerAnimationTests: XCTestCase {
    func testZoomGrowsFrom95PercentToFullSizeWithoutOvershoot() throws {
        XCTAssertEqual(try XCTUnwrap(BrowserinoWindow.zoomScale(at: 0)), 0.95, accuracy: 0.0001)

        let samples = stride(from: 0.0, to: BrowserinoWindow.zoomDuration, by: 0.005).compactMap(BrowserinoWindow.zoomScale)
        XCTAssertEqual(samples, samples.sorted())
        XCTAssertLessThanOrEqual(samples.max()!, 1)
        XCTAssertEqual(samples.last!, 1, accuracy: 0.001)
        XCTAssertNil(BrowserinoWindow.zoomScale(at: BrowserinoWindow.zoomDuration))
    }
}

/// The live picker replaces an effect when it ends, so every effect has to start with nothing drawn and end on the picker exactly.
final class PickerEffectTests: XCTestCase {
    /// Pixel sizes on a 2x screen, from PromptView's width (268 pt plus 36 per browser) and its row and list heights.
    private let sizes: [(width: Int, height: Int)] = [(824, 212), (968, 212), (824, 576), (608, 1200)]

    /// Detail down to single pixels, opaque and translucent content, and transparent areas where the blur shows.
    private func snapshot(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where (x / 40 + y / 40) % 3 != 0 {
                let i = (y * width + x) * 4
                let alpha: UInt8 = (x / 40) % 2 == 0 ? 255 : 128
                let bright = (x + y) % 2 == 0
                pixels[i] = bright ? alpha : alpha / 5
                pixels[i + 1] = bright ? alpha : UInt8(Int(alpha) * 2 / 5)
                pixels[i + 2] = bright ? alpha / 2 : alpha
                pixels[i + 3] = alpha
            }
        }
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func render(_ renderer: PickerEffectRenderer, _ snapshot: MTLTexture, mode: Int32, raw: Double) throws -> (overlay: [UInt8], mask: [UInt8]) {
        let width = snapshot.width, height = snapshot.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = renderer.device.hasUnifiedMemory ? .shared : .managed
        let overlay = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        let mask = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        let uniforms = EffectUniforms(size: SIMD2(Float(width), Float(height)), raw: Float(raw), duration: 0.6, radius: 0, scale: 2, dark: 1, mode: mode)
        try XCTUnwrap(renderer.draw(uniforms, snapshot: snapshot, overlay: overlay, mask: mask)).waitUntilCompleted()
        if !renderer.device.hasUnifiedMemory {
            let buffer = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
            let blit = try XCTUnwrap(buffer.makeBlitCommandEncoder())
            [overlay, mask].forEach { blit.synchronize(resource: $0) }
            blit.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
        }

        func bytes(_ texture: MTLTexture) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return bytes
        }
        return (bytes(overlay), bytes(mask))
    }

    private func largestDifference(bgra: [UInt8], rgba: [UInt8]) -> Int {
        var largest = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            largest = max(largest, abs(Int(bgra[i + 2]) - Int(rgba[i])), abs(Int(bgra[i + 1]) - Int(rgba[i + 1])),
                          abs(Int(bgra[i]) - Int(rgba[i + 2])), abs(Int(bgra[i + 3]) - Int(rgba[i + 3])))
        }
        return largest
    }

    private func alphas(_ pixels: [UInt8]) -> [UInt8] {
        stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    func testEveryEffectStartsHiddenAndEndsOnThePicker() throws {
        guard let renderer = PickerEffectRenderer.shared else {
            throw XCTSkip("No Metal device")
        }

        for size in sizes {
            let image = snapshot(width: size.width, height: size.height)
            let snapshot = try XCTUnwrap(renderer.texture(from: image))
            let expected = Array(UnsafeBufferPointer(start: CFDataGetBytePtr(image.dataProvider!.data!), count: size.width * size.height * 4))

            for effect in PickerAnimation.effects {
                let mode = try XCTUnwrap(effect.effect).mode
                let label = "\(effect) at \(size.width)x\(size.height)"
                let start = try render(renderer, snapshot, mode: mode, raw: 0)
                XCTAssertLessThanOrEqual(alphas(start.overlay).max()!, 3, "\(label) draws at its first frame")
                XCTAssertLessThanOrEqual(alphas(start.mask).max()!, 2, "\(label) shows the background at its first frame")

                let end = try render(renderer, snapshot, mode: mode, raw: 1)
                XCTAssertGreaterThanOrEqual(alphas(end.mask).min()!, 253, "\(label) leaves background hidden at its end")
                XCTAssertLessThanOrEqual(largestDifference(bgra: end.overlay, rgba: expected), 2, "\(label) doesn't end on the picker")
            }
        }
    }

    func testEffectsUseDistinctShaderModes() {
        let modes = PickerAnimation.effects.compactMap { $0.effect?.mode }
        XCTAssertEqual(modes.sorted(), Array(0..<Int32(PickerAnimation.effects.count)))
    }
}

/// While an effect plays the picker is hidden behind it, so every way the effect ends has to put the picker back.
final class PickerEffectHandoffTests: XCTestCase {
    private var window: BrowserinoWindow!
    private var picker: NSView!
    private var background: NSColor!

    override func setUpWithError() throws {
        try XCTSkipIf(PickerEffectRenderer.shared == nil, "No Metal device")
        window = BrowserinoWindow()
        window.isReleasedWhenClosed = false
        picker = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.setPicker(picker)
        window.setFrame(NSRect(x: 200, y: 200, width: 300, height: 200), display: false)
        background = window.backgroundColor
    }

    override func tearDown() {
        window?.close()
    }

    private func assertPickerIsBack(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(picker.alphaValue, 1, file: file, line: line)
        XCTAssertTrue(window.hasShadow, file: file, line: line)
        XCTAssertEqual(window.backgroundColor, background, file: file, line: line)
        XCTAssertFalse(window.contentView!.subviews.contains { $0 is PickerEffectView }, file: file, line: line)
    }

    func testThePickerIsHiddenWhileAnEffectPlays() {
        window.orderFront(animation: .ink)
        XCTAssertEqual(picker.alphaValue, 0)
        XCTAssertFalse(window.hasShadow)
        XCTAssertTrue(window.contentView!.subviews.contains { $0 is PickerEffectView })
    }

    func testClosingDuringAnEffectPutsThePickerBack() {
        window.orderFront(animation: .ink)
        window.close()
        assertPickerIsBack()
    }

    func testAKeyPressEndsTheEffect() throws {
        window.orderFront(animation: .restore)
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        window.sendEvent(key)
        assertPickerIsBack()
    }

    func testTheEffectEndsOnItsOwn() throws {
        window.orderFront(animation: .materialize)
        RunLoop.main.run(until: Date().addingTimeInterval(try XCTUnwrap(PickerAnimation.materialize.effect).duration + 0.2))
        assertPickerIsBack()
    }

    func testAnotherLinkDuringAnEffectShowsThePicker() {
        window.orderFront(animation: .thaw)
        window.orderFront(animation: .thaw)
        assertPickerIsBack()
    }
}

/// Releases are ad-hoc signed, so the Accessibility permission doesn't survive an update and has to be asked for again.
final class AccessibilityPromptTests: XCTestCase {
    private let titleRule = Rule(regex: ".*", app: URL(fileURLWithPath: "/Applications/Dia.app"), sourceWindowTitleRegex: "Acme")
    private let plainRule = Rule(regex: ".*", app: URL(fileURLWithPath: "/Applications/Dia.app"), sourceWindowTitleRegex: "  ")

    func testAsksAgainAfterAnUpdate() {
        XCTAssertTrue(AccessibilityPermission.shouldPrompt(rules: [titleRule], promptedVersion: "1.1.0", version: "1.2.0"))
    }

    func testAsksWhenOnlyTheOldYesNoFlagIsStored() {
        XCTAssertTrue(AccessibilityPermission.shouldPrompt(rules: [titleRule], promptedVersion: nil, version: "1.2.0"))
    }

    func testAsksOncePerVersion() {
        XCTAssertFalse(AccessibilityPermission.shouldPrompt(rules: [titleRule], promptedVersion: "1.2.0", version: "1.2.0"))
    }

    func testDoesntAskWithoutAWindowTitleRule() {
        XCTAssertFalse(AccessibilityPermission.shouldPrompt(rules: [plainRule], promptedVersion: nil, version: "1.2.0"))
        XCTAssertFalse(plainRule.readsWindowTitle)
        XCTAssertTrue(titleRule.readsWindowTitle)
    }
}

/// Only the browsers Linkyard drives with Apple Events get a row in Settings → Permissions and a search result.
final class AppleEventsBrowserTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("linkyard-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func app(_ name: String, _ bundleID: String, in subfolder: String = "") throws -> URL {
        let app = folder.appendingPathComponent(subfolder).appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testListsDiaAndArcOnceEachAndSkipsOtherBrowsers() throws {
        let chrome = try app("Google Chrome", ChromiumProfileUtil.chromeBundleID)
        let dia = try app("Dia", ChromiumProfileUtil.diaBundleID)
        let arc = try app("Arc", ChromiumProfileUtil.arcBundleID)
        let secondDia = try app("Dia", ChromiumProfileUtil.diaBundleID, in: "Other")

        let found = ChromiumProfileUtil.appleEventsBrowsers(in: [chrome, dia, arc, secondDia])

        XCTAssertEqual(found.map(\.app), [dia, arc])
        XCTAssertEqual(found.map(\.source.bundleID), [ChromiumProfileUtil.diaBundleID, ChromiumProfileUtil.arcBundleID])
    }

    func testSearchOffersBrowserControlOnlyWhenSuchABrowserIsInstalled() throws {
        let chrome = try app("Google Chrome", ChromiumProfileUtil.chromeBundleID)
        let dia = try app("Dia", ChromiumProfileUtil.diaBundleID)

        let withoutDia = SettingsSearch.index(browsers: [chrome], profiles: [], rules: [], apps: [])
        let withDia = SettingsSearch.index(browsers: [chrome, dia], profiles: [], rules: [], apps: [])

        XCTAssertFalse(withoutDia.contains { $0.pane == .permissions && $0.id.hasPrefix("permissions.automation") })
        XCTAssertEqual(SettingsSearch.results(for: "control dia", in: withDia).first?.pane, .permissions)
    }

    func testEachBrowserControlResultHasItsOwnID() throws {
        let dia = try app("Dia", ChromiumProfileUtil.diaBundleID)
        let arc = try app("Arc", ChromiumProfileUtil.arcBundleID)

        let ids = SettingsSearch.index(browsers: [dia, arc], profiles: [], rules: [], apps: []).map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains("permissions.automation.\(ChromiumProfileUtil.arcBundleID)"))
    }
}

/// Sparkle offers an update only when CFBundleVersion grows, and installs only downloads signed with SUPublicEDKey.
final class UpdateConfigurationTests: XCTestCase {
    private let info = Bundle.main.infoDictionary ?? [:]

    func testTheBuildNumberFollowsTheVersion() {
        XCTAssertEqual(info["CFBundleVersion"] as? String, info["CFBundleShortVersionString"] as? String)
    }

    func testUpdatesComeFromTheLatestGitHubReleaseAndMustBeSigned() {
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://github.com/jravolio/linkyard/releases/latest/download/appcast.xml")
        XCTAssertEqual(Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count, 32)
    }
}

final class ReorderTests: XCTestCase {
    func testDroppingOnARowBelowPutsTheDraggedRowAfterIt() {
        var rules = ["a", "b", "c", "d"]
        rules.move(from: 0, to: 2)
        XCTAssertEqual(rules, ["b", "c", "a", "d"])
    }

    func testDroppingOnARowAbovePutsTheDraggedRowBeforeIt() {
        var rules = ["a", "b", "c", "d"]
        rules.move(from: 3, to: 1)
        XCTAssertEqual(rules, ["a", "d", "b", "c"])
    }

    func testAdjacentRowsSwap() {
        var rules = ["a", "b"]
        rules.move(from: 0, to: 1)
        XCTAssertEqual(rules, ["b", "a"])
        rules.move(from: 1, to: 0)
        XCTAssertEqual(rules, ["a", "b"])
    }
}

final class DiaAppleEventsTests: XCTestCase {
    private let links = [URL(string: "https://example.com/1")!, URL(string: "https://example.com/2")!]

    private func reply(_ windowCount: Int32) -> NSAppleEventDescriptor {
        let reply = NSAppleEventDescriptor.appleEvent(
            withEventClass: AppleEvents.code("aevt"),
            eventID: AppleEvents.code("ansr"),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        reply.setParam(NSAppleEventDescriptor(int32: windowCount), forKeyword: keyDirectObject)
        return reply
    }

    private func name(_ eventID: String, _ parameters: [String: NSAppleEventDescriptor]) -> String {
        guard eventID == "crel" else {
            return eventID
        }
        return parameters["kocl"]?.typeCodeValue == AppleEvents.code("DiaT") ? "tab" : "window"
    }

    func testMakesAWindowFirstWhenDiaHasNone() {
        var events: [String] = []
        var windows: Int32 = 0
        let failed = BrowserUtil.sendDiaURLs(links, profileName: "Work") { _, eventID, parameters, _ in
            let event = name(eventID, parameters)
            events.append(event)
            switch event {
            case "tab" where windows == 0:
                throw NSError(domain: NSOSStatusErrorDomain, code: -1719)
            case "window":
                windows += 1
            case "cnte":
                return reply(windows)
            default:
                break
            }
            return NSAppleEventDescriptor.null()
        }

        XCTAssertEqual(failed, [])
        XCTAssertEqual(events, ["actv", "tab", "cnte", "window", "tab", "tab"])
    }

    func testLinksThatCouldNotOpenAreReturnedWithoutTheOnesThatDid() {
        var tabs = 0
        let failed = BrowserUtil.sendDiaURLs(links, profileName: "Renamed") { _, eventID, parameters, _ in
            switch name(eventID, parameters) {
            case "tab":
                tabs += 1
                if tabs == 2 {
                    throw NSError(domain: NSOSStatusErrorDomain, code: -1719)
                }
            case "cnte":
                return reply(1)
            default:
                break
            }
            return NSAppleEventDescriptor.null()
        }

        XCTAssertEqual(failed, [links[1]])
    }

    func testTabsAreMadeAtTheEndOfTheProfilesTabs() throws {
        let tabs = AppleEvents.every("DiaT", of: AppleEvents.named("DiaP", "Work", of: AppleEvents.element("cwin", at: 1)))
        let location = AppleEvents.end(of: tabs)

        XCTAssertEqual(location.descriptorType, AppleEvents.code("insl"))
        let record = try XCTUnwrap(location.coerce(toDescriptorType: AppleEvents.code("reco")))
        XCTAssertEqual(record.forKeyword(AppleEvents.code("kpos"))?.enumCodeValue, AppleEvents.code("end "))
        XCTAssertEqual(record.forKeyword(AppleEvents.code("kobj"))?.descriptorType, AppleEvents.code("obj "))
    }
}

final class ShortcutRecordingTests: XCTestCase {
    func testEscCancelsAndDeleteClearsInsteadOfBecomingShortcuts() {
        XCTAssertEqual(ShortcutButton.recording(for: "\u{1B}"), .cancel)
        XCTAssertEqual(ShortcutButton.recording(for: "\u{7F}"), .clear)
        XCTAssertEqual(ShortcutButton.recording(for: "\u{8}"), .clear)
        XCTAssertEqual(ShortcutButton.recording(for: "D"), .record("D"))
    }
}

final class PickerPlacementTests: XCTestCase {
    private let laptop = (frame: NSRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950))
    private let monitor = (frame: NSRect(x: 1512, y: 0, width: 2560, height: 1440), visibleFrame: NSRect(x: 1512, y: 0, width: 2560, height: 1415))

    func testUsesTheScreenUnderThePointer() {
        XCTAssertEqual(AppDelegate.pickerArea(at: NSPoint(x: 2000, y: 700), screens: [laptop, monitor], mainVisibleFrame: laptop.visibleFrame), monitor.visibleFrame)
    }

    func testFallsBackWhenThePointerIsOutsideEveryScreen() {
        let outside = NSPoint(x: -500, y: 3000)
        XCTAssertEqual(AppDelegate.pickerArea(at: outside, screens: [laptop, monitor], mainVisibleFrame: monitor.visibleFrame), monitor.visibleFrame)
        XCTAssertEqual(AppDelegate.pickerArea(at: outside, screens: [laptop], mainVisibleFrame: nil), laptop.visibleFrame)
        XCTAssertNil(AppDelegate.pickerArea(at: outside, screens: [], mainVisibleFrame: nil))
    }
}

final class AppIconRefreshTests: XCTestCase {
    func testAnUpdatedAppGetsItsNewIcon() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("linkyard-icon-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("Browser.app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/System/Applications/Calculator.app"), to: app)
        let before = AppIconCache.icon(forApp: app.path, size: 32, scale: 2, colorScheme: .light)

        try FileManager.default.removeItem(at: app)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/System/Applications/Chess.app"), to: app)
        // An updater installs a bundle built later; the copy would keep Chess's date, which matches Calculator's.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        let after = AppIconCache.icon(forApp: app.path, size: 32, scale: 2, colorScheme: .light)

        XCTAssertNotEqual(before.tiffRepresentation, after.tiffRepresentation)
    }
}

/// Sparkle keeps its own state in the app's defaults, next to the settings.
final class SettingsBackupTests: XCTestCase {
    private let suite = "linkyard-tests-\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testAnExportLeavesOutTheUpdaterStateAndIsValidJSON() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("[]", forKey: "rules")
        defaults.set(Date(), forKey: "SULastCheckTime")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")

        let settings = GeneralTab.exportedSettings(from: defaults)
        XCTAssertEqual(settings["rules"] as? String, "[]")
        XCTAssertNil(settings["SULastCheckTime"])
        XCTAssertNil(settings["SUEnableAutomaticChecks"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(settings))
    }

    func testAResetKeepsTheUpdateChoice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("[]", forKey: "rules")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")

        GeneralTab.resetSettings(in: defaults)
        XCTAssertNil(defaults.object(forKey: "rules"))
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
    }
}

final class BrowserinoImportTests: XCTestCase {
    private let suite = "linkyard-tests-\(UUID().uuidString)"
    private var browserinoName: String { suite + ".browserino" }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        UserDefaults().removePersistentDomain(forName: browserinoName)
    }

    func testImportsBrowserinoOnceAndAResetStaysReset() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.setPersistentDomain([
            "browsers": #"["file:///Applications/Dia.app/"]"#,
            "rules": "[]",
            "NSWindow Frame Preferences": "0 0 700 500",
            "sourceDetectionAccessibilityPrompted": true,
        ], forName: browserinoName)

        BrowserinoImport.importIfNeeded(into: defaults, from: browserinoName)
        XCTAssertEqual(defaults.string(forKey: "browsers"), #"["file:///Applications/Dia.app/"]"#)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["NSWindow Frame Preferences"])
        XCTAssertFalse(defaults.bool(forKey: "sourceDetectionAccessibilityPrompted"))

        GeneralTab.resetSettings(in: defaults)
        BrowserinoImport.importIfNeeded(into: defaults, from: browserinoName)
        XCTAssertNil(defaults.object(forKey: "browsers"))
    }

    func testAnExistingSetupIsNeverOverwritten() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(#"["file:///Applications/Zen.app/"]"#, forKey: "browsers")
        defaults.setPersistentDomain(["browsers": #"["file:///Applications/Dia.app/"]"#], forName: browserinoName)

        BrowserinoImport.importIfNeeded(into: defaults, from: browserinoName)
        XCTAssertEqual(defaults.string(forKey: "browsers"), #"["file:///Applications/Zen.app/"]"#)
    }
}
