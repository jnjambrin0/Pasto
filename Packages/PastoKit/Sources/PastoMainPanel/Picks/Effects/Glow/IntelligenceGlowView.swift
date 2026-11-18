import AppKit
import Metal
import os
import PastoFoundation
import QuartzCore
import simd

/// The glow behind the panel's toolbar and strip that shows what suggestions are doing: an ember
/// by the suggestions button while they are offered, a burst that crosses the panel while they
/// are worked out, a band round the panel while they are on show.
///
/// The motion — springs, drift, lights, pointer, swell — comes from `GlowState` with the numbers
/// in `GlowTuning`; the picture is drawn by the shader in `GlowShaderSource`. It is added to what
/// is under it, lets every click through, and draws nothing where Metal is unavailable.
final class IntelligenceGlowView: FrameDrivenView {
    var scene = GlowScene.closed
    /// Where the reveal wave starts, in this (flipped) view's coordinates; read every frame.
    var revealOrigin: () -> CGPoint = { .zero }
    /// The animated icon's excitement, 0…1; read every frame.
    var excitement: () -> Float = { 0 }

    private let cornerRadius: CGFloat
    private let tuning = GlowTuning.standard
    private var state: GlowState
    private let lightHues: [SIMD4<Float>]

    private let metalLayer = CAMetalLayer()
    private let device: (any MTLDevice)?
    private let queue: (any MTLCommandQueue)?
    private let sampler: (any MTLSamplerState)?
    private var pipeline: (any MTLRenderPipelineState)?
    /// A uniform placeholder until the real noise has been generated.
    private var noiseTexture: (any MTLTexture)?
    private var preparation: Task<Void, Never>?

    private let log = Log.logger(.panel)

    /// - Parameter cornerRadius: The radius of the glass the glow fills.
    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        state = GlowState(tuning: tuning)
        lightHues = GlowState.lightHues(tuning.hues)
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        sampler = device.flatMap(Self.makeSampler)
        super.init(frame: .zero)

        layerContentsRedrawPolicy = .never
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        // The glow lights up what is under it rather than covering it.
        metalLayer.compositingFilter = "additionCompositing"

        if let device {
            noiseTexture = Self.makeNoiseTexture(device: device, samples: [128], width: 1, height: 1, depth: 1)
            prepare(device: device)
        }
    }

    isolated deinit {
        preparation?.cancel()
    }

    override func makeBackingLayer() -> CALayer {
        metalLayer
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Drawable size

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    // MARK: - Frames

    override func render(now: CFTimeInterval, dt: Float, motion: Float) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        state.show(scene, at: now, motion: motion, tuning: tuning)
        let target = tuning.scene(state.sceneShown)
        state.stepSprings(toward: target.targets(isDark: isDark), arrival: target.arrival, dt: dt)
        state.advanceNoise(dt: dt, motion: motion)
        state.placeLights(on: tuning.orbits)
        state.followPointer(to: GlowState.pointerTarget(location: pointerLocation, size: bounds.size), dt: dt, lag: tuning.pointerLag)

        guard bounds.width > 0, bounds.height > 0 else { return }
        draw(state.uniforms(
            at: now,
            size: bounds.size,
            scale: metalLayer.contentsScale,
            cornerRadius: cornerRadius,
            origin: revealOrigin(),
            excitement: excitement(),
            tuning: tuning
        ))
    }

    /// Polled every frame: no event monitor is needed for a panel that is not key.
    private var pointerLocation: CGPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    private func draw(_ uniforms: GlowUniforms) {
        guard let pipeline, let noiseTexture, let sampler, let queue,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        state.lights.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        lightHues.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.setFragmentTexture(noiseTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Metal resources

    /// Compiles the shader and generates the noise in the background; until both are ready the
    /// glow draws nothing, or flames with no flicker.
    private func prepare(device: any MTLDevice) {
        preparation = Task(priority: .utility) { [weak self, log] in
            do {
                let pipeline = try await Self.makePipeline(device: device)
                self?.pipeline = pipeline
            } catch {
                log.error("The suggestions glow could not be prepared: \(error)")
                return
            }
            let samples = await GlowNoise.makeSamples()
            guard !Task.isCancelled else { return }
            self?.noiseTexture = Self.makeNoiseTexture(
                device: device, samples: samples, width: GlowNoise.width, height: GlowNoise.height, depth: GlowNoise.depth
            )
        }
    }

    /// Compiles the shader: premultiplied alpha over a transparent drawable.
    @concurrent
    private nonisolated static func makePipeline(device: any MTLDevice) async throws -> any MTLRenderPipelineState {
        let library = try await device.makeLibrary(source: GlowShaderSource.code, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: GlowShaderSource.vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: GlowShaderSource.fragmentFunction)
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try await device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeSampler(device: any MTLDevice) -> (any MTLSamplerState)? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.rAddressMode = .repeat
        return device.makeSamplerState(descriptor: descriptor)
    }

    private static func makeNoiseTexture(
        device: any MTLDevice, samples: [UInt8], width: Int, height: Int, depth: Int
    ) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Unorm
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        samples.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, width, height, depth),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width,
                bytesPerImage: width * height
            )
        }
        return texture
    }
}
