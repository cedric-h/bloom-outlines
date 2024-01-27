//
//  MetalViewController.swift
//  HelloTriangleSwift
//
//  Created by Peter Edmonston on 10/7/18.
//  Copyright © 2018 com.peteredmonston. All rights reserved.
//

import MetalKit
import UIKit

class MetalViewController: UIViewController {
    
    private var renderer: Renderer?

    @IBOutlet weak var metalView: MTKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        metalView.device = MTLCreateSystemDefaultDevice()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panMetalView(_:)))
        metalView.addGestureRecognizer(pan)
        
        do {
            renderer = try Renderer(metalKitView: metalView)
            metalView.delegate = renderer
        } catch {
            print("Error creating renderer: \(error.localizedDescription)")
        }
    }
    
    @objc func panMetalView(_ gr: UIPanGestureRecognizer) {
        renderer?.pan(delta: gr.velocity(in: self.view))
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        renderer?.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
    }
}

