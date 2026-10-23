//
//  GeneralTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var settings: [String: Any]
    
    init(settings: [String: Any] = [:]) {
        self.settings = settings
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.settings = jsonObject
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        return .init(regularFileWithContents: data)
    }
}

struct GeneralTab: View {
    @State private var isDefault = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.updateSettings) private var updateSettings
    @State private var showingExportPicker = false
    @State private var showingImportPicker = false
    @State private var showingResetConfirmation = false
    @State private var exportDocument = SettingsDocument()
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true

    func defaultBrowser() -> String? {
        guard let browserUrl = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https:")!) else {
            return nil
        }
        
        return Bundle(url: browserUrl)?.bundleIdentifier
    }
    
    func exportSettings() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        let filteredSettings = dictionary.filter { key, _ in
            !key.contains("NS") &&
            !key.contains("com.apple.") &&
            !key.contains("Apple") &&
            !key.contains("METAL") &&
            !key.contains("KB_") &&
            !key.contains("cloud.") &&
            !key.starts(with: "_") &&
            !key.starts(with: "AK") &&
            key != "shouldShowRSVPDataDetectors" &&
            key != "MultipleSessionEnabled" &&
            key != "WebAutomaticSpellingCorrectionEnabled" &&
            key != "Country"
        }
        
        var appSettings: [String: Any] = [:]
        for (key, value) in filteredSettings {
            appSettings[key] = value
        }
        
        exportDocument = SettingsDocument(settings: appSettings)
        showingExportPicker = true
    }
    
    func importSettings(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let settings = settings else {
                print("Invalid settings format")
                return
            }
            
            let defaults = UserDefaults.standard
            for (key, value) in settings {
                defaults.set(value, forKey: key)
            }
        } catch {
            print("Failed to import settings: \(error.localizedDescription)")
        }
    }

    static func resetSettings(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: BrowserinoImport.doneKey)
    }

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent {
                    if isDefault {
                        Label("In use", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Make Default") {
                            NSWorkspace.shared.setDefaultApplication(
                                at: Bundle.main.bundleURL,
                                toOpenURLsWithScheme: "http"
                            ) { _ in
                                DispatchQueue.main.async {
                                    isDefault = defaultBrowser() == Bundle.main.bundleIdentifier
                                }
                            }
                        }
                    }
                } label: {
                    Text("Default browser")
                    Text(isDefault
                        ? "Links you click in other apps come to Linkyard first."
                        : "Make Linkyard your default browser so links come to it first.")
                }
                .settingsItem("general.defaultBrowser")
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .settingsItem("general.launchAtLogin")

                Toggle(isOn: $showInMenuBar) {
                    Text("Show in menu bar")
                    Text("When it's hidden, open Linkyard from Finder to get back to Settings.")
                }
                .settingsItem("general.menuBar")
            }

            if let updateSettings {
                UpdatesSection(settings: updateSettings)
            }

            Section {
                LabeledContent {
                    HStack {
                        Button("Export…", action: exportSettings)
                        Button("Import…") {
                            showingImportPicker = true
                        }
                    }
                } label: {
                    Text("Back up settings")
                    Text("Browsers, profiles, rules, apps and shortcuts, in a file you can import on another Mac.")
                }
                .settingsItem("general.backup")

                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        showingResetConfirmation = true
                    }
                } label: {
                    Text("Reset all settings")
                    Text("Removes your browsers, profiles, rules, apps and shortcuts.")
                }
                .settingsItem("general.reset")
            }
        }
        .onAppear {
            isDefault = defaultBrowser() == Bundle.main.bundleIdentifier
        }
        .confirmationDialog("Reset all Linkyard settings?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                Self.resetSettings()
            }
        } message: {
            Text("This can't be undone. Export your settings first if you might want them back.")
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "linkyard-settings"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importSettings(from: url)
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    PreferencesView()
}
