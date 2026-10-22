//
//  EditAppForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct AppForm: View {
    var app: App?

    var onCancel: () -> Void
    var onSave: (App) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var host = ""
    @State private var appURL: URL?
    @State private var schemeOverride = ""
    @State private var openWithPresented = false

    /// Nil when the text isn't a valid host; empty means every link.
    private var normalizedHost: String? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ""
        }

        let url = trimmed.starts(with: /https?:\/\//) ? trimmed : "http://" + trimmed
        return URL(string: url)?.host()
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Website", text: $host, prompt: Text("example.com, or empty for every link"))

                    if normalizedHost == nil {
                        Text("This isn't a website address.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    LabeledContent("App") {
                        HStack {
                            if let appURL {
                                Text(appURL.appDisplayName)
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
                            appURL = url
                        }
                    }
                } footer: {
                    Text("Links to this website and its subdomains can open in the app.")
                }

                Section {
                    TextField("Replace scheme", text: $schemeOverride, prompt: Text("Optional, like figma"))
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Some apps only open links with their own scheme, like figma:// instead of https://.")
                }
            }
            .formStyle(.grouped)

            Divider()

            SettingsSheetFooter(
                saveTitle: app == nil ? "Add App" : "Save",
                canSave: normalizedHost != nil && appURL != nil,
                deleteTitle: "Delete App",
                onDelete: onDelete,
                onCancel: onCancel
            ) {
                if let normalizedHost, let appURL {
                    onSave(App(host: normalizedHost, schemeOverride: schemeOverride, app: appURL))
                }
            }
        }
        .frame(width: 480, height: 380)
        .onAppear {
            host = app?.host ?? ""
            appURL = app?.app
            schemeOverride = app?.schemeOverride ?? ""
        }
    }
}

#Preview {
    AppForm(
        app: App(host: "figma.com", schemeOverride: "figma", app: URL(fileURLWithPath: "/Applications/Figma.app")),
        onCancel: {},
        onSave: { _ in }
    )
}
