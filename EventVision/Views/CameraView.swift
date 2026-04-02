import SwiftUI
import AVFoundation
import Photos

struct CameraView: View {
    let mode: CaptureMode
    @EnvironmentObject var camera: CameraManager

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewLayer(session: camera.session)
                .ignoresSafeArea()

            // Error overlay
            if let error = camera.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            VStack {
                // Save confirmation
                if let message = camera.saveMessage {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                Spacer()

                // Capture controls overlay
                Button {
                    if mode == .photo {
                        camera.capturePhoto()
                    } else {
                        camera.toggleRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)

                        if mode == .video && camera.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(mode == .video ? Color.red : Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .animation(.easeInOut(duration: 0.3), value: camera.saveMessage)
        }
        .onAppear {
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Re-attach session in case it was reconfigured
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isRecording = false
    @Published var isSessionRunning = false
    @Published var saveMessage: String?
    @Published var errorMessage: String?
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.eventvision.camera")

    private func requestPermissionAndConfigure(then completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async {
                self.configureSession()
                completion()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async {
                        self.configureSession()
                        completion()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Camera access denied. Go to Settings to enable."
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access denied. Go to Settings > Privacy > Camera to enable."
            }
        @unknown default:
            break
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "No camera found" }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Camera input error: \(error.localizedDescription)" }
            return
        }

        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    func startSession() {
        requestPhotoLibraryAccess()
        requestPermissionAndConfigure {
            // Runs on sessionQueue after configuration is complete
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                    self.errorMessage = nil
                }
            }
        }
    }

    func stopSession(completion: (() -> Void)? = nil) {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
                completion?()
            }
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording() {
        sessionQueue.async {
            if self.videoOutput.isRecording {
                self.videoOutput.stopRecording()
                DispatchQueue.main.async { self.isRecording = false }
            } else {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                self.videoOutput.startRecording(to: url, recordingDelegate: self)
                DispatchQueue.main.async { self.isRecording = true }
            }
        }
    }

    private func requestPhotoLibraryAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        }
    }

    private func showSaveMessage(_ text: String) {
        DispatchQueue.main.async {
            self.saveMessage = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.saveMessage == text {
                    self.saveMessage = nil
                }
            }
        }
    }

    private func savePhoto(data: Data) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        } completionHandler: { success, error in
            if success {
                self.showSaveMessage("Photo saved to library")
            } else {
                self.showSaveMessage("Could not save photo: \(error?.localizedDescription ?? "unknown")")
            }
        }
        saveToAppStorage(data: data, ext: "jpg")
    }

    private func saveVideo(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            if success {
                self.showSaveMessage("Video saved to library")
            } else {
                self.showSaveMessage("Could not save video: \(error?.localizedDescription ?? "unknown")")
            }
        }
        copyToAppStorage(from: url, ext: "mov")
    }

    private func copyToAppStorage(from sourceURL: URL, ext: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mediaDir = docs.appendingPathComponent("EventVision", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: Date())).\(ext)"
        let fileURL = mediaDir.appendingPathComponent(filename)
        try? FileManager.default.copyItem(at: sourceURL, to: fileURL)
    }

    private func saveToAppStorage(data: Data, ext: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mediaDir = docs.appendingPathComponent("EventVision", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: Date())).\(ext)"
        let fileURL = mediaDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else {
            showSaveMessage("Failed to capture photo")
            return
        }
        savePhoto(data: data)
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            showSaveMessage("Recording error: \(error.localizedDescription)")
            return
        }
        saveVideo(url: outputFileURL)
    }
}
