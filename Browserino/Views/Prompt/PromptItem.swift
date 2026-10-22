//
//  PromptItem.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct ProfileIcon: View {
    var appPath: String
    var iconPath: String?
    var size: CGFloat = 24

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: appPath)
    }

    var body: some View {
        if let iconPath, let profileImage = NSImage(contentsOfFile: iconPath) {
            Image(nsImage: profileImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .overlay(alignment: .bottomTrailing) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: size * 0.55, height: size * 0.55)
                        .offset(x: size * 0.15, y: size * 0.15)
                }
        } else {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}
