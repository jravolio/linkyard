//
//  AppsTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct App: Codable, Hashable {
    var host: String
    var schemeOverride: String
    var app: URL
}

extension App {
    var title: String {
        host.isEmpty ? "All links" : host
    }

    var summary: String {
        schemeOverride.isEmpty
            ? "Opens in \(app.appDisplayName)"
            : "Opens in \(app.appDisplayName) as \(schemeOverride)://"
    }
}

struct AppsTab: View {
    @AppStorage("apps") private var apps: [App] = []
    @State private var editor: ListEditor?

    var body: some View {
        SettingsForm {
            Section {
                if apps.isEmpty {
                    Text("No apps yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                    HStack(spacing: 10) {
                        ProfileIcon(appPath: app.app.path, size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.title)
                            Text(app.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let bundleID = Bundle(url: app.app)?.bundleIdentifier {
                            ShortcutButton(browserId: bundleID, name: app.title)
                        }

                        Button("Edit…") {
                            editor = .existing(index)
                        }
                        .accessibilityLabel("Edit \(app.title)")
                    }
                    .contextMenu {
                        Button("Edit…") {
                            editor = .existing(index)
                        }
                        Button("Delete", role: .destructive) {
                            apps.remove(at: index)
                        }
                    }
                    .settingsItem(SettingsItemID.app(index))
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Button {
                        editor = .new
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .settingsItem("apps.add")
                }
            } footer: {
                Text("Links to these websites can open straight in their Mac app, which the picker shows as its own row.")
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                AppForm(app: nil, onCancel: { self.editor = nil }, onSave: {
                    apps.append($0)
                    self.editor = nil
                })
            case .existing(let index):
                if apps.indices.contains(index) {
                    AppForm(app: apps[index], onCancel: { self.editor = nil }, onSave: {
                        apps[index] = $0
                        self.editor = nil
                    }, onDelete: {
                        apps.remove(at: index)
                        self.editor = nil
                    })
                }
            }
        }
    }
}

#Preview {
    AppsTab()
}
