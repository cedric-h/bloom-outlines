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

    @inlinable init(xRot rad: Float) {
      let s = sin(rad);
      let c = cos(rad);
      self = simd_float4x4(columns: (
          [ 1,  0, 0, 0],
          [ 0,  c, s, 0],
          [ 0, -s, c, 0],
          [ 0,  0, 0, 1]
      ));
    }

    @inlinable init(yRot rad: Float) {
      let s = sin(rad);
      let c = cos(rad);
      self = simd_float4x4(columns: (
          [ c, 0, -s, 0],
          [ 0, 1,  0, 0],
          [ s, 0,  c, 0],
          [ 0, 0,  0, 1]
      ));
    }

    @inlinable init(zRot rad: Float) {
      let s = sin(rad);
      let c = cos(rad);
      self = simd_float4x4(columns: (
           [ c, s, 0, 0],
           [-s, c, 0, 0],
           [ 0, 0, 1, 0],
           [ 0, 0, 0, 1]
        ));
    }
}


class Renderer: NSObject {
    /* needed to function as independent renderer */
    let device: MTLDevice
    var commandQueue: MTLCommandQueue

    /* needed to construct mvp */
    var viewportSize: simd_uint2 = vector2(0, 0)
    var cameraRotation: SIMD2<Float> = vector2(0, 0)

    /* needed for outline pipeline */
    var pipelineState: MTLRenderPipelineState
    var cpu_lineCount: Int = 0
    var cpu_vbuf = [Vertex]()
    var cpu_ibuf = [UInt16]()
    var gpu_lineCount: Int = 0
    var gpu_vbuf: MTLBuffer!
    var gpu_ibuf: MTLBuffer!

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
        
        allocateBuffers(device: device, newLineCapacity: 128)
    }

    func allocateBuffers(device: MTLDevice, newLineCapacity: Int) {
        self.gpu_lineCount = newLineCapacity
        self.gpu_vbuf = device.makeBuffer(
            length: MemoryLayout<SIMD3<Float>>.stride * newLineCapacity * 4,
            options: MTLResourceOptions.cpuCacheModeWriteCombined
        )
        self.gpu_ibuf = device.makeBuffer(
            length: MemoryLayout<UInt16>.stride * newLineCapacity * 6,
            options: MTLResourceOptions.cpuCacheModeWriteCombined
        )
    }

    func pan(delta: CGPoint) {
      self.cameraRotation.x -= Float(delta.x)*0.0004;
      self.cameraRotation.y -= Float(delta.y)*0.0004;
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)
    }

    func clearCpuLines() {
        self.cpu_ibuf = []
        self.cpu_vbuf = []
        self.cpu_lineCount = 0
    }
    
    func drawCpuLine(from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: Float) {

        var mvp: simd_float4x4;
        var aspect_ratio: Float;
        /* { ---  make mvp from scratch --- */
            aspect_ratio = Float(viewportSize.x) / Float(viewportSize.y)
            mvp = simd_float4x4.perspective(
                aspect: aspect_ratio,
                fovy: (45 * Float.pi) / 180,
                near: 0.1,
                far: 100.0
            )
            mvp = simd_mul(mvp, .init(translate: [0.0, 0.0, -6.0]))
            mvp = simd_mul(mvp, simd_mul(
                simd_float4x4.init(xRot: -self.cameraRotation.y),
                simd_float4x4.init(yRot:  self.cameraRotation.x)
            ).inverse);
        /* } ---  make mvp from scratch --- */

        let screen_a = simd_mul(mvp, SIMD4<Float>([a.x, a.y, a.z, 1.0]));
        let screen_b = simd_mul(mvp, SIMD4<Float>([b.x, b.y, b.z, 1.0]));
        
        /* perpendicular to "a -> b" */
        let nx = -(screen_b.y - screen_a.y);
        let ny =  (screen_b.x - screen_a.x) * aspect_ratio;
        
        /* normalize nx/ny for constant thickness */
        let tlen = (nx * nx + ny * ny).squareRoot() / (thickness * 0.5);
        let tx = nx / tlen;
        let ty = ny / tlen * aspect_ratio;
        
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 0))
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 1))
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 2))
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 2))
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 1))
        self.cpu_ibuf.append(UInt16(self.cpu_vbuf.count + 3))

        let red = SIMD4<Float>([1.0, 0.0, 0.0, 1.0])
        self.cpu_vbuf.append(Vertex(pos: SIMD4<Float>(screen_a.x + tx, screen_a.y + ty, screen_a.z, screen_a.w), color: red))
        self.cpu_vbuf.append(Vertex(pos: SIMD4<Float>(screen_a.x - tx, screen_a.y - ty, screen_a.z, screen_a.w), color: red))
        self.cpu_vbuf.append(Vertex(pos: SIMD4<Float>(screen_b.x + tx, screen_b.y + ty, screen_b.z, screen_b.w), color: red))
        self.cpu_vbuf.append(Vertex(pos: SIMD4<Float>(screen_b.x - tx, screen_b.y - ty, screen_b.z, screen_b.w), color: red))

        self.cpu_lineCount += 1
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let buffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let encoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        /* { ---  make vertices --- */
            let a = SIMD3<Float>([ 0.7, -0.7, 0.0]);
            let b = SIMD3<Float>([-0.7, -0.7, 0.0]);
            let c = SIMD3<Float>([-0.7,  0.7, 0.0]);
            let d = SIMD3<Float>([ 0.7,  0.7, 0.0]);

            self.clearCpuLines();
            self.drawCpuLine(from: a, to: b, thickness: 0.09);
            self.drawCpuLine(from: b, to: c, thickness: 0.09);
            self.drawCpuLine(from: c, to: d, thickness: 0.09);
            self.drawCpuLine(from: d, to: a, thickness: 0.09);
        /* } --- make vertices */

        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(viewportSize.x),
            height: Double(viewportSize.y),
            znear: -1.0, zfar: 1.0
        ));
        encoder.setRenderPipelineState(pipelineState)

        if self.gpu_lineCount < self.cpu_lineCount {
            self.allocateBuffers(
                device: device,
                newLineCapacity: self.cpu_lineCount * 2
            )
        }
        self.gpu_vbuf.contents().copyMemory(from: self.cpu_vbuf, byteCount: self.gpu_vbuf.length)
        self.gpu_ibuf.contents().copyMemory(from: self.cpu_ibuf, byteCount: self.gpu_ibuf.length)

        encoder.setVertexBuffer(self.gpu_vbuf, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: self.cpu_lineCount * 6,
            indexType: .uint16,
            indexBuffer: self.gpu_ibuf,
            indexBufferOffset: 0
        )

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
