import Metal
import MetalKit
import Foundation
import simd

extension simd_float4x4 {
    static func perspective(aspect: Float, fovy: Float, near: Float, far: Float) -> Self {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange

        let P: SIMD4<Float> = [xScale, 0, 0, 0]
        let Q: SIMD4<Float> = [0, yScale, 0, 0]
        let R: SIMD4<Float> = [0, 0, zScale, -1]
        let S: SIMD4<Float> = [0, 0, wzScale, 0]

        return simd_float4x4([P, Q, R, S])
    }

    @inlinable init(translate t: SIMD3<Float>) {
        self = simd_float4x4(columns: (
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [t.x, t.y, t.z, 1]
        ))
    }
}


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
            let aspect_ratio = Float(viewportSize.x) / Float(viewportSize.y)
            var m = simd_float4x4.perspective(
                aspect: aspect_ratio,
                fovy: (45 * Float.pi) / 180,
                near: 0.1,
                far: 100.0
            )
            m = simd_mul(m, .init(translate: [0.0, 0.0, -6.0]))

            self.vertices = [
                Vertex(pos: simd_mul(m, SIMD4<Float>([-0.5, -0.5, 0.0, 1.0])), color: SIMD4<Float>([1.0, 0.0, 0.0, 1.0])),
                Vertex(pos: simd_mul(m, SIMD4<Float>([ 0.0,  1.0, 0.0, 1.0])), color: SIMD4<Float>([0.0, 1.0, 0.0, 1.0])),
                Vertex(pos: simd_mul(m, SIMD4<Float>([ 0.5, -0.5, 0.0, 1.0])), color: SIMD4<Float>([0.0, 0.0, 1.0, 1.0]))
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
