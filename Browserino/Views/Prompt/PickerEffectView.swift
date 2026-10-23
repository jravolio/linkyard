//
//  PickerEffectView.swift
//  Browserino
//

import AppKit
import Metal
import QuartzCore

/// Matches `EffectUniforms` in PickerEffects.metal.
struct EffectUniforms {
    var size: SIMD2<Float>
    var raw: Float
    var duration: Float
    var radius: Float
    var scale: Float
    var dark: Float
    var mode: Int32
}

final class PickerEffectRenderer {
    static let shared = PickerEffectRenderer()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// Builds the pipeline off the main thread, so the first effect doesn't pay for it while a link waits.
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            _ = shared
        }
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "effectVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "effectFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func texture(from image: CGImage) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: image.width, height: image.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            return nil
        }

        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: image.bytesPerRow)
        return texture
    }

    @discardableResult
    func draw(_ uniforms: EffectUniforms, snapshot: MTLTexture, overlay: MTLTexture, mask: MTLTexture,
              present: [MTLDrawable] = []) -> MTLCommandBuffer? {
        let pass = MTLRenderPassDescriptor()
        for (index, target) in [overlay, mask].enumerated() {
            pass.colorAttachments[index].texture = target
            pass.colorAttachments[index].loadAction = .dontCare
            pass.colorAttachments[index].storeAction = .store
        }
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }

        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        present.forEach(buffer.present)
        buffer.commit()
        return buffer
    }
}

/// Plays an effect over the picker: the shader draws the content from a snapshot and reveals a copy of the
/// picker's blurred background, so the live picker can take over unchanged when the effect ends.
final class PickerEffectView: NSView {
    private let renderer: PickerEffectRenderer
    private let snapshot: MTLTexture
    private var uniforms: EffectUniforms
    private let overlayLayer = CAMetalLayer()
    private let maskLayer = CAMetalLayer()
    private var start: CFTimeInterval = 0
    private var timer: Timer?
    private var revealPicker: (() -> Void)?
    private var completion: (() -> Void)?

    /// The snapshot draws images slightly differently from the live picker, so the effect fades out over it at the end.
    private static let handoff: TimeInterval = 0.12

    init?(effect animation: PickerAnimation, content: NSView) {
        guard let (mode, duration) = animation.effect,
              let renderer = PickerEffectRenderer.shared,
              let image = Self.snapshot(of: content),
              let snapshot = renderer.texture(from: image)
        else {
            return nil
        }

        let scale = CGFloat(snapshot.width) / content.bounds.width
        self.renderer = renderer
        self.snapshot = snapshot
        uniforms = EffectUniforms(
            size: SIMD2(Float(snapshot.width), Float(snapshot.height)),
            raw: 0,
            duration: Float(duration),
            radius: Float(BrowserinoWindow.cornerRadius * scale),
            scale: Float(scale),
            dark: content.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0,
            mode: mode
        )
        super.init(frame: content.frame)
        autoresizingMask = [.width, .height]

        let background = NSView(frame: bounds)
        background.autoresizingMask = [.width, .height]
        background.wantsLayer = true
        let blur = BlurredView.makeEffectView()
        blur.frame = background.bounds
        blur.autoresizingMask = [.width, .height]
        background.addSubview(blur)
        background.layer?.mask = maskLayer
        addSubview(background)

        let overlay = NSView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.layer = overlayLayer
        overlay.wantsLayer = true
        addSubview(overlay)

        for layer in [overlayLayer, maskLayer] {
            layer.device = renderer.device
            layer.pixelFormat = .bgra8Unorm
            layer.isOpaque = false
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.frame = bounds
            layer.contentsScale = scale
            layer.drawableSize = CGSize(width: snapshot.width, height: snapshot.height)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Leaves out the blurred background, which the effect reveals separately.
    private static func snapshot(of view: NSView) -> CGImage? {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }

        let backgrounds = view.descendants(of: NSVisualEffectView.self).filter { !$0.isHidden }
        backgrounds.forEach { $0.isHidden = true }
        defer { backgrounds.forEach { $0.isHidden = false } }

        context.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        return context.makeImage()
    }

    /// Clicks and keys go to the picker underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Fresh layers show nothing and an empty mask hides the background, which is also every effect's first frame.
    func play(revealPicker: @escaping () -> Void, completion: @escaping () -> Void) {
        self.revealPicker = revealPicker
        self.completion = completion
        start = CACurrentMediaTime()
        timer = .everyFrame(on: window?.screen) { [weak self] in
            guard let self else {
                return
            }
            let duration = Double(self.uniforms.duration)
            let raw = (CACurrentMediaTime() - self.start) / duration
            guard raw < 1 else {
                self.finish()
                return
            }
            let fade = 1 - Self.handoff / duration
            if raw >= fade {
                self.revealPicker?()
                self.revealPicker = nil
                self.alphaValue = (1 - raw) / (1 - fade)
            }
            self.render(raw: raw)
        }
    }

    func finish() {
        timer?.invalidate()
        timer = nil
        revealPicker = nil
        let completion = completion
        self.completion = nil
        completion?()
    }

    private func render(raw: Double) {
        guard let overlay = overlayLayer.nextDrawable(), let mask = maskLayer.nextDrawable() else {
            return
        }
        uniforms.raw = Float(raw)
        renderer.draw(uniforms, snapshot: snapshot, overlay: overlay.texture, mask: mask.texture, present: [overlay, mask])
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view in (view as? T).map { [$0] } ?? view.descendants(of: type) }
    }
}
