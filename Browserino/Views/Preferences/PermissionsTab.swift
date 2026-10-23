//
//  PermissionsTab.swift
//  Browserino
//

import SwiftUI

struct PermissionsTab: View {
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("browsers") private var browsers: [URL] = []

    @State private var accessibility = AccessibilityPermission.isGranted
    @State private var automation: [String: AutomationPermission.Status] = [:]
    @State private var isCheckingAutomation = false
    @State private var askingBundleIDs: Set<String> = []

    var body: some View {
        let titleRuleCount = rules.filter(\.readsWindowTitle).count
        let controlled = ChromiumProfileUtil.appleEventsBrowsers(in: browsers)

        SettingsForm {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: titleRuleCount == 0
                        ? "Lets rules match the window a link came from. None of your rules do yet."
                        : "Lets \(titleRuleCount == 1 ? "1 rule" : "\(titleRuleCount) rules") match the window a link came from.",
                    why: "To tell apart windows of the same app, like two Slack workspaces, Linkyard reads the title of the window you clicked a link in. It reads only that title, and only when a rule needs it.",
                    isAllowed: accessibility,
                    allow: AccessibilityPermission.request
                ) {
                    SettingsPaneIcon(symbol: "accessibility", tint: .blue, size: 28)
                }
                .settingsItem("permissions.accessibility")
            } header: {
                Text("Rules")
            } footer: {
                if controlled.isEmpty {
                    footer
                }
            }

            if !controlled.isEmpty {
                Section {
                    ForEach(controlled, id: \.source.bundleID) { browser in
                        let name = browser.app.appDisplayName
                        let status = automation[browser.source.bundleID]
                        PermissionRow(
                            title: "Control \(name)",
                            detail: automationDetail(status, name: name, noun: browser.source.profileNoun),
                            why: "Linkyard sends \(name) Apple Events to open each link in the \(browser.source.profileNoun) you chose, and to list its \(browser.source.profileLabel). Without this, links still open in \(name), in whichever \(browser.source.profileNoun) it has open.",
                            isAllowed: status == .allowed,
                            isAsking: askingBundleIDs.contains(browser.source.bundleID),
                            allow: { allowAutomation(app: browser.app, bundleID: browser.source.bundleID) }
                        ) {
                            ProfileIcon(appPath: browser.app.path, size: 28)
                        }
                        .settingsItem(SettingsItemID.automation(browser.source))
                    }
                } header: {
                    Text("Profiles and spaces")
                } footer: {
                    footer
                }
            }
        }
        .onAppear(perform: refresh)
        // Accessibility answers from a cache after the first call, so it's cheap to watch while System Settings is open.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                accessibility = AccessibilityPermission.isGranted
            }
        }
        .onSettingsWindowKey(perform: refresh)
    }

    private var footer: some View {
        Text("Linkyard isn't signed with a paid Apple Developer ID, so macOS turns these off each time Linkyard updates. Check back here after an update.")
    }

    private func automationDetail(_ status: AutomationPermission.Status?, name: String, noun: String) -> String {
        switch status {
        case .denied: "Turned off in System Settings, so links open in whichever \(noun) \(name) has open."
        case .notRunning: "Opens links in the \(name) \(noun) you pick. Linkyard can check this only while \(name) is open."
        default: "Opens links in the \(name) \(noun) you pick."
        }
    }

    private func refresh() {
        accessibility = AccessibilityPermission.isGranted
        guard !isCheckingAutomation else {
            return
        }

        let bundleIDs = ChromiumProfileUtil.appleEventsBrowsers(in: browsers).map(\.source.bundleID)
        isCheckingAutomation = true
        DispatchQueue.global(qos: .utility).async {
            let statuses = Dictionary(bundleIDs.map { ($0, AutomationPermission.status(of: $0)) }) { first, _ in first }
            DispatchQueue.main.async {
                automation = statuses
                isCheckingAutomation = false
            }
        }
    }

    /// macOS only asks once; after a "Don't Allow" the switch is in System Settings.
    private func allowAutomation(app: URL, bundleID: String) {
        if automation[bundleID] == .denied {
            AutomationPermission.openSettings()
            return
        }

        askingBundleIDs.insert(bundleID)
        DispatchQueue.global(qos: .userInitiated).async {
            let status = AutomationPermission.request(app, bundleID: bundleID)
            DispatchQueue.main.async {
                automation[bundleID] = status
                askingBundleIDs.remove(bundleID)
            }
        }
    }
}

private struct PermissionRow<Icon: View>: View {
    let title: String
    let detail: String
    let why: String
    let isAllowed: Bool
    var isAsking = false
    let allow: () -> Void
    @ViewBuilder let icon: Icon

    @State private var showsWhy = false

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                    Button {
                        showsWhy.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(why)
                    .accessibilityLabel("Why Linkyard needs \(title)")
                    .popover(isPresented: $showsWhy, arrowEdge: .bottom) {
                        Text(why)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 280, alignment: .leading)
                            .padding(14)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isAllowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isAsking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for macOS")
            } else {
                Button("Allow…", action: allow)
            }
        }
    }
}

#Preview {
    PermissionsTab()
}
