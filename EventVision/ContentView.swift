import SwiftUI

struct CaptureFlowView: View {
    @State private var selectedMode: CaptureMode = .arScan
    @State private var arReady = false
    @StateObject private var camera = CameraManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch selectedMode {
                    case .photo, .video:
                        CameraView(mode: selectedMode)
                            .environmentObject(camera)
                    case .arScan:
                        if arReady {
                            RoomScanView()
                        } else {
                            VStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Starting AR...")
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                            }
                        }
                    case .arPlace:
                        if arReady {
                            ARPlaceView()
                        } else {
                            VStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Starting AR...")
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ModeSelectorView(selectedMode: $selectedMode)
                    .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    camera.stopSession()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Home")
                            .font(.body)
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedMode == .arScan || selectedMode == .arPlace {
                arReady = true
            }
        }
        .onChange(of: selectedMode) { oldMode, newMode in
            if newMode == .arScan || newMode == .arPlace {
                arReady = false
                camera.stopSession {
                    DispatchQueue.main.async {
                        self.arReady = true
                    }
                }
            } else {
                arReady = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaptureFlowView()
    }
}
