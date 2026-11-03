//
//  MetalRenderer.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import MetalKit
import CoreVideo

/// Vertex structure matching Metal shader definitions
struct MirrorVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
}

/// Renderer responsible for drawing CVPixelBuffers efficiently using Metal.
public final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    // MARK: - Observable Metrics

    public var currentFps: Double = 0.0
    public var frameCount: Int = 0
    public var videoSize: CGSize = .zero
    public var renderedViewportRect: CGRect = .zero

    // MARK: - Metal Core

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    // MARK: - State & Synchronization

    private var currentPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    // FPS Calculation State
    private var lastFpsCalculationTime: TimeInterval = 0
    private var framesSinceLastCalculation: Int = 0

    // Screenshots & Recording
    private var pendingScreenshotCompletion: ((NSImage?) -> Void)?

    // MARK: - Shaders Source

    private let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                  constant VertexIn *vertices [[buffer(0)]]) {
        VertexOut out;
        out.position = float4(vertices[vertexID].position, 0.0, 1.0);
        out.texCoord = vertices[vertexID].texCoord;
        return out;
    }

    // Bi-Planar NV12 (Y + CbCr) to RGB conversion
    fragment float4 fragmentShaderNV12(VertexOut in [[stage_in]],
                                      texture2d<float, access::sample> yTexture [[texture(0)]],
                                      texture2d<float, access::sample> uvTexture [[texture(1)]],
                                      sampler colorSampler [[sampler(0)]]) {
        float y = yTexture.sample(colorSampler, in.texCoord).r;
        float2 uv = uvTexture.sample(colorSampler, in.texCoord).rg - float2(0.5, 0.5);

        // BT.709 conversion matrix
        float r = y + 1.5748 * uv.y;
        float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
        float b = y + 1.8556 * uv.x;

        return float4(r, g, b, 1.0);
    }
    """

    // MARK: - Initialization

    public override init() {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        self.device = metalDevice
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue.")
        }
        self.commandQueue = queue

        super.init()

        setupTextureCache()
        setupPipeline()
    }

    private func setupTextureCache() {
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: metalShaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShaderNV12")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to initialize Metal render pipeline: \(error)")
        }
    }

    // MARK: - Frame Feeding

    public func feedPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        bufferLock.lock()
        self.currentPixelBuffer = pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        bufferLock.unlock()

        DispatchQueue.main.async {
            self.videoSize = CGSize(width: width, height: height)
        }
    }

    // MARK: - Screenshot Capture

    public func captureScreenshot(completion: @escaping (NSImage?) -> Void) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard let pixelBuffer = currentPixelBuffer else {
            completion(nil)
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        completion(nsImage)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateViewport(viewSize: size)
    }

    public func draw(in view: MTKView) {
        trackFps()

        bufferLock.lock()
        guard let pixelBuffer = currentPixelBuffer else {
            bufferLock.unlock()
            return
        }
        bufferLock.unlock()

        guard let textureCache = textureCache,
              let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Texture plane 0: Luma (Y)
        var yTextureRef: CVMetalTexture?
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            yWidth,
            yHeight,
            0,
            &yTextureRef
        )

        // Texture plane 1: Chroma (UV)
        var uvTextureRef: CVMetalTexture?
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            uvWidth,
            uvHeight,
            1,
            &uvTextureRef
        )

        guard yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
              let yMetalTexture = CVMetalTextureGetTexture(yTextureRef!),
              let uvMetalTexture = CVMetalTextureGetTexture(uvTextureRef!) else {
            renderEncoder.endEncoding()
            return
        }

        // Compute aspect-fit vertices
        let vertices = calculateQuadVertices(viewSize: view.drawableSize, videoWidth: yWidth, videoHeight: yHeight)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBytes(vertices, length: MemoryLayout<MirrorVertex>.stride * vertices.count, index: 0)
        renderEncoder.setFragmentTexture(yMetalTexture, index: 0)
        renderEncoder.setFragmentTexture(uvMetalTexture, index: 1)

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameCount += 1
    }

    // MARK: - Viewport Geometry & Coordinate Calculation

    private func updateViewport(viewSize: CGSize) {
        guard videoSize.width > 0, videoSize.height > 0 else { return }

        let viewAspect = viewSize.width / viewSize.height
        let videoAspect = videoSize.width / videoSize.height

        var rect = CGRect.zero
        if viewAspect > videoAspect {
            // Letterbox horizontally
            let width = viewSize.height * videoAspect
            let x = (viewSize.width - width) / 2.0
            rect = CGRect(x: x, y: 0, width: width, height: viewSize.height)
        } else {
            // Letterbox vertically
            let height = viewSize.width / videoAspect
            let y = (viewSize.height - height) / 2.0
            rect = CGRect(x: 0, y: y, width: viewSize.width, height: height)
        }

        DispatchQueue.main.async {
            self.renderedViewportRect = rect
        }
    }

    private func calculateQuadVertices(viewSize: CGSize, videoWidth: Int, videoHeight: Int) -> [MirrorVertex] {
        guard viewSize.width > 0 && viewSize.height > 0 else {
            return [
                MirrorVertex(position: [-1, -1], texCoord: [0, 1]),
                MirrorVertex(position: [ 1, -1], texCoord: [1, 1]),
                MirrorVertex(position: [-1,  1], texCoord: [0, 0]),
                MirrorVertex(position: [ 1,  1], texCoord: [1, 0])
            ]
        }

        let viewAspect = Float(viewSize.width / viewSize.height)
        let videoAspect = Float(videoWidth) / Float(videoHeight)

        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if viewAspect > videoAspect {
            scaleX = videoAspect / viewAspect
        } else {
            scaleY = viewAspect / videoAspect
        }

        return [
            MirrorVertex(position: [-scaleX, -scaleY], texCoord: [0, 1]),
            MirrorVertex(position: [ scaleX, -scaleY], texCoord: [1, 1]),
            MirrorVertex(position: [-scaleX,  scaleY], texCoord: [0, 0]),
            MirrorVertex(position: [ scaleX,  scaleY], texCoord: [1, 0])
        ]
    }

    private func trackFps() {
        let now = CACurrentMediaTime()
        framesSinceLastCalculation += 1

        if now - lastFpsCalculationTime >= 1.0 {
            let elapsed = now - lastFpsCalculationTime
            let fps = Double(framesSinceLastCalculation) / elapsed
            DispatchQueue.main.async {
                self.currentFps = (fps * 10).rounded() / 10
            }
            lastFpsCalculationTime = now
            framesSinceLastCalculation = 0
        }
    }
}
