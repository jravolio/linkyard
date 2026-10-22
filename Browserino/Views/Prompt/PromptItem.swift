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
        if let iconPath, let profileImage = ProfileImageCache.image(atPath: iconPath) {
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

/// Profile logos are read from disk once; the picker redraws on every key press.
enum ProfileImageCache {
    private static let images = NSCache<NSString, NSImage>()

    static func image(atPath path: String) -> NSImage? {
        if let image = images.object(forKey: path as NSString) {
            return image
        }

        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        images.setObject(image, forKey: path as NSString)
        return image
    }
}
