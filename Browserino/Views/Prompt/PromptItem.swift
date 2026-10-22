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

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    private var appIcon: NSImage {
        AppIconCache.icon(forApp: appPath, size: size, scale: displayScale, colorScheme: colorScheme)
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

/// Workspace icons are rendered by Icon Services over XPC every time they're drawn, so the picker draws bitmaps rendered once.
/// Only used from views on the main thread.
enum AppIconCache {
    private struct Key: Hashable {
        let path: String
        /// An app updated in place gets a new bundle, and with it a new icon to render.
        let modified: Date?
        let size: CGFloat
        let scale: CGFloat
        let isDark: Bool
    }

    private static var images: [Key: NSImage] = [:]

    static func icon(forApp path: String, size: CGFloat, scale: CGFloat, colorScheme: ColorScheme) -> NSImage {
        let modified = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let key = Key(path: path, modified: modified, size: size, scale: scale, isDark: colorScheme == .dark)
        if let image = images[key] {
            return image
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        var cgImage: CGImage?
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: transform])
        }
        guard let cgImage else {
            return icon
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        images[key] = image
        return image
    }
}
