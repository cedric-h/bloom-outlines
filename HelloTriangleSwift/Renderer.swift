import Metal
import MetalKit
import Foundation
import simd

class Renderer: NSObject {
    let device: MTLDevice
    var pipelineState: MTLRenderPipelineState
    var commandQueue: MTLCommandQueue
    var viewportSize: simd_uint2 = vector2(0, 0)

    private var vertices = [Vertex]()

    init(metalKitView: MTKView) throws {
        let device = metalKitView.device!

        /* { --- make pipeline state --- */
            let library = device.makeDefaultLibrary()!
            let descriptor = MTLRenderPipelineDescriptor()
            /* without sampleCount line, your geometry will be pixelated. (enables MSAA) */
            descriptor.vertexFunction                  = library.makeFunction(name: "vertexShader")
            descriptor.fragmentFunction                = library.makeFunction(name: "fragmentShader")
            descriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
            descriptor.depthAttachmentPixelFormat      = metalKitView.depthStencilPixelFormat
            descriptor.sampleCount                     = metalKitView.sampleCount
            self.pipelineState = (try? device.makeRenderPipelineState(descriptor: descriptor))!
        /* } --- make pipeline state --- */

        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        super.init()
    }
    
    func pan(delta: CGPoint) {
        print(delta)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let buffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let encoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        /* { ---  make vertices --- */
            self.vertices = [
                Vertex(pos: SIMD4<Float>([-0.5, -0.5, 0.0, 1.0]), color: SIMD4<Float>([1.0, 0.0, 0.0, 1.0])),
                Vertex(pos: SIMD4<Float>([ 0.0,  1.0, 0.0, 1.0]), color: SIMD4<Float>([0.0, 1.0, 0.0, 1.0])),
                Vertex(pos: SIMD4<Float>([ 0.5, -0.5, 0.0, 1.0]), color: SIMD4<Float>([0.0, 0.0, 1.0, 1.0]))
            ]
        /* } --- make vertices */

        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(viewportSize.x),
            height: Double(viewportSize.y),
            znear: -1.0, zfar: 1.0
        ));
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices,
                               length: MemoryLayout<Vertex>.stride * vertices.count,
                               index: Int(VertexInputIndexVertices.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
