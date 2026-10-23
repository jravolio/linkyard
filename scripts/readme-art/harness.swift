// Renders Linkyard's real views with a demo setup for the README. Run through render-ui.sh.
import AppKit
import SwiftUI

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
    writePNG(rep, to: path)
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
        render(PromptView(urls: [demoURL]), size: nil, to: "\(out)/picker.png")
        render(ProfilesTab().padding(.top, 12).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 1240), to: "\(out)/settings-profiles.png")
        render(RulesTab().padding(.top, 12).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 350), to: "\(out)/settings-rules.png")
    }
}
