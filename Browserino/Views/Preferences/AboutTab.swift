//
//  AboutTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        SettingsForm {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Linkyard")
                        .font(.title.bold())
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                    Text("Every link to the right browser, as the right you.")
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .settingsItem("about.version")
            }

            Section {
                LabeledContent("Source code") {
                    Link("github.com/jravolio/linkyard", destination: URL(string: "https://github.com/jravolio/linkyard")!)
                }
                LabeledContent("Based on") {
                    Link("Browserino by Aleksandr Strizhnev", destination: URL(string: "https://github.com/AlexStrNik/Browserino")!)
                }
                LabeledContent("License") {
                    Text("GPL-3.0")
                }
            } footer: {
                Text("Thanks to @byt3m4st3r, @mihado, @ventz, @motilevy and everyone else who contributed to Browserino.")
            }
        }
    }
}

#Preview {
    AboutTab()
}
