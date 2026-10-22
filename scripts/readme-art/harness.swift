// Renders Linkyard's real views with a demo setup for the README. Run through render-ui.sh.
import AppKit
import SwiftUI

private func emojiIcon(_ glyph: String, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let text = NSAttributedString(string: glyph, attributes: [.font: NSFont.systemFont(ofSize: 200)])
    let size = text.size()
    text.draw(at: NSPoint(x: 128 - size.width / 2, y: 128 - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

private func seedDemoSettings(out: String) {
    let icons = out
    for (name, glyph) in [("personal", "🏠"), ("work", "💼"), ("northwind", "🌲"), ("sideproject", "🚀")] {
        emojiIcon(glyph, to: "\(icons)/\(name).png")
    }
    func profile(_ name: String, dir: String? = nil, space: String? = nil, icon: String) -> ChromeProfile {
        ChromeProfile(directoryName: dir ?? name, displayName: name, arcSpaceID: space, iconPath: "\(icons)/\(icon).png")
    }
    let d = UserDefaults.standard
    let apps = URL(fileURLWithPath: "/Applications")
    let browsers = ["Dia.app", "Zen.app", "Arc.app", "Google Chrome.app"].map { apps.appendingPathComponent($0, isDirectory: true) }
    d.set(browsers.rawValue, forKey: "browsers")
    d.set([URL]().rawValue, forKey: "hiddenBrowsers")
    d.set([profile("Personal", icon: "personal"), profile("Work", icon: "work"), profile("Northwind", icon: "northwind"), profile("Side Project", icon: "sideproject")].rawValue, forKey: "diaProfiles")
    d.set([profile("Personal", icon: "personal"), profile("Work", icon: "work"), profile("Northwind", icon: "northwind")].rawValue, forKey: "zenProfiles")
    d.set([profile("Personal", dir: "Default", space: "DEMO-PERSONAL", icon: "personal"), profile("Work", dir: "Profile 1", space: "DEMO-WORK", icon: "work")].rawValue, forKey: "arcProfiles")
    d.set([profile("Work", dir: "Profile 1", icon: "work"), profile("Side Project", dir: "Profile 2", icon: "sideproject")].rawValue, forKey: "chromeProfiles")
    d.set(["Personal", "Work", "Northwind", "Side Project"].rawValue, forKey: "pickerGroupOrder")
    let dia = apps.appendingPathComponent("Dia.app", isDirectory: true)
    let zen = apps.appendingPathComponent("Zen.app", isDirectory: true)
    d.set([
        Rule(regex: ".*", app: dia, profileDirectory: "Work", sourceApp: apps.appendingPathComponent("Slack.app", isDirectory: true), sourceWindowTitleRegex: "Acme"),
        Rule(regex: ".*", app: dia, profileDirectory: "Northwind", sourceApp: apps.appendingPathComponent("Microsoft Teams.app", isDirectory: true)),
        Rule(regex: ".*", app: dia, profileDirectory: "Personal", sourceApp: apps.appendingPathComponent("Telegram.app", isDirectory: true)),
        Rule(regex: "github\\.com/acme/.*", app: zen, profileDirectory: "Work"),
    ].rawValue, forKey: "rules")
}

private func render<V: View>(_ view: V, size: CGSize?, to path: String) {
    let host = NSHostingView(rootView: view)
    let frameSize = size ?? host.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: frameSize), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: frameSize)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let scale: CGFloat = 3
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frameSize.width * scale), pixelsHigh: Int(frameSize.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = frameSize
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("\(path) \(Int(frameSize.width))x\(Int(frameSize.height))")
}

@main
enum DemoHarness {
    static func main() {
        let out = CommandLine.arguments[1]
        seedDemoSettings(out: out)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        render(PromptView(urls: [URL(string: "https://github.com/acme/website/pull/42")!]), size: nil, to: "\(out)/picker.png")
        render(ProfilesTab().padding(.top, 12).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 1240), to: "\(out)/settings-profiles.png")
        render(RulesTab().padding(.top, 12).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 400), to: "\(out)/settings-rules.png")
    }
}
