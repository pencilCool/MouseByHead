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
    @State private var sensitivity: Double = 1
    @State private var selectedCameraIndex: Int = 0
    @State private var isScrollingEnabled: Bool = true
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        VStack {
            // 摄像头预览
            CameraPreview(cameraManager: cameraManager)
               .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 灵敏度设置
            HStack {
                Text("灵敏度:")
                Slider(value: $sensitivity, in: 1...10, step: 1)
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
        }.onReceive(cameraManager.$isScrollingEnabled) { scrollAble in
                if scrollAble == true {
                    showAlert(message: "🟢向右歪头，允许触发鼠标滚动事件")
                } else {
                    showAlert(message: "🔴向左歪头，禁止触发鼠标滚动事件")
                }
        }
       
    }
    private func showAlert(message: String) {
        let alertWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        alertWindow.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        alertWindow.isOpaque = false
        alertWindow.hasShadow = true
        alertWindow.level = .floating
        alertWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        textView.string = message
        textView.alignment = .center

        // 垂直居中
        let textContainer = textView.textContainer
        textContainer?.lineFragmentPadding = 0 // 移除默认的行片段填充

        let font = NSFont.systemFont(ofSize: 20)
        let lineHeight = font.capHeight
        let availableHeight = textView.bounds.height
        let verticalInset = (availableHeight - lineHeight) / 2
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)


        textView.textColor = .white
        textView.font = font
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.layer?.cornerRadius = 20
        textView.clipsToBounds = true
        alertWindow.contentView = textView

        // 居中显示
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowRect = alertWindow.frame
        alertWindow.setFrameOrigin(NSPoint(x: (screenRect.width - windowRect.width) / 2, y: (screenRect.height - windowRect.height) / 2))

        alertWindow.makeKeyAndOrderFront(nil)


        // 自动消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            alertWindow.orderOut(nil)
        }
    }

}

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var sensitivity: Int = 1
    @Published var isScrollingEnabled:Bool = true
    var captureSession: AVCaptureSession?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    var sequenceHandler = VNSequenceRequestHandler()
    
    let dataOutputQueue = DispatchQueue(
      label: "com.pencilcool.mousebyhead.video.data.queue",
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
//        let  yaw = observation.yaw?.doubleValue ?? 0
        let pitch = observation.pitch?.doubleValue ?? 0
        let roll = observation.roll?.doubleValue ?? 0
        if roll > 0.4 {
            // 右歪头
            isScrollingEnabled = true
            print("[pencilCool]  scrollAble")
        } else if roll < -0.4 {
            // 左歪头
            isScrollingEnabled = false
            print("[pencilCool]  not scrollAble")
        }
        
        if (isScrollingEnabled == false) {
           return
        }
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
        scrollMouse(xLines: delta, yLines: delta)
    }
   
      func scrollMouse(xLines: Int, yLines: Int) {
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
                  // 引导用户去开启权限
                  _ = CameraManager.onceAccessibility
              }
            

        } else {
            // scroll event is not supported for macOS older than 10.13
        }
    }
    
    static let onceAccessibility: Void = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            return ()
        }()
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let faceDetectionRequest = faceDetectionRequest else { return }
        let imageRequestHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
          try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
          print("Error performing face detection request: \(error)")
        }
        
//        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//          return
//        }
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
        videoLayer.connection?.automaticallyAdjustsVideoMirroring = false;
        videoLayer.connection?.isVideoMirrored = true;
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
    
