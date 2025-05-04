//
//  ContentView.swift
//  MouseByHead
//
//  Created by yuhua Tang on 2025/5/4.
//
import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @State private var sensitivity: Double = 100
    @State private var selectedCameraIndex: Int = 0
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        VStack {
            // 摄像头预览
            CameraPreview(cameraManager: cameraManager)
               .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 灵敏度设置
            HStack {
                Text("灵敏度:")
                Slider(value: $sensitivity, in: 1...1000, step: 100)
                    .onChange(of: sensitivity) { newValue in
                        cameraManager.sensitivity = Int(newValue)
                    }
                Text("\(Int(sensitivity))")
            }
           .padding()

            // 摄像头选择
            Picker("选择摄像头", selection: $selectedCameraIndex) {
                ForEach(0..<cameraManager.availableCameras.count, id: \.self) { index in
                    Text(cameraManager.availableCameras[index].localizedName)
                        .tag(index)
                }
            }
           .pickerStyle(MenuPickerStyle())
           .onChange(of: selectedCameraIndex) { newIndex in
                cameraManager.selectCamera(at: newIndex)
            }
           .padding()
        }
       .onAppear {
            cameraManager.startSession()
        }
    }
}

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var sensitivity: Int = 10

    var captureSession: AVCaptureSession?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    var sequenceHandler = VNSequenceRequestHandler()
    
    let dataOutputQueue = DispatchQueue(
      label: "video data queue",
      qos: .userInitiated,
      attributes: [],
      autoreleaseFrequency: .workItem)
    
    override init() {
        super.init()
        setupSession()
        setupFaceDetection()
    }

    func setupSession() {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }

        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        availableCameras = discoverySession.devices

        if let firstDevice = availableCameras.first {
            setupInputDevice(firstDevice)
        }

        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput?.setSampleBufferDelegate(self, queue: dataOutputQueue)

        if session.canAddOutput(videoDataOutput!) {
            session.addOutput(videoDataOutput!)
        }
    }

    func setupInputDevice(_ device: AVCaptureDevice) {
        guard let session = captureSession else { return }
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        if let newInput = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(newInput) {
                session.addInput(newInput)
            }
        }
    }

    func startSession() {
        captureSession?.startRunning()
    }

    func selectCamera(at index: Int) {
        if index < availableCameras.count {
            setupInputDevice(availableCameras[index])
        }
    }

    func handleFaceObservation(observation: VNFaceObservation) {
        let  yaw = observation.yaw?.doubleValue ?? 0
        let pitch = observation.pitch?.doubleValue ?? 0
        let roll = observation.roll?.doubleValue ?? 0
//        print("roll:\(roll),yaw:\(yaw),pitch:\(pitch)")
        if pitch > 0.1 {
            // 低头
            print("[pencilCool]  down")
            scrollMouse(by: sensitivity)
        } else if pitch < -0.1 {
            // 抬头
            print("[pencilCool]  up")
            scrollMouse(by: -sensitivity)
        }
    }

    func scrollMouse(by delta: Int) {
//        let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(delta), wheel2:  Int32(delta), wheel3: 0)
//        scrollEvent?.setIntegerValueField(CGEventField.eventSourceUserData, value: 1)
//        scrollEvent?.post(tap: .cghidEventTap)
        scrollMouse(onPoint: CGPoint(x: 1000, y: 1000), xLines: delta, yLines: delta)
    }
   
      func scrollMouse(onPoint point: CGPoint, xLines: Int, yLines: Int) {
        if #available(OSX 10.13, *) {
            guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: CGScrollEventUnit.line, wheelCount: 2, wheel1: Int32(yLines), wheel2: Int32(xLines), wheel3: 0) else {
                return
            }
            scrollEvent.setIntegerValueField(CGEventField.eventSourceUserData, value: 1)
            
            // 需要辅助功能权限
              let accessEnabled = AXIsProcessTrustedWithOptions(nil)
              if accessEnabled {
                  scrollEvent.post(tap: CGEventTapLocation.cghidEventTap)
              } else {
                  print("Accessibility access is not enabled. Please grant permission in System Settings > Privacy & Security > Accessibility.")
                  // 你可以引导用户去开启权限
                  // NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
              }
            

        } else {
            // scroll event is not supported for macOS older than 10.13
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // 1
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          return
        }

        guard let faceDetectionRequest = faceDetectionRequest else { return }
//        print("pencilCool has buffer")
        let imageRequestHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
              do {
                  try imageRequestHandler.perform([faceDetectionRequest])
              } catch {
                  print("Error performing face detection request: \(error)")
              }
        
//        // 3
//        do {
//          try sequenceHandler.perform(
//            [faceDetectionRequest],
//            on: imageBuffer,
//            orientation: .up)
//        } catch {
//          print(error.localizedDescription)
//        }
    }
    
    
    func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { [weak self] (request, error) in
            guard let self = self else { return }
            if let error = error {
                print("Face detection error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNFaceObservation],
                  let firstObservation = observations.first else { return }
            
            self.handleFaceObservation(observation: firstObservation)
        })
    }
}

struct CameraPreview: NSViewRepresentable {
    let cameraManager: CameraManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let videoLayer = AVCaptureVideoPreviewLayer(session: cameraManager.captureSession!)
        videoLayer.frame = view.bounds
        view.layer = videoLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let videoLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            videoLayer.session = cameraManager.captureSession
        }
    }
}
    
