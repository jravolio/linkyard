// Records the picker's effects for the README: each one plays in a real picker window over a wallpaper window,
// and both windows are captured as it runs. Run through render-animations.sh.
import AppKit
import SwiftUI

/// Deprecated, but unlike ScreenCaptureKit it can capture the app's own windows without Screen Recording permission.
private let captureWindows = unsafeBitCast(
    dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"),
    to: (@convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?).self
)

private let margin: CGFloat = 44

/// The README art's wallpaper (compose.py), drawn in AppKit.
private final class Wallpaper: NSView {
    override func draw(_ rect: NSRect) {
        NSColor(red: 0.043, green: 0.055, blue: 0.086, alpha: 1).setFill()
        bounds.fill()
        let spots: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: NSColor)] = [
            (0.15, 0.75, 0.5, NSColor(red: 0.18, green: 0.31, blue: 0.58, alpha: 1)),
            (0.85, 0.8, 0.45, NSColor(red: 0.42, green: 0.24, blue: 0.49, alpha: 1)),
            (0.75, 0.05, 0.5, NSColor(red: 0.12, green: 0.42, blue: 0.4, alpha: 1)),
            (0.2, 0.0, 0.4, NSColor(red: 0.54, green: 0.35, blue: 0.17, alpha: 1)),
        ]
        for spot in spots {
            let center = NSPoint(x: bounds.width * spot.x, y: bounds.height * spot.y)
            NSGradient(colors: [spot.color, spot.color.withAlphaComponent(0)])!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: bounds.width * spot.radius, options: [])
        }
    }
}

private func capture(_ window: NSWindow) -> CGImage {
    let screenHeight = NSScreen.screens[0].frame.height
    let frame = window.frame.insetBy(dx: -margin, dy: -margin)
    let rect = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
    let belowAndIncluding: UInt32 = 1 << 2 | 1 << 3, nominalResolution: UInt32 = 1 << 4
    return captureWindows(rect, belowAndIncluding, UInt32(window.windowNumber), nominalResolution)!.takeRetainedValue()
}

private func save(_ image: CGImage, caption: String, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 6
    shadow.shadowColor = .black.withAlphaComponent(0.6)
    let text = NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white, .shadow: shadow,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (rep.size.width - size.width) / 2, y: (margin - size.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, to: path)
}

private func run(for seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@main
enum AnimationRecorder {
    static func main() {
        let out = CommandLine.arguments[1]
        seedDemoSettings(out: out)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)

        let window = BrowserinoWindow()
        window.isReleasedWhenClosed = false
        let picker = NSHostingView(rootView: PromptView(urls: [demoURL], openID: 1))
        picker.safeAreaRegions = []
        window.setPicker(picker)
        let screen = NSScreen.main!.visibleFrame
        let size = picker.fittingSize
        window.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height), display: false)

        let wallpaper = NSWindow(contentRect: window.frame.insetBy(dx: -2 * margin, dy: -2 * margin), styleMask: [.borderless], backing: .buffered, defer: false)
        wallpaper.level = NSWindow.Level(window.level.rawValue - 1)
        wallpaper.contentView = Wallpaper()
        wallpaper.orderFrontRegardless()
        run(for: 0.5)

        var list = ""
        var index = 0
        func frame(_ image: CGImage, _ caption: String, _ duration: Double) {
            index += 1
            let name = String(format: "%04d.png", index)
            save(image, caption: caption, to: "\(out)/\(name)")
            list += "file '\(name)'\nduration \(String(format: "%.4f", duration))\n"
        }

        for effect in PickerAnimation.effects {
            frame(capture(window), effect.title, 0.3)
            let start = CACurrentMediaTime()
            window.orderFront(animation: effect)
            var shots: [(time: Double, image: CGImage)] = []
            while CACurrentMediaTime() - start < effect.effect!.duration + 0.1 {
                shots.append((CACurrentMediaTime() - start, capture(window)))
                run(for: 1.0 / 40)
            }
            for (i, shot) in shots.enumerated() {
                frame(shot.image, effect.title, (i + 1 < shots.count ? shots[i + 1].time : shot.time + 0.025) - shot.time)
            }
            run(for: 0.2)
            frame(capture(window), effect.title, 1.1)
            window.close()
            run(for: 0.3)
        }
        // The concat format needs the last file listed again for its duration to count.
        list += "file '\(String(format: "%04d.png", index))'\n"
        try! list.write(toFile: "\(out)/frames.txt", atomically: true, encoding: .utf8)
    }
}
