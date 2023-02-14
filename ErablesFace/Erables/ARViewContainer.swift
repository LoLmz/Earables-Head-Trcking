//
//  ARViewContainer.swift
//  BodyTracking
//
//  Created by Lorenzo Lamazzi on 28/11/22.
//

import SwiftUI
import ARKit
import RealityKit


private let faceAnchor = AnchorEntity()

class SetHeadPose
{
    @ObservedObject var global = HeadPose.global
    var pose:String
    var x:Float
    var y:Float
    
    init(pose: String, x:Float, y:Float)
    {
        self.pose = pose
        self.x = x
        self.y = y
    }
    
    func setGlobal()
    {
        global.pose = self.pose
        global.x = self.x
        global.y = self.y
    }
}

struct ARViewContainer: UIViewRepresentable
{
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: true)
        
        arView.setupForFaceTracking()
        arView.scene.addAnchor(faceAnchor)
        
        return arView
    }
    func updateUIView(_ uiView: ARView, context: Context) {
        
    }
}

extension ARView: ARSessionDelegate
{
    func setupForFaceTracking()
    {
        let configuration = ARFaceTrackingConfiguration()
        self.session.run (configuration)
        self.session.delegate = self
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        if let faceAnchor = anchors.first as? ARFaceAnchor
        {
            update(withFaceAnchor: faceAnchor)
        }
        
    }
    
    func update(withFaceAnchor faceAnchor: ARFaceAnchor)
    {
        let headPose = SetHeadPose(pose: "-", x:0.0, y:0.0)
        let x = faceAnchor.transform.eulerAngles.x
        let y = faceAnchor.transform.eulerAngles.y
            
        var yawApprox = getYaw(y: y)
        //var only_center = getOnlyCenter(y: y)
        //var pitch_yaw = getPitchYaw(x: x, y: y)
        
        //headPose.pose = gaze // All poses: center, up, down ecc...
        headPose.pose = yawApprox // Only yaw
        //headPose.pose = only_center // Only center
        headPose.x = x
        headPose.y = y
        headPose.setGlobal()
    }
    
    
    func getPitchYaw(x: Float, y: Float) -> String
    {
        var gaze:String = ""
        // Pitch - ↑↓
        if(x > 0.1)
        {
            gaze = "up"
        }
        else if(x < -0.35)
        {
            gaze = "down"
        }
        else
        {
            gaze = "center"
        }
        
        // Yaw - ←→
        if(y >= 0.1)
        {
            gaze += "-right"
        }
        else if(y < -0.1)
        {
            gaze += "-left"
        }
        else
        {
            gaze += "-center"
        }
        
        return gaze
    }
    
    
    func getYaw(y:Float) -> String
    {
        var yawApprox = ""
        // Yaw - ←→
        if(y >= -0.05 && y <= 0.05)
        {
            yawApprox = "center"
        }
        else if(y >= 0.25 && y <= 0.35)
        {
            yawApprox = "right-30"
        }
        else if(y >= 0.40 && y <= 0.50)
        {
            yawApprox = "right-45"
        }
        else if(y >= 0.55 && y <= 0.65)
        {
            yawApprox = "right-60"
        }
        else if(y >= 0.85 && y <= 0.95)
        {
            yawApprox = "right-90"
        }
        
        else if(y <= -0.25 && y >= -0.35)
        {
            yawApprox = "left-30"
        }
        else if(y <= -0.40 && y >= -0.50)
        {
            yawApprox = "left-45"
        }
        else if(y <= -0.55 && y >= -0.65)
        {
            yawApprox = "left-60"
        }
        else if(y <= -0.85 && y >= -0.95)
        {
            yawApprox = "left-90"
        }
        else
        {
            yawApprox = "other"
        }
        
        return yawApprox
    }
    
    //Test: only center
    //-> try to reset gyro yaw when head is at center position
    func getOnlyCenter(y:Float) -> String
    {
        var pos = ""
        if(y >= -0.15 && y <= 0.15)
        {
            pos = "center"
        }
        else
        {
            pos = "other"
        }
        return pos
    }
}

// Extension to convert Quaternions to Euler angles
extension simd_float4x4 {
    // Note to ourselves: This is the implementation from AREulerAnglesFromMatrix. // Apple comment
    // Ideally, this would be RealityKit API when this sample gets published. // Apple comment
    var eulerAngles: SIMD3<Float> {
        var angles: SIMD3<Float> = .zero
        
        if columns.2.y >= 1.0 - .ulpOfOne * 10 {
            angles.x = -.pi / 2
            angles.y = 0
            angles.z = atan2(-columns.0.z, -columns.1.z)
        } else if columns.2.y <= -1.0 + .ulpOfOne * 10 {
            angles.x = -.pi / 2
            angles.y = 0
            angles.z = atan2(columns.0.z, columns.1.z)
        } else {
            angles.x = asin(-columns.2.y)
            angles.y = atan2(columns.2.x, columns.2.z)
            angles.z = atan2(columns.0.y, columns.1.y)
        }
        
        return angles
    }
}
