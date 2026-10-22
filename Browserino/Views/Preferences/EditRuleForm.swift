//
//  EditRuleForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

struct EditRuleForm: View {
    @Binding var rule: Rule
    @Binding var isPresented: Bool
    
    @AppStorage("rules") private var rules: [Rule] = []
    
    var body: some View {
        RuleForm(
            rule: rule,
            onCancel: {
                isPresented.toggle()
            },
            onSave: {
                rule = $0
                isPresented.toggle()
            },
            onDelete: {
                rules.removeAll {
                    $0 == rule
                }
                isPresented.toggle()
            }
        )
    }
}

struct NewRuleForm: View {
    @Binding var isPresented: Bool
    
    @AppStorage("rules") private var rules: [Rule] = []
    
    var body: some View {
        RuleForm(
            rule: nil,
            onCancel: {
                isPresented.toggle()
            },
            onSave: {
                rules.append($0)
                isPresented.toggle()
            },
            onDelete: {
                isPresented.toggle()
            }
        )
    }
}

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
    var onDelete: () -> Void

    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("arcProfilesEnabled") private var arcProfilesEnabled: Bool = true
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    @AppStorage("browsers") private var browsers: [URL] = []

    @State private var openWithPresented = false
    @State private var sourceAppPresented = false

    @State private var regex: String = ""
    @State private var testUrls: String = "https://github.com/AlexStrNik/Browserino\nhttps://x.com/alexstrnik"
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
    
    private var attributtedText: AttributedString {
        var string = AttributedString(testUrls)
        guard let compiledRegex else {
            return string
        }
        
        for line in testUrls.split(separator: "\n") {
            if line.firstMatch(of: compiledRegex) != nil, let range = string.range(of: line) {
                string[range].foregroundColor = .red
            }
        }
        
        return string
    }

    private var selectedAppProfiles: [ChromeProfile] {
        guard let bundleID = selectedAppBundleID else {
            return []
        }

        switch bundleID {
        case ChromiumProfileUtil.chromeBundleID:
            return chromeProfiles
        case ChromiumProfileUtil.arcBundleID:
            return arcProfiles
        default:
            return []
        }
    }

    private func refreshArcProfilesIfNeeded() {
        guard ChromiumProfileUtil.shouldRefreshProfiles(
            for: ChromiumProfileUtil.arcSource,
            profiles: arcProfiles
        ) else {
            return
        }

        let refreshedProfiles = ChromiumProfileUtil.refreshProfiles(
            for: ChromiumProfileUtil.arcSource,
            existing: arcProfiles
        )
        shortcuts = ChromiumProfileUtil.migrateShortcuts(
            shortcuts,
            for: ChromiumProfileUtil.arcSource,
            profiles: refreshedProfiles
        )
        arcProfiles = refreshedProfiles
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
            let browserName = bundle.infoDictionary?["CFBundleName"] as? String ?? browser.deletingPathExtension().lastPathComponent
            var options = [RuleTargetOption(
                id: targetOptionID(appURL: browser, profileDirectory: nil),
                appURL: browser,
                profileDirectory: nil,
                displayName: browserName
            )]

            switch bundleID {
            case ChromiumProfileUtil.chromeBundleID where chromeProfilesEnabled:
                options.append(contentsOf: chromeProfiles.map { profile in
                    RuleTargetOption(
                        id: targetOptionID(appURL: browser, profileDirectory: profile.directoryName),
                        appURL: browser,
                        profileDirectory: profile.directoryName,
                        displayName: "\(browserName) - \(profile.displayName)"
                    )
                })
            case ChromiumProfileUtil.arcBundleID where arcProfilesEnabled:
                options.append(contentsOf: arcProfiles.map { profile in
                    RuleTargetOption(
                        id: targetOptionID(appURL: browser, profileDirectory: profile.selectionID),
                        appURL: browser,
                        profileDirectory: profile.selectionID,
                        displayName: "\(browserName) - \(profile.displayName)"
                    )
                })
            default:
                break
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

    private func profileSelectionID(_ profile: ChromeProfile, bundleID: String) -> String {
        bundleID == ChromiumProfileUtil.arcBundleID ? profile.selectionID : profile.directoryName
    }

    private func normalizedProfileDirectory(_ value: String?, bundleID: String) -> String? {
        guard bundleID == ChromiumProfileUtil.arcBundleID, let value else {
            return value
        }

        return selectedAppProfiles.first {
            $0.selectionID == value || $0.directoryName == value
        }?.selectionID ?? value
    }
    
    var body: some View {
        Form {
            Section(
                header: Text("General")
                    .font(.headline)
            ) {
                TextField("Regex:", text: $regex)
                    .font(
                        .system(size: 14)
                    )
                
                LabeledContent("Test URLs:") {
                    TextEditor(text: $testUrls)
                        .font(
                            .system(size: 14)
                        )
                }
                
                Text(attributtedText)
                    .font(
                        .system(size: 14)
                    )
            }
            
            Spacer()
                .frame(height: 32)

            Section(
                header: Text("Source Conditions")
                    .font(.headline)
            ) {
                Text("Optional. Use this to route links clicked from a specific app or Slack workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Source application:") {
                    Button(action: {
                        sourceAppPresented.toggle()
                    }) {
                        Text("Choose source app")
                    }
                    .fileImporter(
                        isPresented: $sourceAppPresented,
                        allowedContentTypes: [.application]
                    ) {
                        if case .success(let url) = $0 {
                            self.sourceApp = url
                        }
                    }

                    if let bundle = sourceApp.flatMap({ Bundle(url: $0) }) {
                        Text("\(bundle.infoDictionary!["CFBundleName"] as! String)")
                            .padding(.horizontal, 5)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(action: {
                            sourceApp = nil
                        }) {
                            Text("Clear")
                        }
                    } else {
                        Text("Any app")
                            .padding(.horizontal, 5)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Source window title regex:") {
                    TextField("Example: Acme", text: $sourceWindowTitleRegex)
                        .font(.system(size: 14))

                    if !sourceWindowTitleRegexIsValid {
                        Text("Invalid regex")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()
                .frame(height: 32)
            
            if !targetOptions.isEmpty {
                LabeledContent("Open in:") {
                    Picker("", selection: targetSelectionBinding) {
                        Text("Choose browser or profile").tag(nil as String?)
                        ForEach(targetOptions) { option in
                            Text(option.displayName).tag(option.id as String?)
                        }
                    }
                    .frame(width: 260)
                }
            }
             
            LabeledContent("Application:") {
                Button(action: {
                    openWithPresented.toggle()
                }) {
                    Text("Choose custom app")
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
                
                if let bundle = url.map({ Bundle(url: $0)! }) {
                    Text("\(bundle.infoDictionary!["CFBundleName"] as! String)")
                        .padding(.horizontal, 5)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let bundle = url.flatMap({ Bundle(url: $0) }),
               let bundleID = bundle.bundleIdentifier,
               ChromiumProfileUtil.source(for: bundleID) != nil,
               !selectedAppProfiles.isEmpty {
                LabeledContent("Profile:") {
                    Picker("", selection: profileDirectoryBinding) {
                        Text("None").tag(nil as String?)
                        ForEach(selectedAppProfiles, id: \.selectionID) { profile in
                            Text(profile.displayName).tag(profileSelectionID(profile, bundleID: bundleID) as String?)
                        }
                    }
                    .frame(width: 200)
                }
            }

            Spacer()
                .frame(height: 32)
            
            HStack {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                }
                
                if rule != nil {
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete")
                    }
                }
                
                Spacer()
                
                Button(action: {
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
                }) {
                    Text("Save")
                }
                .disabled(compiledRegex == nil || url == nil || !sourceWindowTitleRegexIsValid)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(minWidth: 500)
        .onAppear {
            refreshArcProfilesIfNeeded()
            regex = rule?.regex ?? ""
            url = rule?.app
            profileDirectory = rule?.profileDirectory
            sourceApp = rule?.sourceApp
            sourceWindowTitleRegex = rule?.sourceWindowTitleRegex ?? ""
        }
    }
}
