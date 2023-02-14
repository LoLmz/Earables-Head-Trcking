//
//  Erables - App to collect data
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
    @Published var data:String = "time,accX,accY,accZ,gyrX,gyrY,gyrZ,accX_cal,accY_cal,accZ_cal,gyrX_cal,gyrY_cal,gyrZ_cal,Roll,Pitch,pose,X,Y\n" //It will be filev .csv (initialize with first row = columns name)
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
    @Published var kalmanAngleYaw:Double = 0
    @Published var kalmanUncertaintyAngleYaw:Double = 2*2
    
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
        return atan(az / sqrt(ay*ay + ax*ax))*1/(3.142/180)  // V1 cuffia indossata (sembra essere corretto)
        //return atan2(az,sqrt(ay*ay+ax*ax))*1/(3.142/180)
        //return atan(ay / sqrt(ax*ax + az*az))*1/(3.142/180) // Versione video
    }
    
    // Calculate Pitch from Accelerometer
    func calcPitchAcc(ax: Double, ay: Double, az: Double) -> Double
    {
        //return -atan(ay/sqrt(az*az+ax*ax))*1/(3.142/180)  // In questo modo sarebbe (?) per averlo corretto con cuff indossata
        //return -atan2(ay,sqrt(az*az+ax*ax))*1/(3.142/180)
        //return -atan(ax/sqrt(ay*ay+az*az))*1/(3.142/180) // Versione video
        return -atan(ay/sqrt(az*az+ax*ax))*1/(3.142/180)
    }
    
    
    // Kalman filter implementation
    func Kalman(kalmanAngle:Double, kalmanU:Double, gyro:Double, acc:Double)
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
                accX_offset += 1
                gyrX_offset /= 200
                gyrY_offset /= 200
                gyrZ_offset /= 200
                
                self.iteration+=1
                print("Acc: \(accX_offset), \(accY_offset), \(accZ_offset)")
                print("Gyr: \(gyrX_offset), \(gyrY_offset), \(gyrZ_offset)")
            }

            else
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
                
                // Updata data to write on file
                self.data += "\(time),\(acc[0]),\(acc[1]),\(acc[2]),\(gyro[0]),\(gyro[1]),\(gyro[2]),\(acc_cal[0]),\(acc_cal[1]),\(acc_cal[2]),\(gyro_cal[0]),\(gyro_cal[1]),\(gyro_cal[2]),\(kalmanAngleRoll), \(kalmanAnglePitch),\(global.pose),\(global.x),\(global.y)\n"
                
            }
        }
    }
}

class HeadPose: ObservableObject
{
    //Questa classe mi serve solo per visualizzare sull'iPhone in che posizione ho la testa
    //Accrocchio
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
    @State private var fileName:String = "train"  // file name
    
    var body: some View {
        ZStack(alignment: .top)
        {
            ARViewContainer()
                .ignoresSafeArea(.all)
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.white.opacity(0.8))
                .frame(width: 330, height: 150)
            
            Text(global.pose) // Head pose ARKit
                .fontWeight(.heavy)
                .foregroundColor(.indigo)
            Text("X: \(global.x, specifier: "%.2f")")
                .offset(x:-100)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            Text("Y: \(global.y, specifier: "%.2f")")
                .offset(x:+100)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            // Print Accelerometer
            Text("acc x: \(erable.accelerometer[0], specifier: "%.2f") acc y: \(erable.accelerometer[1], specifier: "%.2f") acc z: \(erable.accelerometer[2], specifier: "%.2f")")
                .offset(y: +30)
                .foregroundColor(.accentColor)
            
            // Print Gyroscope
            Text("gyro x: \(erable.gyroscope[0], specifier: "%.2f") gyro y: \(erable.gyroscope[1], specifier: "%.2f") gyro z: \(erable.gyroscope[2], specifier: "%.2f")")
                .offset(y: +60)
                .foregroundColor(.accentColor)
            

            // To connect erables
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
                //print(self.erable.data)
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



