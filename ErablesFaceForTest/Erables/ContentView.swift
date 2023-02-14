//
//  ContentView.swift
//  Erables - Version for test and collect results
//
//  Created by Lorenzo Lamazzi on 04/11/22.
//

import CoreML
import SwiftUI
import ESense
import Charts
import Foundation
import UniformTypeIdentifiers

// MessageDocument: Struct to save file
struct MessageDocument: FileDocument {
    
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var message: String

    init(message: String) {
        self.message = message
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        message = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: message.data(using: .utf8)!)
    }
    
}

class Erables: ObservableObject
{
    var name: String
    var manager:ESenseManager? = nil
    var sensorConfig:ESenseConfig?
    @Published var stato = "Not connected"
    @Published var accelerometer:[Double] = [0,0,0] // Data from accelerometer
    @Published var gyroscope:[Double] = [0,0,0] // // Data from gyroscope
    @Published var accelerometer_cal:[Double] = [0,0,0] // Data from accelerometer calibrated
    @Published var gyroscope_cal:[Double] = [0,0,0] // // Data from gyroscope calibrated
    @Published var roll:Double = 0.0
    @Published var pitch:Double = 0.0
    @Published var yaw:Double = 0.0
    @Published var yawMLClass:Double = 0.0
    @Published var yawMLRegress:Double = 0.0
    @Published var yawDLRegress:Double = 0.0
    @Published var kalmanRegGyr:(Double,Double) = (0.0,0.0)
    @Published var kalmanClasReg:(Double,Double) = (0.0,0.0)
    @Published var kalmanClasGyr:(Double,Double) = (0.0,0.0)
    @Published var kalmanDL:(Double,Double) = (0.0,0.0)
    @Published var kalmanAll:(Double,Double) = (0.0,0.0)
    @Published var yawMLMean:Double = 0.0
    @Published var yawDLMean:Double = 0.0
    @Published var yawRegGyr:Double = 0.0
    @Published var data:String = "Yaw ML Regress,Yaw ML Mean,Yaw DL Regress Mean,Kalman ML,Gyro Yaw and Kalman DL,Gyro Yaw,Gyro Yaw and Kalman ML,Ground Truth (/100),Ground Truth,Error\n" //It will be filev .csv (initialize with first row = columns name)
    @Published var predictedHeadPose:String = ""
    
    
    @ObservedObject var global = HeadPose.global // Object to pass and show data to view
    
    let g:Double = 9.81  // Gravitational acceleration
    let MPI:Double = 3.14159265358979323846  // pi-greco
    var iteration:Int = 0  // N° iteration: i need it for calibration stage
    var accX_offset:Double = 0.0  // Offset
    var accY_offset:Double = 0.0
    var accZ_offset:Double = 0.0
    var gyrX_offset:Double = 0.0
    var gyrY_offset:Double = 0.0
    var gyrZ_offset:Double = 0.0
    
    //Kalman
    @Published var kalmanAngleRoll:Double = 0
    @Published var kalmanUncertaintyAngleRoll:Double = 2*2
    @Published var kalmanAnglePitch:Double = 0
    @Published var kalmanUncertaintyAnglePitch:Double = 2*2
    @Published var kalmanOut:[Double] = [0,0]
    //@Published var kalmanAngleYaw:Double = 0
    @Published var kalmanUncertaintyAngleYaw:Double = 2*2
    
    var window_step:Int = 0 // ML window
    var windowReg:[Double] = [0.0]
    var windowRegDL:[Double] = [0.0]
    var gyro_iter:Int = 0
    
    init(name: String)
    {
        self.name = name
    }
    
    // Triggered when "connect" button in pressed
    func startConnection(){
        self.manager = ESenseManager(deviceName: name, listener: self)
        if let m = self.manager {
            print(m.connect(timeout: 60))
        }
    }
    
    
    func setConnected()
    {
        stato = "Connected"
    }
    
    func setConfig()
    {
        // Configuration of Accelerometer and Gyroscpoe
        self.sensorConfig = ESenseConfig.init(accRange: ESenseConfig.AccRange.G_8, gyroRange: ESenseConfig.GyroRange.DEG_500, accLPF: ESenseConfig.AccLPF.BW_5, gyroLPF: ESenseConfig.GyroLPF.BW_5)
    }
    
    // Set public var of Accelerometer, I need it to show in the view
    func setAccelerometer(data: [Double], data_cal: [Double])
    {
        accelerometer[0] = data[0]
        accelerometer[1] = data[1]
        accelerometer[2] = data[2]
        
        accelerometer_cal[0] = data_cal[0]
        accelerometer_cal[1] = data_cal[1]
        accelerometer_cal[2] = data_cal[2]
    }
    
    // Set public var of Gyroscope, I need it to show in the view
    func setGyroscope(data: [Double], data_cal: [Double])
    {
        gyroscope[0] = data[0]
        gyroscope[1] = data[1]
        gyroscope[2] = data[2]
        
        gyroscope_cal[0] = data_cal[0]
        gyroscope_cal[1] = data_cal[1]
        gyroscope_cal[2] = data_cal[2]
    }
    
    // Calculate Roll from Accelerometer
    func calcRollAcc(ax: Double, ay: Double, az: Double) -> Double
    {
        return atan(az / sqrt(ay*ay + ax*ax))*1/(3.142/180)
    }
    
    // Calculate Pitch from Accelerometer
    func calcPitchAcc(ax: Double, ay: Double, az: Double) -> Double
    {
        return -atan(ay/sqrt(az*az+ax*ax))*1/(3.142/180)
    }
    
    
    //Kalman filter implementation
    func Kalman(kalmanAngle:Double, kalmanU:Double, gyro:Double, acc:Double) // kalmanInput=rotation rate=gyro, kalmanMeasurement=accelerometer angle, kalmanState=angolo misurato kalman filter
    {
        var kalmanState:Double = kalmanAngle
        var kalmanUncertainty:Double = kalmanU
        var kalmanGain:Double = 0
        kalmanState += 0.1 * gyro
        kalmanUncertainty += 0.1*0.1*4*4
        kalmanGain = kalmanUncertainty * 1/(1*kalmanUncertainty+3*3)
        kalmanState = kalmanState + kalmanGain*(acc - kalmanState)
        kalmanUncertainty = (1 - kalmanGain) * kalmanUncertainty
        self.kalmanOut[0] = kalmanState // Angolo misurato Kalman
        self.kalmanOut[1] = kalmanUncertainty
    }
     
    
    // Kalman filter implementation version 2
    func Kalman2(kalmanAngle:Double, kalmanU:Double, gyro:Double, acc:Double) ->(kalmanState:Double, kalmanUncertanty:Double)
    {
        var kalmanState:Double = kalmanAngle
        var kalmanUncertainty:Double = kalmanU
        var kalmanGain:Double = 0
        kalmanState += 0.1 * gyro
        kalmanUncertainty += 0.1*0.1*4*4
        kalmanGain = kalmanUncertainty * 1/(1*kalmanUncertainty+3*3)
        kalmanState = kalmanState + kalmanGain*(acc - kalmanState)
        kalmanUncertainty = (1 - kalmanGain) * kalmanUncertainty
        return(kalmanState, kalmanUncertainty)
    }
    
    // ML function to calc pose old version - I don't use it now
    func calcPose()
    {
        do
        {
            
            /* VERSIONE REGRESSORE CON CreateML*/
             let config = MLModelConfiguration()
            
            /*
            ALL Features
            let model = try ErablesRegresNow(configuration: config)
            let prediction = try model.prediction(input: ErablesRegresNowInput(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2], gyrX: gyroscope[0], gyrY: gyroscope[1], gyrZ: gyroscope[2], accX_cal: accelerometer_cal[0], accY_cal: accelerometer_cal[1], accZ_cal: accelerometer_cal[2], gyrX_cal: gyroscope_cal[0], gyrY_cal: gyroscope_cal[1], gyrZ_cal: gyroscope_cal[2], Roll: kalmanAngleRoll, Pitch: kalmanAnglePitch))
            */
            
            //ONLY ACC GYR
            /*
            let model = try ErableRegres13(configuration: config)
            let prediction = try model.prediction(input: ErableRegres13Input(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2], gyrX: gyroscope[0], gyrY: gyroscope[1], gyrZ: gyroscope[2], accX_cal: accelerometer_cal[0], accY_cal: accelerometer_cal[1], accZ_cal: accelerometer_cal[2], gyrX_cal: gyroscope_cal[0], gyrY_cal: gyroscope_cal[1], gyrZ_cal: gyroscope_cal[2],Roll:roll, Pitch:pitch))
        
            yawMLRegress = prediction.Y
    
             // TEST kalman con ML regressor
            kalmanRegGyr = Kalman2(kalmanAngle: kalmanRegGyr.0, kalmanU: kalmanRegGyr.1, gyro: gyroscope_cal[0], acc: prediction.Y*100)
            
            // CLASSIFICATION ONLY CENTER
            let classificatorCenter = try ErablesClassification26Gen(configuration: config)
            let is_center = try classificatorCenter.prediction(input: ErablesClassification26GenInput(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2], gyrX: gyroscope[0], gyrY: gyroscope[1], gyrZ: gyroscope[2]))
            
            print(is_center.pose)
            
            if is_center.pose == "center"
            {
                yaw = 0.0
            }
            else
            {
                yaw = yawMLRegress*100
            }
            
            kalmanAll = Kalman2(kalmanAngle: kalmanAll.0, kalmanU: kalmanAll.1, gyro: gyroscope_cal[0], acc: yaw)
            
            */
            
            
            
        /*
            let classificator = try ErablesClassification26Gen(configuration: config)
            let predicted_pose = try classificator.prediction(input: ErablesClassification26GenInput(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2], gyrX: gyroscope[0], gyrY: gyroscope[1], gyrZ: gyroscope[2]))
            
            print("Pose \(predicted_pose.pose)")
           // For classification... Approssimo yaw sulla base della classe predetta
        
            if predicted_pose.pose == "center"
            {
                yawMLClass = 0.0
            }
            else if predicted_pose.pose == "right-30"
            {
                yawMLClass = 30.0
            }
            else if predicted_pose.pose == "right-45"
            {
                yawMLClass = 45.0
            }
            else if predicted_pose.pose == "right-60"
            {
                yawMLClass = 60.0
            }
            else if predicted_pose.pose == "right-90"
            {
                yawMLClass = 90.0
            }
            else if predicted_pose.pose == "left-30"
            {
                yawMLClass = -30.0
            }
            else if predicted_pose.pose == "left-45"
            {
                yawMLClass = -45.0
            }
            else if predicted_pose.pose == "left-60"
            {
                yawMLClass = -60.0
            }
            else if predicted_pose.pose == "left-90"
            {
                yawMLClass = -90.0
            }
            else
            {
                yawMLClass = yawMLRegress*100
            }
             
            // TEST KALMAN TRA CLASSIFICATOR E REGRESSOR
            kalmanClasGyr = Kalman2(kalmanAngle: kalmanClasGyr.0, kalmanU: kalmanClasGyr.1, gyro: gyroscope_cal[0], acc: yawMLClass)
            
            kalmanClasReg = Kalman2(kalmanAngle: kalmanClasReg.0, kalmanU: kalmanClasReg.1, gyro: yawMLRegress*100, acc: yawMLClass)
            */
         
            
        } catch {
                print("error")
        }
        
        /* Versione regressore con Keras*/
        
        let modelKeras = ErableKeras6()
        
        guard let tensorInput = try? MLMultiArray(shape: [1,14], dataType: .float32) else
        {
            fatalError("Could not create trensorInput")
        }
        
        tensorInput[0] = accelerometer[0] as NSNumber
        tensorInput[1] = accelerometer[1] as NSNumber
        tensorInput[2] = accelerometer[2] as NSNumber
        tensorInput[3] = gyroscope[0] as NSNumber
        tensorInput[4] = gyroscope[1] as NSNumber
        tensorInput[5] = gyroscope[2] as NSNumber
        
        tensorInput[6] = accelerometer_cal[0] as NSNumber
        tensorInput[7] = accelerometer_cal[1] as NSNumber
        tensorInput[8] = accelerometer_cal[2] as NSNumber
        tensorInput[9] = gyroscope_cal[0] as NSNumber
        tensorInput[10] = gyroscope_cal[1] as NSNumber
        tensorInput[11] = gyroscope_cal[2] as NSNumber
        
        tensorInput[12] = kalmanAngleRoll as NSNumber
        tensorInput[13] = kalmanAnglePitch as NSNumber
        
        do
        {
            let prediction = try modelKeras.prediction(dense_input: tensorInput)
            var Y = prediction.Identity[0].doubleValue
            
            
            kalmanDL = Kalman2(kalmanAngle: kalmanDL.0, kalmanU: kalmanDL.1, gyro: gyroscope_cal[0], acc: Y*100)
            
           // print("Prediction Keras: \(Y)")
           // print("Gyroscope: \(gyroscope[0])")
            
            yawDLRegress = kalmanDL.0
            
            
        }
        catch
        {
            fatalError("error")
        }
    }
    
    func MLRegr(){
        do{
            
            let config = MLModelConfiguration()
            let model = try Reg30Gen(configuration: config)
            let prediction = try model.prediction(input: Reg30GenInput(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2], gyrX: gyroscope[0], gyrY: gyroscope[1], gyrZ: gyroscope[2], accX_cal: accelerometer_cal[0], accY_cal: accelerometer_cal[1], accZ_cal: accelerometer_cal[2], gyrX_cal: gyroscope_cal[0], gyrY_cal: gyroscope_cal[1], gyrZ_cal: gyroscope_cal[2], Roll: kalmanAngleRoll, Pitch: kalmanAnglePitch))
            yawMLRegress = prediction.Y
        } catch {
                print("error")
        }
    }
    
    /*
    func MLClass(){
        do{
            
            let config = MLModelConfiguration()
            let model = try LeftCenRight(configuration: config)
            let prediction = try model.prediction(input: LeftCenRightInput(accX: accelerometer[0], accY: accelerometer[1], accZ: accelerometer[2]))
            
            print(prediction.pose)
            predictedHeadPose = prediction.pose
            
        } catch {
                print("error")
        }
    }
    */
    
    func DLRegr()
    {
        let modelKeras = ErableKeras7()
        
        guard let tensorInput = try? MLMultiArray(shape: [1,14], dataType: .float32) else
        {
            fatalError("Could not create trensorInput")
        }
        
        tensorInput[0] = accelerometer[0] as NSNumber
        tensorInput[1] = accelerometer[1] as NSNumber
        tensorInput[2] = accelerometer[2] as NSNumber
        tensorInput[3] = gyroscope[0] as NSNumber
        tensorInput[4] = gyroscope[1] as NSNumber
        tensorInput[5] = gyroscope[2] as NSNumber
        
        tensorInput[6] = accelerometer_cal[0] as NSNumber
        tensorInput[7] = accelerometer_cal[1] as NSNumber
        tensorInput[8] = accelerometer_cal[2] as NSNumber
        tensorInput[9] = gyroscope_cal[0] as NSNumber
        tensorInput[10] = gyroscope_cal[1] as NSNumber
        tensorInput[11] = gyroscope_cal[2] as NSNumber
        
        tensorInput[12] = kalmanAngleRoll as NSNumber
        tensorInput[13] = kalmanAnglePitch as NSNumber
        
        do
        {
            let prediction = try modelKeras.prediction(dense_input: tensorInput)
            var Y = prediction.Identity[0].doubleValue
            
            
            kalmanDL = Kalman2(kalmanAngle: kalmanDL.0, kalmanU: kalmanDL.1, gyro: gyroscope_cal[0], acc: Y*100)
            
           // print("Prediction Keras: \(Y)")
           // print("Gyroscope: \(gyroscope[0])")
            
            yawDLRegress = kalmanDL.0
            
            
        }
        catch
        {
            fatalError("error")
        }
    }
    
}

// Extension for connection phase
extension Erables:ESenseConnectionListener{
    func onDeviceFound(_ manager: ESenseManager) {
        print("Found")
        
    }

    func onDeviceNotFound(_ manager: ESenseManager) {
        // YOUR CODE HERE
    }

    func onConnected(_ manager: ESenseManager) {
        manager.setDeviceReadyHandler { device in
            manager.removeDeviceReadyHandler()
            // YOUR CODE HERE
            print("Connected")
            self.setConnected()
            
            self.setConfig()
            
            if let config = self.sensorConfig{
                                // set the sensor config to eSense via ESenseManager
                                print(manager.setSensorConfig(config))
                            }
            
            print(manager.registerSensorListener(self, hz: UInt8(50)))
        }
        
    }

    func onDisconnected(_ manager: ESenseManager) {
        // YOUR CODE HERE
    }
}

// Extension for listner
extension Erables:ESenseSensorListener{
    // Triggered when sensor data change
    func onSensorChanged(_ evt: ESenseEvent) {
        if let config = self.sensorConfig {
            var acc  = evt.convertAccToG(config: config)
            var gyro = evt.convertGyroToDegPerSecond(config: config)
            var acc_cal = acc
            var gyro_cal = gyro
            
            /* Manual Calibration
            acc[0] = acc[0] - 0.004842529296875
            acc[1] = acc[1] - 0.11874176025390625
            acc[2] = acc[2] - 0.01297760009765625
            
            gyro[0] = gyro[0] - 1.7908396946564884
            gyro[1] = gyro[1] - 0.170763358778626
            gyro[2] = gyro[2] - 1.0187022900763385
            */
            
            // Calibration phase
            if self.iteration < 200 // Sommo registrazioni sensori
            {
                accX_offset += acc[0]
                accY_offset += acc[1]
                accZ_offset += acc[2]
                
                gyrX_offset += gyro[0]
                gyrY_offset += gyro[1]
                gyrZ_offset += gyro[2]
                
                self.iteration+=1
                print(self.iteration)
                
                print("Acc: \(acc[0]), \(acc[1]), \(acc[2])")
                print("Gyr: \(gyro[0]), \(gyro[1]), \(gyro[2])")
                
            }
            else if self.iteration == 200 // Mean of 200 first values = Offset
            {
                accX_offset /= 200
                accY_offset /= 200
                accZ_offset /= 200
                accX_offset += 1  // X = 1 when erables are worn
                gyrX_offset /= 200
                gyrY_offset /= 200
                gyrZ_offset /= 200
                
                self.iteration+=1
                print("Acc: \(accX_offset), \(accY_offset), \(accZ_offset)")
                print("Gyr: \(gyrX_offset), \(gyrY_offset), \(gyrZ_offset)")
            }

            else //Posso iniziare a raccogliere i dati
            {
                acc_cal[0] -= accX_offset
                acc_cal[1] -= accY_offset
                acc_cal[2] -= accZ_offset
                
                gyro_cal[0] -= gyrX_offset
                gyro_cal[1] -= gyrY_offset
                gyro_cal[2] -= gyrZ_offset
                
                self.setAccelerometer(data: acc, data_cal: acc_cal)
                self.setGyroscope(data: gyro, data_cal: gyro_cal)
                
                var time = Date() // get date and time
                 
                // Compute Roll and Pitch from Accelerometer
                let rollAcc = self.calcRollAcc(ax: acc_cal[0], ay: acc_cal[1], az: acc_cal[2])
                let pitchAcc = self.calcPitchAcc(ax: acc_cal[0], ay: acc_cal[1], az: acc_cal[2])
        
                //Roll
                Kalman(kalmanAngle: kalmanAngleRoll, kalmanU: kalmanUncertaintyAngleRoll, gyro: gyro_cal[1], acc: rollAcc)
                kalmanAngleRoll = kalmanOut[0]
                kalmanUncertaintyAngleRoll = kalmanOut[1]
                //Pitch
                Kalman(kalmanAngle: kalmanAnglePitch, kalmanU: kalmanUncertaintyAnglePitch, gyro: -gyro_cal[2], acc: pitchAcc)
                kalmanAnglePitch = kalmanOut[0]
                kalmanUncertaintyAnglePitch = kalmanOut[1]
                
            
                //MLClass()
                MLRegr()
                DLRegr()
                
                if window_step >= 10
                {
                    window_step = 0
                    windowReg.removeFirst()
                    windowReg.removeLast()
                    var sum = windowReg.reduce(0,+)
                    var len = windowReg.count
                    yawMLMean = Double(sum)/Double(len)
                    yawMLMean *= 100
                    windowReg.removeAll()
                    
                    //DL
                    windowRegDL.removeFirst()
                    windowRegDL.removeLast()
                    var sumDL = windowRegDL.reduce(0,+)
                    var lenDL = windowRegDL.count
                    yawDLMean = Double(sumDL)/Double(lenDL)
                    windowRegDL.removeAll()
                    
                }
                else
                {
                    windowReg.append(yawMLRegress)
                    window_step += 1
                    
                    //DL
                    windowRegDL.append(yawDLRegress)
                }
                
                kalmanRegGyr = Kalman2(kalmanAngle: kalmanRegGyr.0, kalmanU: kalmanRegGyr.1, gyro: gyro_cal[0]/15, acc: yawMLMean)
                kalmanAll = Kalman2(kalmanAngle: kalmanAll.0, kalmanU: kalmanAll.1, gyro: gyro_cal[0]/15, acc: yawDLMean) // Ho usato kalmanAll per fare test... devo cambiare nome nel caso
                
                // Use Gyro for 100 iterazioni, then reset with ML/DL value
                if gyro_iter >= 100
                {
                    //yawRegGyr = kalmanRegGyr.0
                    //yawRegGyr = yawMLMean
                    yawRegGyr = kalmanAll.0 // versione DL
                    gyro_iter = 0
                }
                else
                {
                    yawRegGyr += (gyroscope_cal[0]/15)
                    gyro_iter += 1
                }
                
                yaw += (gyroscope_cal[0]/15)
                
                var error = abs((Double(global.y)*100)) - abs(yaw) // Error on gyroscope mesurements
                
                /* Test reset yaw con dati acellerometro
            
                if acc[2] >= accZ_offset - 0.05 && acc[2] <= accZ_offset + 0.05
                {
                    print("Center")
                    yaw = 0.0
                }
                else
                {
                    print("Altro")
                    yaw += (gyroscope_cal[0]/18)
                }
                 */
                self.data += "  -\(yawMLRegress),\(yawMLMean),\(yawDLMean),\(kalmanRegGyr.0),\(kalmanAll.0),\(yaw),\(yawRegGyr),\(global.y),\(global.y*100),\(error)\n"
            }
        }
    }
}

class HeadPose: ObservableObject
{
    static let global = HeadPose(pose: "-", x: 0.0, y: 0.0)
    @Published var pose:String
    @Published var x:Float
    @Published var y:Float
    
    init(pose: String, x:Float, y:Float)
    {
        self.pose = pose
        self.x = x
        self.y = y
    }
}

struct ContentView: View {
    @ObservedObject var erable = Erables(name: "eSense-0182")  // Check Erable name with App like LightBlue
    @ObservedObject var global = HeadPose.global
    @State private var document: MessageDocument = MessageDocument(message: "")  // Doc for data collection
    @State private var isExporting: Bool = false
    @State private var fileName:String = "results"  // file name
    
    var body: some View {
        ZStack(alignment: .top)
        {
            ARViewContainer()
                .ignoresSafeArea(.all)
            
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.white.opacity(0.8))
                .frame(width: 330, height: 150)
            
            LinearGradient(gradient: Gradient(colors: [.red,.blue]), startPoint: .topLeading, endPoint: .bottomTrailing).frame(width: 30, height: 30).cornerRadius(1)
                .rotation3DEffect(.degrees(erable.yaw), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(erable.kalmanAnglePitch), axis: (x: 1, y: 0, z: 0)) // Pitch
    
            Text("X: \(global.x, specifier: "%.2f")")
                .offset(x:-100)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            Text("Y: \(global.y, specifier: "%.2f")")
                .offset(x:+100)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            //Roll, Pitch, Yaw
            Text("Roll: \(erable.kalmanAngleRoll, specifier: "%.2f") Pitch: \(erable.kalmanAnglePitch, specifier: "%.2f") Yaw: \(erable.yaw, specifier: "%.2f")")
                .offset(y: +30)
                .foregroundColor(.accentColor)
            // Gyroscope
            Text("yawML: \(erable.yawMLRegress, specifier: "%.2f") yawDL: \(erable.yawDLRegress, specifier: "%.2f")")
                .offset(y: +60)
                .foregroundColor(.accentColor)
            // Button to connect earables
            Button("Connect")
            {
              let _ = self.erable.startConnection()
            }
            .offset(x: -100, y:+90)
            Text(self.erable.stato)
                .offset(y:+90)
                .foregroundColor(.cyan)
            Button("Save")
            {
                self.document.message = self.erable.data
                isExporting.toggle()
            }
            .offset(y:+120)
            
        }
        .fileExporter(
              isPresented: $isExporting,
              document: document,
              contentType: .plainText,
              defaultFilename: self.fileName
          ) { result in
              if case .success = result {
                  // Handle success.
              } else {
                  // Handle failure.
              }
          }
    }
  
    // Function to create and manage data
    private func documentDirectory() -> String {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask,true)
        return documentDirectory[0]
    }
    
    private func append(toPath path: String,withPathComponent pathComponent: String) -> String? {
        if var pathURL = URL(string: path) {
            pathURL.appendPathComponent(pathComponent)
            
            return pathURL.absoluteString
        }
        
        return nil
    }
    
    private func read(fromDocumentsWithFileName fileName: String) {
        guard let filePath = self.append(toPath: self.documentDirectory(),
                                         withPathComponent: fileName) else {
                                            return
        }
        
        do {
            let savedString = try String(contentsOfFile: filePath)
            
            print(savedString)
        } catch {
            print("Error reading saved file")
        }
    }
    
    private func save(text: String,
                      toDirectory directory: String,
                      withFileName fileName: String) {
        guard let filePath = self.append(toPath: directory,
                                         withPathComponent: fileName) else {
            return
        }
        
        do {
            try text.write(toFile: filePath,
                           atomically: true,
                           encoding: .utf8)
        } catch {
            print("Error", error)
            return
        }
        
        print("Save successful")
    }
}



