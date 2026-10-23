//
//  PickerTab.swift
//  Browserino
//

import SwiftUI

struct PickerTab: View {
    @AppStorage("prompt_centerOnScreen") private var centerOnScreen: Bool = false
    @AppStorage("prompt_animation") private var animation: PickerAnimation = .none
    @AppStorage("apps_atTop") private var appsAtTop: Bool = true
    @AppStorage("copy_alternativeShortcut") private var alternativeShortcut: Bool = false
    @AppStorage("copy_closeAfterCopy") private var closeAfterCopy: Bool = false
    @Environment(\.previewPicker) private var previewPicker

    private let keyboardShortcuts: [(action: String, keys: String)] = [
        ("Choose an identity", "↑ ↓"),
        ("Choose a browser", "← →"),
        ("Open", "↵"),
        ("Open in a private window", "⇧↵"),
        ("Open an identity in its first browser", "1 – 9"),
        ("Close", "esc"),
        ("Skip your rules", "hold ⌘ when you click a link"),
    ]

    var body: some View {
        SettingsForm {
            Section {
                Picker("Open the picker", selection: $centerOnScreen) {
                    Text("At the pointer").tag(false)
                    Text("In the center of the screen").tag(true)
                }
                .settingsItem("picker.position")

                LabeledContent {
                    HStack {
                        Picker("Animation", selection: $animation) {
                            ForEach(PickerAnimation.allCases.filter { $0.effect == nil }) { animation in
                                Text(animation.title).tag(animation)
                            }
                            Section("Effects") {
                                ForEach(PickerAnimation.effects) { animation in
                                    Text(animation.title).tag(animation)
                                }
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: animation) { animation in
                            if animation.effect != nil {
                                PickerEffectRenderer.prewarm()
                            }
                        }

                        Button("Preview", action: previewPicker)
                    }
                } label: {
                    Text("Animation")
                    Text(animation.summary)
                }
                .settingsItem("picker.animation")
            } footer: {
                Text("With Reduce Motion turned on in System Settings, every animation becomes a short fade.")
            }

            Section {
                Toggle("Show apps before browsers", isOn: $appsAtTop)
                    .settingsItem("picker.appsFirst")
            }

            Section("Copying the link") {
                Picker("Shortcut", selection: $alternativeShortcut) {
                    Text("⌥⌘C").tag(false)
                    Text("⌘C").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .settingsItem("picker.copyShortcut")

                Toggle("Close the picker after copying", isOn: $closeAfterCopy)
                    .settingsItem("picker.closeAfterCopy")
            }

            Section {
                ForEach(keyboardShortcuts, id: \.action) { shortcut in
                    LabeledContent(shortcut.action) {
                        Text(shortcut.keys)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keyboard")
                    .settingsItem("picker.keyboard")
            }
        }
    }
}

#Preview {
    PickerTab()
}
