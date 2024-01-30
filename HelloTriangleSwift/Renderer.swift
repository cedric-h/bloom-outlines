import Metal
import MetalKit
import Foundation
import MetalPerformanceShaders
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
    var cameraZoom: Float = 1.0

    /* needed for outline -> renderTarget pipeline */
    var outlineRawTarget: MTLTexture
    var outlineBloomTarget: MTLTexture
#if MSAA
    var outlineRawTargetMSAA: MTLTexture
    var outlineBloomTargetMSAA: MTLTexture
#endif
    var outlineRenderPassDesc: MTLRenderPassDescriptor
    var outlinePipelineState: MTLRenderPipelineState
    var cpu_lineCount: Int = 0
    var cpu_vbuf = [OutlineVertex]()
    var cpu_ibuf = [UInt16]()
    var gpu_lineCount: Int = 0
    var gpu_vbuf: MTLBuffer!
    var gpu_ibuf: MTLBuffer!
    
    /* needed for blur pass */
    var fullscreenPipelineState: MTLRenderPipelineState

    init(metalKitView: MTKView) throws {
        func makeOutlineRenderTarget(device: MTLDevice, metalKitView: MTKView) -> MTLTexture {
            let texDesc = MTLTextureDescriptor()
            texDesc.width          = (metalKitView.currentDrawable?.texture.width)!
            texDesc.height         = (metalKitView.currentDrawable?.texture.height)!
            texDesc.depth          = 1
            texDesc.textureType    = .type2D
            texDesc.sampleCount    = 1
            texDesc.pixelFormat    = metalKitView.colorPixelFormat

            texDesc.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite]

            return device.makeTexture(descriptor: texDesc)!
        }
        
#if MSAA
        func makeOutlineRenderTargetMSAA(device: MTLDevice, metalKitView: MTKView) -> MTLTexture {
            let texDesc = MTLTextureDescriptor()
            texDesc.width          = (metalKitView.currentDrawable?.texture.width)!
            texDesc.height         = (metalKitView.currentDrawable?.texture.height)!
            texDesc.depth          = 1
            texDesc.textureType    = .type2DMultisample
            texDesc.sampleCount    = metalKitView.sampleCount
            texDesc.pixelFormat    = metalKitView.colorPixelFormat

            texDesc.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite]

            return device.makeTexture(descriptor: texDesc)!
        }
#endif

        func makeOutlineRenderPassDescriptor(
            device: MTLDevice,
            metalKitView: MTKView,
            rawTarget: MTLTexture,
            rawTargetMSAA: MTLTexture,
            bloomTarget: MTLTexture,
            bloomTargetMSAA: MTLTexture
        ) -> MTLRenderPassDescriptor {
            let desc = MTLRenderPassDescriptor()
            
            desc.depthAttachment = metalKitView.currentRenderPassDescriptor!.depthAttachment
            desc.depthAttachment.loadAction = .clear
            desc.depthAttachment.storeAction = .store
            desc.stencilAttachment = metalKitView.currentRenderPassDescriptor!.stencilAttachment
            desc.stencilAttachment.loadAction = .clear
            desc.stencilAttachment.storeAction = .store
            
            #if MSAA
                desc.colorAttachments[0].texture = rawTargetMSAA
                desc.colorAttachments[0].resolveTexture = rawTarget
                desc.colorAttachments[0].storeAction = .storeAndMultisampleResolve
            #else
                desc.colorAttachments[0].texture = rawTarget
                desc.colorAttachments[0].storeAction = .store
            #endif
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

            #if MSAA
                desc.colorAttachments[1].texture = bloomTargetMSAA
                desc.colorAttachments[1].resolveTexture = bloomTarget
                desc.colorAttachments[1].storeAction = .storeAndMultisampleResolve
            #else
                desc.colorAttachments[1].texture = bloomTarget
                desc.colorAttachments[1].storeAction = .store
            #endif
            desc.colorAttachments[1].loadAction = .clear
            desc.colorAttachments[1].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
            
            return desc
        }

        func makeOutlinePipelineState(
            device: MTLDevice,
            metalKitView: MTKView,
            rawTargetMSAA: MTLTexture,
            bloomTargetMSAA: MTLTexture
        ) -> MTLRenderPipelineState {

            let library = device.makeDefaultLibrary()!
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction                  = library.makeFunction(name: "outlineVertexShader")
            descriptor.fragmentFunction                = library.makeFunction(name: "outlineFragmentShader")
            descriptor.colorAttachments[0].pixelFormat = rawTargetMSAA.pixelFormat
            descriptor.colorAttachments[1].pixelFormat = bloomTargetMSAA.pixelFormat
            
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            descriptor.colorAttachments[1].isBlendingEnabled = true
            descriptor.colorAttachments[1].rgbBlendOperation = .add
            descriptor.colorAttachments[1].alphaBlendOperation = .add
            descriptor.colorAttachments[1].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[1].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[1].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[1].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            assert(rawTargetMSAA.sampleCount == bloomTargetMSAA.sampleCount)
            descriptor.sampleCount           = rawTargetMSAA.sampleCount

            return (try? device.makeRenderPipelineState(descriptor: descriptor))!
        }

        func makeFullscreenPipelineState(device: MTLDevice, metalKitView: MTKView) -> MTLRenderPipelineState {
            let library = device.makeDefaultLibrary()!
            let descriptor = MTLRenderPipelineDescriptor()

            /* without sampleCount line, your geometry will be pixelated. (enables MSAA) */
            descriptor.vertexFunction                  = library.makeFunction(name: "fullscreenVertexShader")
            descriptor.fragmentFunction                = library.makeFunction(name: "fullscreenFragmentShader")
            descriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
            descriptor.depthAttachmentPixelFormat      = metalKitView.depthStencilPixelFormat
            descriptor.sampleCount                     = metalKitView.sampleCount
            return (try? device.makeRenderPipelineState(descriptor: descriptor))!
        }

        device = metalKitView.device!
        commandQueue = device.makeCommandQueue()!

        fullscreenPipelineState = makeFullscreenPipelineState(device: device, metalKitView: metalKitView)

        outlineRawTarget = makeOutlineRenderTarget(device: device, metalKitView: metalKitView)
        outlineBloomTarget = makeOutlineRenderTarget(device: device, metalKitView: metalKitView)
#if MSAA
        outlineRawTargetMSAA = makeOutlineRenderTargetMSAA(device: device, metalKitView: metalKitView)
        outlineBloomTargetMSAA = makeOutlineRenderTargetMSAA(device: device, metalKitView: metalKitView)
        outlineRenderPassDesc = makeOutlineRenderPassDescriptor(
            device: device,
            metalKitView: metalKitView,
            rawTarget: outlineRawTarget,
            rawTargetMSAA: outlineRawTargetMSAA,
            bloomTarget: outlineBloomTarget,
            bloomTargetMSAA: outlineBloomTargetMSAA
        )
        outlinePipelineState = makeOutlinePipelineState(
            device: device,
            metalKitView: metalKitView,
            rawTargetMSAA: outlineRawTargetMSAA,
            bloomTargetMSAA: outlineBloomTargetMSAA
        )
#else
        outlineRenderPassDesc = makeOutlineRenderPassDescriptor(
            device: device,
            metalKitView: metalKitView,
            rawTarget: outlineRawTarget,
            rawTargetMSAA: outlineRawTarget,
            bloomTarget: outlineBloomTarget,
            bloomTargetMSAA: outlineBloomTarget
        )
        outlinePipelineState = makeOutlinePipelineState(
            device: device,
            metalKitView: metalKitView,
            rawTargetMSAA: outlineRawTarget,
            bloomTargetMSAA: outlineBloomTarget
        )
#endif

        super.init()
        
        allocateBuffers(device: device, newLineCapacity: 128)
    }

    func allocateBuffers(device: MTLDevice, newLineCapacity: Int) {
        self.gpu_lineCount = newLineCapacity
        self.gpu_vbuf = device.makeBuffer(
            length: MemoryLayout<OutlineVertex>.stride * newLineCapacity * 4,
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

    func tap(pos: CGPoint) {
        let halfHeight = CGFloat(UIScreen.main.bounds.size.height)/2.0
        self.cameraZoom *= (pos.y < halfHeight) ? 0.8 : 1.2;
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
    
    /* it's useful to have this as a function (instead of just appending to array) because we have 
     * a single place to change Index Size, (can do UInt32 for more than 65k vertices), or debug issues */
    func ibufCpuQuad(_ v0: UInt16, _ v1: UInt16, _ v2: UInt16, _ v3: UInt16) {
        self.cpu_ibuf.append(contentsOf: [v0, v1, v2, v2, v1, v3])
    }
    
    func drawCpuLine(from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: Float, color: SIMD4<Float>) {
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
            mvp = simd_mul(mvp, .init(translate: [0.0, 0.0, -6.0 * cameraZoom]))
            mvp = simd_mul(mvp, simd_mul(
                simd_float4x4.init(yRot: -self.cameraRotation.x),
                simd_float4x4.init(xRot:  self.cameraRotation.y)
            ));
        /* } ---  make mvp from scratch --- */

        var screen_a = simd_mul(mvp, SIMD4<Float>([a.x, a.y, a.z, 1.0]));
        var screen_b = simd_mul(mvp, SIMD4<Float>([b.x, b.y, b.z, 1.0]));

        /* without this block, lines will get smaller
         * the farther you are from the camera */
        if true {
            /* here we account for the "perspective divide" that the GPU does under the hood;
             * without this, the lines will not stay the same thickness when the camera is far away */
            if screen_a.w > 0 {
                screen_a.x /= screen_a.w;
                screen_a.y /= screen_a.w;
                screen_a.z /= screen_a.w;
                screen_a.w = 1;
            }
            if screen_b.w > 0 {
                screen_b.x /= screen_b.w;
                screen_b.y /= screen_b.w;
                screen_b.z /= screen_b.w;
                screen_b.w = 1;
            }
        }

        /* perpendicular to "a -> b" */
        let nx = -(screen_b.y - screen_a.y);
        let ny =  (screen_b.x - screen_a.x) * aspect_ratio;
        
        /* normalize nx/ny for constant thickness */
        let tlen = (nx * nx + ny * ny).squareRoot() / (thickness * 0.5);
        let tx = nx / tlen;
        let ty = ny / tlen * aspect_ratio;
        
        ibufCpuQuad(
            UInt16(self.cpu_vbuf.count + 0),
            UInt16(self.cpu_vbuf.count + 1),
            UInt16(self.cpu_vbuf.count + 2),
            UInt16(self.cpu_vbuf.count + 3)
        )

        #if false
        screen_a.x -= ty*0.5;
        screen_a.y += tx*0.5;
        
        screen_b.x += ty*0.5;
        screen_b.y -= tx*0.5;
        #endif

        self.cpu_vbuf.append(OutlineVertex(pos: SIMD4<Float>(screen_a.x + tx, screen_a.y + ty, screen_a.z, screen_a.w), color: color))
        self.cpu_vbuf.append(OutlineVertex(pos: SIMD4<Float>(screen_a.x - tx, screen_a.y - ty, screen_a.z, screen_a.w), color: color))
        self.cpu_vbuf.append(OutlineVertex(pos: SIMD4<Float>(screen_b.x + tx, screen_b.y + ty, screen_b.z, screen_b.w), color: color))
        self.cpu_vbuf.append(OutlineVertex(pos: SIMD4<Float>(screen_b.x - tx, screen_b.y - ty, screen_b.z, screen_b.w), color: color))

        self.cpu_lineCount += 1
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let buffer = commandQueue.makeCommandBuffer() else { return }
        
        func drawOutlinesToRenderTarget(buffer: MTLCommandBuffer) {
            self.clearCpuLines();
#if false
            func makeVertices() {
                let color = SIMD4<Float>([0.8, 1.0, 0.9, 1.0])

                /* make 10 "windows" arranged in a circle */
                for i in 0..<10 {
                    let modelX = cos(Float(i) / 10.0 * Float.pi*2) * 5.0
                    let modelY = sin(Float(i) / 10.0 * Float.pi*2) * 5.0
                    
                    /* SIDE_LENGTH doesn't include BORDER_RADIUS, so total square size is sum of these two */
                    let BORDER_RADIUS: Float = 0.35
                    let SIDE_LENGTH: Float = 0.7

                    var firstV: Optional<SIMD3<Float>> = nil
                    var lastV: Optional<SIMD3<Float>> = nil
                    for i in 0..<16 {
                        var p = SIMD2<Float>(
                            cos(Float(i) / 16.0 * Float.pi*2) * BORDER_RADIUS,
                            sin(Float(i) / 16.0 * Float.pi*2) * BORDER_RADIUS
                        );
                        
                        p.x += ((p.x < 0) ? -1 : 1) * SIDE_LENGTH * 0.5
                        p.y += ((p.y < 0) ? -1 : 1) * SIDE_LENGTH * 0.5
                        
                        let v = SIMD3<Float>([modelX + p.x, p.y, modelY])
                        
                        /* connect this point to the last one */
                        if let lv = lastV {
                            self.drawCpuLine(from: v, to: lv, thickness: 0.02, color: color);
                        } else {
                            /* store the first one so we can close the gap at the end */
                            firstV = v
                        }
                        lastV = v
                    }
                    
                    /* close circle */
                    if let a = firstV,
                       let b = lastV {
                        self.drawCpuLine(from: a, to: b, thickness: 0.02, color: color)
                    }
                }
            }
#else
            func makeVertices() {
                for i in 0..<20 {
                    let x = cos(Float(i) / 20.0 * Float.pi*2) * 5.0
                    let y = sin(Float(i) / 20.0 * Float.pi*2) * 5.0

                    let a = SIMD3<Float>([x +  0.7, -0.7, y]);
                    let b = SIMD3<Float>([x + -0.7, -0.7, y]);
                    let c = SIMD3<Float>([x + -0.7,  0.7, y]);
                    let d = SIMD3<Float>([x +  0.7,  0.7, y]);

                    let color = SIMD4<Float>([0.8, 1.0, 0.9, 0.1])
                    let contour = [
                        (a, b),
                        (b, c),
                        (c, d),
                        (d, a),
                    ]
                    
                    var first = true
                    let vertA0 = UInt16(self.cpu_vbuf.count)
                    let vertA1 = UInt16(self.cpu_vbuf.count + 1)
                    for (from, to) in contour {
                        self.drawCpuLine(from: from, to: to, thickness: 0.02, color: color);
                        
                        if first {
                        } else {
                            let v = UInt16(self.cpu_vbuf.count - 6)
                            ibufCpuQuad(v + 0, v + 1, v + 2, v + 3)
                        }
                        
                        first = false
                    }
                    let vertZ0 = UInt16(self.cpu_vbuf.count - 2)
                    let vertZ1 = UInt16(self.cpu_vbuf.count - 1)
                    
                    ibufCpuQuad(vertA0, vertA1, vertZ0, vertZ1)
                }
            }
#endif
        
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: outlineRenderPassDesc) else { return }

            makeVertices()

            encoder.setViewport(MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(viewportSize.x),
                height: Double(viewportSize.y),
                znear: -1.0, zfar: 1.0
            ));
            encoder.setRenderPipelineState(outlinePipelineState)

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
        }
    
        drawOutlinesToRenderTarget(buffer: buffer)

#if false
        let kernel = MPSImageGaussianBlur(device: device, sigma: 15.0)
        kernel.encode(commandBuffer: buffer, inPlaceTexture: &outlineBloomTarget, fallbackCopyAllocator: nil)
#endif

        let renderPassDescriptor = view.currentRenderPassDescriptor!
        let encoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!

        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(viewportSize.x),
            height: Double(viewportSize.y),
            znear: -1.0, zfar: 1.0
        ));
        encoder.setRenderPipelineState(fullscreenPipelineState)

        let fullscreenTriangle = [
            FullscreenVertex(pos: SIMD2<Float>(-1.0,  3.0), uv: SIMD2<Float>(0.0,  2.0)),
            FullscreenVertex(pos: SIMD2<Float>(-1.0, -1.0), uv: SIMD2<Float>(0.0,  0.0)),
            FullscreenVertex(pos: SIMD2<Float>( 3.0, -1.0), uv: SIMD2<Float>(2.0,  0.0))
        ];
        encoder.setVertexBytes(
            fullscreenTriangle,
            length: MemoryLayout<FullscreenVertex>.stride * fullscreenTriangle.count,
            index: 0
        )
        encoder.setFragmentTexture(outlineRawTarget, index: 0)
        encoder.setFragmentTexture(outlineBloomTarget, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
