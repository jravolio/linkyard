//
//  EditRuleForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

private struct RuleTargetOption: Identifiable, Hashable {
    let id: String
    let appURL: URL
    let profileDirectory: String?
    let displayName: String
}

struct RuleForm: View {
    var rule: Rule?

    var onCancel: () -> Void
    var onSave: (Rule) -> Void
    var onDelete: (() -> Void)? = nil

    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("arcProfilesEnabled") private var arcProfilesEnabled: Bool = true
    @AppStorage("diaProfiles") private var diaProfiles: [ChromeProfile] = []
    @AppStorage("diaProfilesEnabled") private var diaProfilesEnabled: Bool = true
    @AppStorage("zenProfiles") private var zenProfiles: [ChromeProfile] = []
    @AppStorage("zenProfilesEnabled") private var zenProfilesEnabled: Bool = true
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    @AppStorage("browsers") private var browsers: [URL] = []

    @State private var openWithPresented = false
    @State private var sourceAppPresented = false

    @State private var regex: String = ".*"
    @State private var testLink: String = "https://github.com/jravolio/linkyard"
    @State private var url: URL?
    @State private var profileDirectory: String? = nil
    @State private var sourceApp: URL? = nil
    @State private var sourceWindowTitleRegex: String = ""
    
    private var compiledRegex: Regex<AnyRegexOutput>? {
        return try? Regex(regex).ignoresCase()
    }

    private var trimmedSourceWindowTitleRegex: String {
        sourceWindowTitleRegex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceWindowTitleRegexIsValid: Bool {
        trimmedSourceWindowTitleRegex.isEmpty || (try? Regex(trimmedSourceWindowTitleRegex).ignoresCase()) != nil
    }
    
    private var testLinkMatches: Bool {
        compiledRegex.map { testLink.firstMatch(of: $0) != nil } ?? false
    }

    private func profileSettings(for bundleID: String) -> (profiles: [ChromeProfile], enabled: Bool)? {
        switch bundleID {
        case ChromiumProfileUtil.chromeBundleID:
            return (chromeProfiles, chromeProfilesEnabled)
        case ChromiumProfileUtil.arcBundleID:
            return (arcProfiles, arcProfilesEnabled)
        case ChromiumProfileUtil.diaBundleID:
            return (diaProfiles, diaProfilesEnabled)
        case ChromiumProfileUtil.zenBundleID:
            return (zenProfiles, zenProfilesEnabled)
        default:
            return nil
        }
    }

    private var selectedAppProfiles: [ChromeProfile] {
        selectedAppBundleID.flatMap { profileSettings(for: $0)?.profiles } ?? []
    }

    private var selectedAppBundleID: String? {
        url.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private var targetOptions: [RuleTargetOption] {
        browsers.flatMap { browser -> [RuleTargetOption] in
            guard let bundle = Bundle(url: browser) else {
                return []
            }

            let bundleID = bundle.bundleIdentifier ?? browser.absoluteString
            let browserName = browser.appDisplayName
            var options = [RuleTargetOption(
                id: targetOptionID(appURL: browser, profileDirectory: nil),
                appURL: browser,
                profileDirectory: nil,
                displayName: browserName
            )]

            if let settings = profileSettings(for: bundleID), settings.enabled {
                options.append(contentsOf: settings.profiles.map { profile in
                    RuleTargetOption(
                        id: targetOptionID(appURL: browser, profileDirectory: profile.selectionID),
                        appURL: browser,
                        profileDirectory: profile.selectionID,
                        displayName: "\(browserName) - \(profile.displayName)"
                    )
                })
            }

            return options
        }
    }

    private var targetSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedTargetOption?.id },
            set: { targetID in
                guard let targetID,
                      let option = targetOptions.first(where: { $0.id == targetID })
                else {
                    return
                }

                url = option.appURL
                profileDirectory = option.profileDirectory
            }
        )
    }

    private var selectedTargetOption: RuleTargetOption? {
        guard let url else {
            return nil
        }

        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        let normalizedProfileDirectory = normalizedProfileDirectory(profileDirectory, bundleID: bundleID)
        return targetOptions.first {
            $0.appURL == url && $0.profileDirectory == normalizedProfileDirectory
        }
    }

    private func targetOptionID(appURL: URL, profileDirectory: String?) -> String {
        "\(appURL.absoluteString)::\(profileDirectory ?? "")"
    }

    private var profileDirectoryBinding: Binding<String?> {
        Binding(
            get: {
                guard let bundleID = selectedAppBundleID else {
                    return profileDirectory
                }

                return normalizedProfileDirectory(profileDirectory, bundleID: bundleID)
            },
            set: { profileDirectory = $0 }
        )
    }

    private var showsProfilePicker: Bool {
        guard let bundleID = selectedAppBundleID,
              ChromiumProfileUtil.source(for: bundleID) != nil,
              !selectedAppProfiles.isEmpty
        else {
            return false
        }

        return selectedTargetOption == nil || profileSettings(for: bundleID)?.enabled == false
    }

    private func save() {
        guard let url else {
            return
        }

        let bundleID = Bundle(url: url)?.bundleIdentifier
        onSave(
            Rule(
                regex: regex,
                app: url,
                profileDirectory: selectedAppProfiles.isEmpty
                    ? nil
                    : normalizedProfileDirectory(profileDirectory, bundleID: bundleID ?? ""),
                sourceApp: sourceApp,
                sourceWindowTitleRegex: trimmedSourceWindowTitleRegex.isEmpty
                    ? nil
                    : trimmedSourceWindowTitleRegex
            )
        )
    }

    private func normalizedProfileDirectory(_ value: String?, bundleID: String) -> String? {
        guard bundleID == ChromiumProfileUtil.arcBundleID, let value else {
            return value
        }

        return selectedAppProfiles.first {
            $0.matches(value)
        }?.selectionID ?? value
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("URL pattern") {
                        TextField("URL pattern", text: $regex, prompt: Text(".* matches every link"))
                            .labelsHidden()
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                    }

                    if compiledRegex == nil {
                        Text("This isn't a valid regular expression.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    LabeledContent {
                        TextField("Test a link", text: $testLink, prompt: Text("Paste a link"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("Test a link")
                        Label(testLinkMatches ? "Matches" : "Doesn't match", systemImage: testLinkMatches ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(testLinkMatches ? Color.green : Color.secondary)
                    }
                } header: {
                    Text("Match links")
                } footer: {
                    Text("A regular expression, matched anywhere in the link and ignoring case.")
                }

                Section {
                    LabeledContent("Clicked in") {
                        HStack {
                            Text(sourceApp?.appDisplayName ?? "Any app")
                                .foregroundStyle(.secondary)
                            if sourceApp != nil {
                                Button("Clear") {
                                    sourceApp = nil
                                }
                            }
                            Button("Choose…") {
                                sourceAppPresented.toggle()
                            }
                        }
                    }
                    .fileImporter(
                        isPresented: $sourceAppPresented,
                        allowedContentTypes: [.application]
                    ) {
                        if case .success(let url) = $0 {
                            self.sourceApp = url
                        }
                    }

                    TextField("Window title", text: $sourceWindowTitleRegex, prompt: Text("Optional, like Acme"))

                    if !sourceWindowTitleRegexIsValid {
                        Text("This isn't a valid regular expression.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Only links from")
                } footer: {
                    Text("Optional. Match links clicked in one app, or only in its windows whose title matches, to tell Slack workspaces apart. Window titles need Accessibility access.")
                }

                Section("Open in") {
                    if !targetOptions.isEmpty {
                        Picker("Browser", selection: targetSelectionBinding) {
                            Text("Choose…").tag(nil as String?)
                            ForEach(targetOptions) { option in
                                Text(option.displayName).tag(option.id as String?)
                            }
                        }
                    }

                    LabeledContent("Another app") {
                        HStack {
                            if let url, selectedTargetOption == nil {
                                Text(url.appDisplayName)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Choose…") {
                                openWithPresented.toggle()
                            }
                        }
                    }
                    .fileImporter(
                        isPresented: $openWithPresented,
                        allowedContentTypes: [.application]
                    ) {
                        if case .success(let url) = $0 {
                            self.url = url
                            self.profileDirectory = nil
                        }
                    }

                    if showsProfilePicker {
                        Picker("Profile", selection: profileDirectoryBinding) {
                            Text("None").tag(nil as String?)
                            ForEach(selectedAppProfiles, id: \.selectionID) { profile in
                                Text(profile.displayName).tag(profile.selectionID as String?)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            SettingsSheetFooter(
                saveTitle: rule == nil ? "Add Rule" : "Save",
                canSave: compiledRegex != nil && url != nil && sourceWindowTitleRegexIsValid,
                deleteTitle: "Delete Rule",
                onDelete: onDelete,
                onCancel: onCancel,
                onSave: save
            )
        }
        .frame(width: 540, height: 460)
        .onAppear {
            ChromiumProfileUtil.refreshArcProfilesIfNeeded($arcProfiles, shortcuts: $shortcuts)
            regex = rule?.regex ?? ".*"
            url = rule?.app
            profileDirectory = rule?.profileDirectory
            sourceApp = rule?.sourceApp
            sourceWindowTitleRegex = rule?.sourceWindowTitleRegex ?? ""
        }
    }
}
