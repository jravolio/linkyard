//
//  BrowsersTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct BrowsersTab: View {
    @AppStorage("browsers") private var browsers: [URL] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [URL] = []
    @AppStorage("privateArgs") private var privateArgs: [String: String] = [:]

    private func isVisible(_ browser: URL) -> Binding<Bool> {
        Binding(
            get: { !hiddenBrowsers.contains(browser) },
            set: { visible in
                hiddenBrowsers.removeAll { $0 == browser }
                if !visible {
                    hiddenBrowsers.append(browser)
                }
            }
        )
    }

    private func privateArg(for bundleID: String) -> Binding<String> {
        Binding(
            get: { privateArgs[bundleID, default: ""] },
            set: { privateArgs[bundleID] = $0 }
        )
    }

    /// Browsers that were uninstalled stay stored but aren't shown, so moves are made between the rows on screen.
    private func moveShown(_ shown: [(offset: Int, element: URL)], from: Int, to: Int) {
        browsers.move(from: shown[from].offset, to: shown[to].offset)
    }

    var body: some View {
        let shown = Array(browsers.enumerated().filter { Bundle(url: $0.element)?.bundleIdentifier != nil })

        SettingsForm {
            Section {
                ForEach(Array(shown.enumerated()), id: \.element.element) { index, entry in
                    let browser = entry.element
                    if let bundleID = Bundle(url: browser)?.bundleIdentifier {
                        HStack(spacing: 10) {
                            ProfileIcon(appPath: browser.path, size: 24)

                            Text(browser.appDisplayName)

                            Spacer()

                            ShortcutButton(browserId: bundleID, name: browser.appDisplayName)

                            Toggle("Show \(browser.appDisplayName) in the picker", isOn: isVisible(browser))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .reorderable(at: index, count: shown.count) { moveShown(shown, from: $0, to: $1) }
                        .settingsItem(SettingsItemID.browser(browser))
                    }
                }
            } header: {
                HStack {
                    Text("Browsers")
                        .settingsItem("browsers.list")
                    Spacer()
                    Button("Rescan") {
                        browsers = BrowserUtil.loadBrowsers(oldBrowsers: browsers)
                    }
                    .settingsItem("browsers.rescan")
                }
            } footer: {
                Text("The picker shows browsers in this order; drag a browser onto another to move it there. Switch a browser off to hide it from the picker.")
            }

            Section {
                ForEach(browsers, id: \.self) { browser in
                    if let bundleID = Bundle(url: browser)?.bundleIdentifier {
                        LabeledContent(browser.appDisplayName) {
                            TextField(browser.appDisplayName, text: privateArg(for: bundleID), prompt: Text("Not set"))
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } header: {
                Text("Private windows")
                    .settingsItem("browsers.private")
            } footer: {
                Text("The command-line flag Linkyard passes when you press ⇧↵ in the picker, like --incognito for Chrome.")
            }

            BrowserLocationsSection()
        }
        .onAppear {
            if browsers.isEmpty {
                browsers = BrowserUtil.loadBrowsers(oldBrowsers: browsers)
            }
        }
    }
}

#Preview {
    BrowsersTab()
}
