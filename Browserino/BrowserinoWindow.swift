//
//  BrowserinoWindow.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import Foundation
import AppKit

class BrowserinoWindow: NSPanel {
    static let selectorWidth: CGFloat = 250
    static let selectorHeight: CGFloat = 200

    private var zoomTimer: Timer?

    /// AppKit has no public way to scale a whole window with its shadow; Arc and Dia use this private method.
    /// The transform maps the screen to the window, so drawing the window at scale `s` takes a transform of `1 / s`.
    /// Nil when the method is missing or its signature changed, and Zoom falls back to the system's window animation.
    private static let setTransform: ((NSWindow, CGAffineTransform, CGPoint) -> Void)? = {
        let selector = NSSelectorFromString("_setTransformForAnimation:anchorPoint:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "v80@0:8{CGAffineTransform=dddddd}16{CGPoint=dd}64"
        else {
            return nil
        }

        typealias Function = @convention(c) (NSWindow, Selector, CGAffineTransform, CGPoint) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return { window, transform, anchor in function(window, selector, transform, anchor) }
    }()
    
    public convenience init() {
        self.init(
            contentRect: .init(x: 0, y: 0, width: Self.selectorWidth, height: Self.selectorHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        self.isOpaque = false
        self.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        self.isMovable = false
    }
    
    /// Animates the window itself, so the system shadow and rounded corners move with the picker.
    func orderFront(animation: PickerAnimation) {
        resetScale()

        if isVisible {
            // Another link arrived while the picker is open or still animating in: settle it where it was just placed.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                animator().setFrame(frame, display: true)
                animator().alphaValue = 1
            }
            makeKeyAndOrderFront(nil)
            return
        }

        animationBehavior = .none

        switch animation {
        case .none:
            alphaValue = 1
            makeKeyAndOrderFront(nil)
        case .fade, .glow:
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            animate(duration: 0.3) { $0.animator().alphaValue = 1 }
        case .zoom:
            alphaValue = 0
            if let setTransform = Self.setTransform {
                startZoom(setTransform)
                makeKeyAndOrderFront(nil)
                animate(duration: Self.zoomDuration) { $0.animator().alphaValue = 1 }
            } else {
                // The system's document-window animation zooms in from about 98%.
                animationBehavior = .documentWindow
                makeKeyAndOrderFront(nil)
                animate(duration: 0.2) { $0.animator().alphaValue = 1 }
            }
        case .rise:
            let target = frame
            setFrameOrigin(NSPoint(x: target.minX, y: target.minY - 24))
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            animate(duration: 0.3) {
                $0.animator().setFrame(target, display: true)
                $0.animator().alphaValue = 1
            }
        }
    }

    static let zoomDuration: TimeInterval = 0.25

    /// Scale from 95% to 100% with no overshoot, so the picker lands once and stops; nil once it's done.
    /// Ease-out quint stays within 0.1% of the curve the other animations use.
    static func zoomScale(at time: TimeInterval) -> CGFloat? {
        guard time < zoomDuration else {
            return nil
        }

        let progress = 1 - pow(1 - time / zoomDuration, 5)
        return 0.95 + 0.05 * progress
    }

    private func startZoom(_ setTransform: @escaping (NSWindow, CGAffineTransform, CGPoint) -> Void) {
        let anchor = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let start = CACurrentMediaTime()
        setTransform(self, CGAffineTransform(scaleX: 1 / 0.95, y: 1 / 0.95), anchor)

        let framesPerSecond = (screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60
        let timer = Timer(timeInterval: 1 / Double(framesPerSecond), repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            if let scale = Self.zoomScale(at: CACurrentMediaTime() - start) {
                setTransform(self, CGAffineTransform(scaleX: 1 / scale, y: 1 / scale), anchor)
            } else {
                self.resetScale()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        zoomTimer = timer
    }

    private func resetScale() {
        guard let zoomTimer else {
            return
        }

        zoomTimer.invalidate()
        self.zoomTimer = nil
        Self.setTransform?(self, .identity, .zero)
    }

    private func animate(duration: TimeInterval, _ changes: (BrowserinoWindow) -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            changes(self)
        }
    }

    override func close() {
        // Only opening animates: the picker should be gone the moment a browser is chosen.
        animationBehavior = .none
        resetScale()
        super.close()
    }

    func deactivateDelay() {
        self.hidesOnDeactivate = false
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            // A shortcut can open a browser and close the picker within these 100 ms.
            if self.isVisible {
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.makeKeyAndOrderFront(nil)
            }
            self.hidesOnDeactivate = true
        }
    }
}

extension NSPanel {
    open override var canBecomeKey: Bool { true }
}
