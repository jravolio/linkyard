//
//  UpdatesSection.swift
//  Browserino
//

import Combine
import SwiftUI

/// Settings reach the updater through this, so the views build without Sparkle (the README art harness).
struct UpdateSettings {
    var checksAutomatically: () -> Bool
    var setChecksAutomatically: (Bool) -> Void
    var canCheck: AnyPublisher<Bool, Never>
    var checkNow: () -> Void
}

private struct UpdateSettingsKey: EnvironmentKey {
    static let defaultValue: UpdateSettings? = nil
}

extension EnvironmentValues {
    var updateSettings: UpdateSettings? {
        get { self[UpdateSettingsKey.self] }
        set { self[UpdateSettingsKey.self] = newValue }
    }
}

struct UpdatesSection: View {
    let settings: UpdateSettings

    @State private var checksAutomatically: Bool
    @State private var canCheck = false

    /// Loaded here rather than in onAppear, where onChange would save the loaded value as if it were a choice.
    init(settings: UpdateSettings) {
        self.settings = settings
        _checksAutomatically = State(initialValue: settings.checksAutomatically())
    }

    var body: some View {
        Section {
            Toggle(isOn: $checksAutomatically) {
                Text("Check for updates automatically")
                Text("Linkyard looks for a new release on GitHub once a day and asks before installing it.")
            }
            .onChange(of: checksAutomatically) { settings.setChecksAutomatically($0) }
            .settingsItem("general.updates")

            LabeledContent("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                Button("Check Now", action: settings.checkNow)
                    .disabled(!canCheck)
            }
        } header: {
            Text("Updates")
        }
        .onReceive(settings.canCheck) { canCheck = $0 }
    }
}
