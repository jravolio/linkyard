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
