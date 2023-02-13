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
    //Questa classe mi serve solo per visualizzare sull'iPhone in che posizione ho la testa
    //Accrocchio

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
    
    
    // Funzione per convertire radianti i gradi -> Mi serve per provare a convertire da quternions a euler
    func radiansToDegress(radians: Float32) -> Float32 {
            return radians * 180 / (Float32.pi)
    }
    
    func update(withFaceAnchor faceAnchor: ARFaceAnchor)
    {
        
        let headPose = SetHeadPose(pose: "-", x:0.0, y:0.0)
        //let x = faceAnchor.lookAtPoint.x  // lookAtFace mi da la pos sguardo: se sposto la testa a destra ma                                            guardando centralmente mi dirà comunque che sto guardando al centro
        //let y = faceAnchor.lookAtPoint.y
        let x = faceAnchor.transform.columns.2.x
        let y = faceAnchor.transform.columns.2.y
        
    
        //let x0 = faceAnchor.transform.columns.0.x
        //let y0 = faceAnchor.transform.columns.0.y
        
        //print("colonna 0, x: \(x0), y: \(y0)")

        var gaze:String = ""
        var yawApprox = getYawFaceAnchor(x: x)
        
        //print("X:\(x)")
       // print("Y:\(y)")
        
    
        
        // Pitch - ↑↓
        if(y > 0.1)
        {
            gaze = "up"
        }
        else if(y < -0.35)
        {
            gaze = "down"
        }
        else
        {
            gaze = "center"
        }
        
        // Yaw - ←→
        if(x >= 0.1)
        {
            gaze += "-right"
        }
        else if(x < -0.1)
        {
            gaze += "-left"
        }
        else
        {
            gaze += "-center"
        }
        //print(gaze)
        //headPose.pose = gaze // Tutte le pos: centro, su, giù ecc...
        headPose.pose = yawApprox // Solo yaw
        headPose.x = x
        headPose.y = y
        headPose.setGlobal()
    }
    
    
    func convertQuaternionsToEuler()
    {
        // PROVA: Convertire quaternion in euler
        /*
        
        let qw = sqrt(1 + faceAnchor.transform.columns.0.x + faceAnchor.transform.columns.1.y + faceAnchor.transform.columns.2.z) / 2.0
        let qx = (faceAnchor.transform.columns.2.y - faceAnchor.transform.columns.1.z) / (qw * 4.0)
        let qy = (faceAnchor.transform.columns.0.z - faceAnchor.transform.columns.2.x) / (qw * 4.0)
        let qz = (faceAnchor.transform.columns.1.x - faceAnchor.transform.columns.0.y) / (qw * 4.0)
        
        // Deduce euler angles
        // yaw (z-axis rotation)
        let siny = +2.0 * (qw * qz + qx * qy)
        let cosy = +1.0 - 2.0 * (qy * qy + qz * qz)
        let yaw = radiansToDegress(radians:atan2(siny, cosy))
        
        // pitch (y-axis rotation)
        let sinp = +2.0 * (qw * qy - qz * qx)
        var pitch: Float
        if abs(sinp) >= 1 {
            pitch = radiansToDegress(radians:copysign(Float.pi / 2, sinp))
        } else {
            pitch = radiansToDegress(radians:asin(sinp))
        }
        // roll (x-axis rotation)
        let sinr = +2.0 * (qw * qx + qy * qz)
        let cosr = +1.0 - 2.0 * (qx * qx + qy * qy)
        let roll = radiansToDegress(radians:atan2(sinr, cosr))
         */
    }
    
    func getYawFaceAnchor(x:Float) -> String
    {
        var yawApprox = ""
        // Yaw - ←→
        if(x >= -0.15 && x <= 0.15)
        {
            yawApprox = "center"
        }
        else if(x > 0.15 && x < 0.40)
        {
            yawApprox = "right-15-40"
        }
        else if(x >= 0.40 && x < 0.80)
        {
            yawApprox = "right-40-80"
        }
        else if(x < -0.15 && x >= -0.40)
        {
            yawApprox = "left-15-40"
        }
        else if(x < -0.40 && x >= -0.80)
        {
            yawApprox = "left-40-80"
        }
        
        return yawApprox
    }
}
