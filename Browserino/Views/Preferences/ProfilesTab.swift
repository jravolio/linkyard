//
//  ProfilesTab.swift
//  Browserino
//

import SwiftUI

struct ProfilesTab: View {
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("arcProfilesEnabled") private var arcProfilesEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ProfileSourceSection(
                    source: ChromiumProfileUtil.chromeSource,
                    profiles: $chromeProfiles,
                    profilesEnabled: $chromeProfilesEnabled
                )

                ProfileSourceSection(
                    source: ChromiumProfileUtil.arcSource,
                    profiles: $arcProfiles,
                    profilesEnabled: $arcProfilesEnabled
                )
            }

            Text("Detect Chrome profiles and Arc spaces and show them as separate picker items. Assign shortcuts and hide entries you don't use.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.5))
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

private struct ProfileSourceSection: View {
    let source: ChromiumProfileSource

    @Binding var profiles: [ChromeProfile]
    @Binding var profilesEnabled: Bool

    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]

    @State private var hasDetected = false

    private var isInstalled: Bool {
        ChromiumProfileUtil.appURL(for: source) != nil
    }

    private var shouldRefreshProfiles: Bool {
        ChromiumProfileUtil.shouldRefreshProfiles(for: source, profiles: profiles)
    }

    private func detectProfiles() {
        let refreshedProfiles = ChromiumProfileUtil.refreshProfiles(for: source, existing: profiles)
        shortcuts = ChromiumProfileUtil.migrateShortcuts(
            shortcuts,
            for: source,
            profiles: refreshedProfiles
        )
        profiles = refreshedProfiles
        hasDetected = true
    }

    private func displayName(at index: Int) -> Binding<String> {
        Binding(
            get: { profiles[index].displayName },
            set: { profiles[index].displayName = $0 }
        )
    }

    var body: some View {
        Section(header: Text(source.displayName)) {
            if !isInstalled {
                Text("\(source.displayName) is not installed.")
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                HStack(spacing: 16) {
                    Toggle(isOn: $profilesEnabled) {
                        Text("Show \(source.displayName) \(source.profileLabel) as separate items in the picker")
                            .font(.callout)
                    }

                    Spacer()

                    Button(action: detectProfiles) {
                        Text("Detect \(source.profileLabel.capitalized)")
                    }
                }
                .padding(.vertical, 4)

                if profiles.isEmpty {
                    Text("No \(source.profileLabel) detected.")
                        .foregroundStyle(.secondary)
                        .padding(10)
                }

                ForEach(Array(profiles.enumerated()), id: \.element.selectionID) { index, profile in
                    HStack {
                        TextField("Display name", text: displayName(at: index))
                            .font(.system(size: 14))
                            .frame(maxWidth: 200)

                        Spacer()
                            .frame(width: 16)

                        Text(source.detectsArcSpaces && profile.arcSpaceID != nil
                            ? "\(profile.directoryName) space"
                            : profile.directoryName)
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        ShortcutButton(
                            browserId: "\(source.bundleID)::\(source.detectsArcSpaces ? profile.selectionID : profile.directoryName)"
                        )

                        Spacer()
                            .frame(width: 8)

                        Button(action: {
                            profiles[index].isHidden.toggle()
                        }) {
                            Image(
                                systemName: profile.isHidden
                                    ? "eye.slash.fill" : "eye.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                }
            }
        }
        .onAppear {
            if !hasDetected && isInstalled && shouldRefreshProfiles {
                detectProfiles()
            }
        }
    }
}

#Preview {
    ProfilesTab()
}
