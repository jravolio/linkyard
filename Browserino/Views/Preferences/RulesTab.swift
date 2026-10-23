//
//  RulesTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

extension Rule {
    var title: String {
        regex == ".*" ? "Any link" : regex
    }

    func targetProfile(in profiles: [String: [ChromeProfile]]) -> ChromeProfile? {
        guard let profileDirectory, let bundleID = Bundle(url: app)?.bundleIdentifier else {
            return nil
        }

        return profiles[bundleID]?.first { $0.matches(profileDirectory) }
    }

    func summary(profiles: [String: [ChromeProfile]]) -> String {
        var target = app.appDisplayName
        if let profileDirectory {
            target += " · \(targetProfile(in: profiles)?.displayName ?? profileDirectory)"
        }

        var parts = ["Opens in \(target)"]
        if let sourceApp {
            parts.append("from \(sourceApp.appDisplayName)")
        }
        if let sourceWindowTitleRegex, !sourceWindowTitleRegex.isEmpty {
            parts.append("window matches “\(sourceWindowTitleRegex)”")
        }
        return parts.joined(separator: ", ")
    }
}

struct RulesTab: View {
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("diaProfiles") private var diaProfiles: [ChromeProfile] = []
    @AppStorage("zenProfiles") private var zenProfiles: [ChromeProfile] = []

    @State private var editor: ListEditor?
    @State private var accessibilityGranted: Bool?
    @Environment(\.openSettingsItem) private var openSettingsItem

    private var profilesByBundleID: [String: [ChromeProfile]] {
        [
            ChromiumProfileUtil.chromeBundleID: chromeProfiles,
            ChromiumProfileUtil.arcBundleID: arcProfiles,
            ChromiumProfileUtil.diaBundleID: diaProfiles,
            ChromiumProfileUtil.zenBundleID: zenProfiles,
        ]
    }

    var body: some View {
        let profiles = profilesByBundleID

        SettingsForm {
            if accessibilityGranted == false && rules.contains(where: \.readsWindowTitle) {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Rules that match a window title need Accessibility access, which is off. Until it's on, those rules are skipped and links open the picker.")
                        Spacer()
                        Button("Show Permissions") {
                            openSettingsItem(.permissions, "permissions.accessibility")
                        }
                    }
                }
            }

            Section {
                if rules.isEmpty {
                    Text("No rules yet, so every link opens the picker.")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    HStack(spacing: 10) {
                        ProfileIcon(appPath: rule.app.path, iconPath: rule.targetProfile(in: profiles)?.iconPath, size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.title)
                                .font(rule.regex == ".*" ? .body : .body.monospaced())
                                .lineLimit(1)
                            Text(rule.summary(profiles: profiles))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Edit…") {
                            editor = .existing(index)
                        }
                        .accessibilityLabel("Edit rule \(rule.title)")
                    }
                    .contextMenu {
                        Button("Edit…") {
                            editor = .existing(index)
                        }
                        Button("Delete", role: .destructive) {
                            rules.remove(at: index)
                        }
                    }
                    .reorderable(at: index, count: rules.count) { rules.move(from: $0, to: $1) }
                    .settingsItem(SettingsItemID.rule(index))
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    Button {
                        editor = .new
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .settingsItem("rules.add")
                }
            } footer: {
                Text("Rules are checked from top to bottom, and the first one that matches opens the link without the picker. Drag a rule onto another to change the order. Hold ⌘ when you click a link to skip your rules.")
            }
        }
        .onAppear(perform: refreshAccessibility)
        .onChange(of: rules) { _ in refreshAccessibility() }
        .onSettingsWindowKey(perform: refreshAccessibility)
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                RuleForm(rule: nil, onCancel: { self.editor = nil }, onSave: {
                    rules.append($0)
                    self.editor = nil
                })
            case .existing(let index):
                if rules.indices.contains(index) {
                    RuleForm(rule: rules[index], onCancel: { self.editor = nil }, onSave: {
                        rules[index] = $0
                        self.editor = nil
                    }, onDelete: {
                        rules.remove(at: index)
                        self.editor = nil
                    })
                }
            }
        }
    }
}

private extension RulesTab {
    /// The first Accessibility check in a process takes tens of ms, so it's skipped when no rule needs it.
    func refreshAccessibility() {
        if rules.contains(where: \.readsWindowTitle) {
            accessibilityGranted = AccessibilityPermission.isGranted
        }
    }
}

#Preview {
    RulesTab()
}
