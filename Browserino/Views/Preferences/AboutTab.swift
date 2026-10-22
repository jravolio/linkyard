//
//  AboutTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack {
            Spacer()
            
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 128, height: 128)
            
            Text(
                "Linkyard v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String)"
            )
            .font(.title)
            .frame(maxWidth: .infinity)
            
            Spacer()
                .frame(height: 16)
            
            Button(action: {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/jravolio/linkyard")!
                )
            }) {
                Text("https://github.com/jravolio/linkyard")
            }
            .buttonStyle(.link)
            
            Spacer()
                .frame(height: 16)
            
            Text("A community continuation of Browserino by Aleksandr Strizhnev (@AlexStrNik).")
                .foregroundStyle(.secondary)

            Button(action: {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/AlexStrNik/Browserino")!
                )
            }) {
                Text("https://github.com/AlexStrNik/Browserino")
            }
            .buttonStyle(.link)

            Text("Thanks to @byt3m4st3r, @mihado, @ventz, @motilevy and others for contributions!")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    AboutTab()
}
