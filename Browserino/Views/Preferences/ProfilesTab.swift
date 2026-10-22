//
//  ProfilesTab.swift
//  Browserino
//

import SwiftUI
import UniformTypeIdentifiers

struct ProfilesTab: View {
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("arcProfiles") private var arcProfiles: [ChromeProfile] = []
    @AppStorage("arcProfilesEnabled") private var arcProfilesEnabled: Bool = true
    @AppStorage("diaProfiles") private var diaProfiles: [ChromeProfile] = []
    @AppStorage("diaProfilesEnabled") private var diaProfilesEnabled: Bool = true
    @AppStorage("zenProfiles") private var zenProfiles: [ChromeProfile] = []
    @AppStorage("zenProfilesEnabled") private var zenProfilesEnabled: Bool = true

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

                ProfileSourceSection(
                    source: ChromiumProfileUtil.diaSource,
                    profiles: $diaProfiles,
                    profilesEnabled: $diaProfilesEnabled
                )

                ProfileSourceSection(
                    source: ChromiumProfileUtil.zenSource,
                    profiles: $zenProfiles,
                    profilesEnabled: $zenProfilesEnabled
                )
            }

            Text("Detect Chrome and Dia profiles, Arc spaces and Zen containers and show them as separate picker items. Click an icon to give a profile its own logo, assign shortcuts and hide entries you don't use.")
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

    /// List rows must have IDs unique across every section; Dia and Zen can both have a "Personal" profile.
    private var rows: [(index: Int, profile: ChromeProfile, id: String)] {
        profiles.enumerated().map { ($0.offset, $0.element, "\(source.bundleID)::\($0.element.selectionID)") }
    }

    private func displayName(at index: Int) -> Binding<String> {
        Binding(
            get: { profiles[index].displayName },
            set: { profiles[index].displayName = $0 }
        )
    }

    private func iconPath(at index: Int) -> Binding<String?> {
        Binding(
            get: { profiles[index].iconPath },
            set: { profiles[index].iconPath = $0 }
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

                ForEach(rows, id: \.id) { index, profile, rowID in
                    HStack {
                        ProfileIconPicker(
                            appPath: ChromiumProfileUtil.appURL(for: source)?.path,
                            iconPath: iconPath(at: index)
                        )

                        TextField("Display name", text: displayName(at: index))
                            .font(.system(size: 14))
                            .frame(maxWidth: 200)

                        Spacer()
                            .frame(width: 16)

                        Text(profile.arcSpaceID != nil
                            ? "\(profile.directoryName) space"
                            : profile.directoryName)
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        ShortcutButton(
                            browserId: rowID
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

private struct ProfileIconPicker: View {
    let appPath: String?

    @Binding var iconPath: String?

    var body: some View {
        Button(action: chooseIcon) {
            if let appPath {
                ProfileIcon(appPath: appPath, iconPath: iconPath, size: 20)
            } else {
                Image(systemName: "photo")
            }
        }
        .buttonStyle(.plain)
        .help("Choose an icon for this profile")
        .accessibilityLabel("Profile icon")
        .contextMenu {
            if iconPath != nil {
                Button("Remove Icon") {
                    iconPath = nil
                }
            }
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linkyard/ProfileIcons", isDirectory: true)
        let destination = folder.appendingPathComponent("\(UUID().uuidString).png")

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.thumbnailPNG(of: url).write(to: destination)
            iconPath = destination.path
        } catch {
            print("Failed to save profile icon: \(error)")
        }
    }

    /// Logos are drawn at 36pt at most, so a 256px copy keeps the picker from decoding full-size images.
    private static func thumbnailPNG(of url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url),
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              )
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let scale = min(256 / max(image.size.width, 1), 256 / max(image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: (256 - size.width) / 2, y: (256 - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}

#Preview {
    ProfilesTab()
}
