import SwiftUI
import ARKit
import RoomPlan
import SceneKit

struct RoomScanView: View {
    private var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    var body: some View {
        if hasLiDAR {
            LiDARScanView()
        } else {
            ManualMeasureView()
        }
    }
}

// MARK: - LiDAR Room Scan

struct LiDARScanView: View {
    @StateObject private var scanner = RoomScanManager()
    @EnvironmentObject var scanStore: ScanStore
    @State private var showResults = false
    @State private var show3DView = false
    @State private var showSavePrompt = false
    @State private var scanName = ""
    @State private var savedConfirmation: String?

    var body: some View {
        ZStack {
            // Keep RoomPlan view alive so it retains the post-scan 3D model
            RoomCaptureViewContainer(scanner: scanner)
                .ignoresSafeArea()
                .opacity(show3DView ? 0 : 1)

            if show3DView, let room = scanner.scannedRoom {
                Room3DViewer(room: room)
                    .ignoresSafeArea()
            }

            VStack {
                if let status = scanner.statusMessage {
                    Text(status)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.top, 12)
                }

                Spacer()

                Group {
                    if !scanner.isScanning {
                        if scanner.scannedRoom != nil {
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        show3DView.toggle()
                                    } label: {
                                        Label(show3DView ? "RoomPlan" : "Measured",
                                              systemImage: show3DView ? "cube" : "ruler")
                                            .font(.headline)
                                            .lineLimit(1).fixedSize()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(25)
                                    }

                                    Button {
                                        showResults = true
                                    } label: {
                                        Label("List", systemImage: "list.bullet")
                                            .font(.headline)
                                            .lineLimit(1).fixedSize()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.white.opacity(0.2))
                                            .foregroundColor(.white)
                                            .cornerRadius(25)
                                    }
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        scanName = ""
                                        showSavePrompt = true
                                    } label: {
                                        Label("Save", systemImage: "square.and.arrow.down")
                                            .font(.headline)
                                            .lineLimit(1).fixedSize()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(25)
                                    }

                                    Button {
                                        show3DView = false
                                        scanner.startScan()
                                    } label: {
                                        Label("Rescan", systemImage: "record.circle")
                                            .font(.headline)
                                            .lineLimit(1).fixedSize()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.orange)
                                            .foregroundColor(.white)
                                            .cornerRadius(25)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            Button {
                                scanner.startScan()
                            } label: {
                                Label("Scan", systemImage: "record.circle")
                                    .font(.headline)
                                    .lineLimit(1).fixedSize()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(25)
                            }
                        }
                    } else {
                        Button {
                            scanner.stopScan()
                        } label: {
                            Label("Done", systemImage: "checkmark.circle")
                                .font(.headline)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onDisappear {
            if scanner.isScanning {
                scanner.stopScan()
            }
        }
        .onChange(of: scanner.scannedRoom != nil) { _, hasRoom in
            if hasRoom {
                show3DView = true
                scanName = ""
                showSavePrompt = true
            }
        }
        .sheet(isPresented: $showResults) {
            if let room = scanner.scannedRoom {
                ScanResultsSheet(room: room)
            }
        }
        .alert("Save Scan", isPresented: $showSavePrompt) {
            TextField("e.g. Grand Ballroom", text: $scanName)
            Button("Save") {
                if let room = scanner.scannedRoom {
                    let trimmed = scanName.trimmingCharacters(in: .whitespaces)
                    let name = trimmed.isEmpty ? "Untitled Scan" : trimmed
                    let scan = SavedScan(name: name, room: room)
                    scanStore.save(scan, room: room)
                    savedConfirmation = "\u{201C}\(name)\u{201D} saved"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedConfirmation = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this scan a name so you can find it later.")
        }
        .overlay {
            if let msg = savedConfirmation {
                Text(msg)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .animation(.easeInOut, value: savedConfirmation)
            }
        }
    }
}

// MARK: - Custom 3D Room Viewer with Measurements

struct Room3DViewer: UIViewRepresentable {
    let surfaces: [(dimensions: simd_float3, transform: simd_float4x4, color: UIColor, edgeColor: UIColor)]
    var showMeasurements: Bool = true

    /// Initialize from a live CapturedRoom
    init(room: CapturedRoom) {
        var s: [(simd_float3, simd_float4x4, UIColor, UIColor)] = []
        for wall in room.walls {
            s.append((wall.dimensions, wall.transform, UIColor.systemBlue.withAlphaComponent(0.3), .systemBlue))
        }
        for door in room.doors {
            s.append((door.dimensions, door.transform, UIColor.systemGreen.withAlphaComponent(0.3), .systemGreen))
        }
        for window in room.windows {
            s.append((window.dimensions, window.transform, UIColor.systemOrange.withAlphaComponent(0.3), .systemOrange))
        }
        for opening in room.openings {
            s.append((opening.dimensions, opening.transform, UIColor.systemPurple.withAlphaComponent(0.3), .systemPurple))
        }
        self.surfaces = s
    }

    /// Initialize from a saved scan
    init(scan: SavedScan, showMeasurements: Bool = true) {
        var s: [(simd_float3, simd_float4x4, UIColor, UIColor)] = []
        for wall in scan.walls {
            s.append((wall.dimensions, wall.simdTransform, UIColor.systemBlue.withAlphaComponent(0.3), .systemBlue))
        }
        for door in scan.doors {
            s.append((door.dimensions, door.simdTransform, UIColor.systemGreen.withAlphaComponent(0.3), .systemGreen))
        }
        for window in scan.windows {
            s.append((window.dimensions, window.simdTransform, UIColor.systemOrange.withAlphaComponent(0.3), .systemOrange))
        }
        for opening in scan.openings {
            s.append((opening.dimensions, opening.simdTransform, UIColor.systemPurple.withAlphaComponent(0.3), .systemPurple))
        }
        self.surfaces = s
        self.showMeasurements = showMeasurements
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        // One finger = orbit/rotate, two fingers = pan/move, pinch = zoom
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true

        let scene = SCNScene()
        scnView.scene = scene

        buildRoom(in: scene)

        // Compute room center for better orbit target
        var center = simd_float3.zero
        var count: Float = 0
        for surface in surfaces {
            center += simd_make_float3(surface.transform.columns.3)
            count += 1
        }
        if count > 0 { center /= count }

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(center.x, center.y + 5, center.z + 5)
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        scnView.defaultCameraController.target = SCNVector3(center.x, center.y, center.z)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let root = uiView.scene?.rootNode else { return }
        root.enumerateChildNodes { node, _ in
            if node.name == "measurementLabel" || node.name == "measurementEdge" {
                node.isHidden = !showMeasurements
            }
        }
    }

    private func buildRoom(in scene: SCNScene) {
        var lowestY: Float = 0

        for surface in surfaces {
            addSurface(to: scene, dimensions: surface.dimensions, transform: surface.transform, color: surface.color, edgeColor: surface.edgeColor)
            let bottomY = surface.transform.columns.3.y - surface.dimensions.y / 2
            lowestY = min(lowestY, bottomY)
        }

        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor.white.withAlphaComponent(0.15)
        floorMat.lightingModel = .constant
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = lowestY
        scene.rootNode.addChildNode(floorNode)
    }

    private func addSurface(to scene: SCNScene, dimensions: simd_float3, transform: simd_float4x4, color: UIColor, edgeColor: UIColor) {
        let w = dimensions.x
        let h = dimensions.y
        let hw = w / 2
        let hh = h / 2

        let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.lightingModel = .constant
        plane.materials = [material]
        let planeNode = SCNNode(geometry: plane)
        planeNode.simdTransform = transform
        scene.rootNode.addChildNode(planeNode)

        let tl = simd_make_float3(transform * simd_float4(-hw,  hh, 0, 1))
        let tr = simd_make_float3(transform * simd_float4( hw,  hh, 0, 1))
        let br = simd_make_float3(transform * simd_float4( hw, -hh, 0, 1))
        let bl = simd_make_float3(transform * simd_float4(-hw, -hh, 0, 1))

        let edge1 = addLine(to: scene, from: tl, to: tr, color: edgeColor)
        let edge2 = addLine(to: scene, from: tr, to: br, color: edgeColor)
        let edge3 = addLine(to: scene, from: br, to: bl, color: edgeColor)
        let edge4 = addLine(to: scene, from: bl, to: tl, color: edgeColor)
        for edge in [edge1, edge2, edge3, edge4] { edge.name = "measurementEdge" }

        // Offset labels along the surface normal so they float in front of the wall
        let normal = simd_make_float3(transform.columns.2) * 0.05

        let topMid = (tl + tr) / 2 + normal
        let widthLabel = PropNodeBuilder.makeImageLabel(text: MeasurementFormatter.feetInches(w), color: edgeColor)
        widthLabel.simdWorldPosition = topMid
        widthLabel.constraints = [SCNBillboardConstraint()]
        widthLabel.renderingOrder = 100
        widthLabel.geometry?.firstMaterial?.readsFromDepthBuffer = false
        widthLabel.name = "measurementLabel"
        scene.rootNode.addChildNode(widthLabel)

        let leftMid = (tl + bl) / 2 + normal
        let heightLabel = PropNodeBuilder.makeImageLabel(text: MeasurementFormatter.feetInches(h), color: edgeColor)
        heightLabel.simdWorldPosition = leftMid
        heightLabel.constraints = [SCNBillboardConstraint()]
        heightLabel.renderingOrder = 100
        heightLabel.geometry?.firstMaterial?.readsFromDepthBuffer = false
        heightLabel.name = "measurementLabel"
        scene.rootNode.addChildNode(heightLabel)
    }

    @discardableResult
    private func addLine(to scene: SCNScene, from a: simd_float3, to b: simd_float3, color: UIColor) -> SCNNode {
        let vertices = [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)]
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: [UInt16(0), UInt16(1)], primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        geometry.materials = [mat]
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        return node
    }

}

// MARK: - USDZ Room Viewer (RoomPlan export)

struct USDZRoomViewer: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        if let scene = try? SCNScene(url: fileURL) {
            scnView.scene = scene
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Scan Results Sheet

struct ScanResultsSheet: View {
    let room: CapturedRoom
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        SummaryItem(count: room.walls.count, label: "Walls", icon: "rectangle.portrait")
                        Spacer()
                        SummaryItem(count: room.doors.count, label: "Doors", icon: "door.left.hand.open")
                        Spacer()
                        SummaryItem(count: room.windows.count, label: "Windows", icon: "window.vertical.open")
                        Spacer()
                        SummaryItem(count: room.openings.count, label: "Openings", icon: "rectangle.portrait.arrowtriangle.2.outward")
                    }
                    .padding(.vertical, 8)
                }

                if !room.walls.isEmpty {
                    Section("Walls") {
                        ForEach(Array(room.walls.enumerated()), id: \.element.identifier) { i, wall in
                            SurfaceRow(
                                label: "Wall \(i + 1)",
                                icon: "rectangle.portrait",
                                width: wall.dimensions.x,
                                height: wall.dimensions.y,
                                color: .blue
                            )
                        }
                    }
                }

                if !room.doors.isEmpty {
                    Section("Doors") {
                        ForEach(Array(room.doors.enumerated()), id: \.element.identifier) { i, door in
                            SurfaceRow(
                                label: "Door \(i + 1)",
                                icon: "door.left.hand.open",
                                width: door.dimensions.x,
                                height: door.dimensions.y,
                                color: .green
                            )
                        }
                    }
                }

                if !room.windows.isEmpty {
                    Section("Windows") {
                        ForEach(Array(room.windows.enumerated()), id: \.element.identifier) { i, window in
                            SurfaceRow(
                                label: "Window \(i + 1)",
                                icon: "window.vertical.open",
                                width: window.dimensions.x,
                                height: window.dimensions.y,
                                color: .orange
                            )
                        }
                    }
                }

                if !room.openings.isEmpty {
                    Section("Openings") {
                        ForEach(Array(room.openings.enumerated()), id: \.element.identifier) { i, opening in
                            SurfaceRow(
                                label: "Opening \(i + 1)",
                                icon: "rectangle.portrait.arrowtriangle.2.outward",
                                width: opening.dimensions.x,
                                height: opening.dimensions.y,
                                color: .purple
                            )
                        }
                    }
                }
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SummaryItem: View {
    let count: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SurfaceRow: View {
    let label: String
    let icon: String
    let width: Float
    let height: Float
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)

            Text(label)
                .font(.headline)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("W:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(MeasurementFormatter.feetInches(width))
                        .font(.body)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    Text("H:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(MeasurementFormatter.feetInches(height))
                        .font(.body)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - RoomCaptureView Container

struct RoomCaptureViewContainer: UIViewControllerRepresentable {
    @ObservedObject var scanner: RoomScanManager

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.scanner = scanner
        scanner.setupCaptureView(in: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
}

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    weak var scanner: RoomScanManager?
    var roomCaptureView: RoomCaptureView!

    override func viewDidLoad() {
        super.viewDidLoad()

        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.delegate = self
        view.addSubview(roomCaptureView)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (Error)?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (Error)?) {
        guard let scanner = scanner else { return }

        DispatchQueue.main.async {
            scanner.scannedRoom = processedResult
            scanner.isScanning = false

            let wc = processedResult.walls.count
            let dc = processedResult.doors.count
            let wnc = processedResult.windows.count
            let oc = processedResult.openings.count
            scanner.statusMessage = "Found \(wc) walls, \(dc) doors, \(wnc) windows, \(oc) openings"
        }
    }
}

// MARK: - Room Scan Manager

class RoomScanManager: ObservableObject {
    @Published var isScanning = false
    @Published var statusMessage: String? = "Tap \u{2018}Start Scan\u{2019} to begin"
    @Published var scannedRoom: CapturedRoom?

    weak var captureViewController: RoomCaptureViewController?

    func setupCaptureView(in vc: RoomCaptureViewController) {
        self.captureViewController = vc
    }

    func startScan() {
        guard let vc = captureViewController else {
            statusMessage = "Error: capture view not ready"
            return
        }

        scannedRoom = nil

        let config = RoomCaptureSession.Configuration()
        vc.roomCaptureView.captureSession.run(configuration: config)
        isScanning = true
        statusMessage = "Move slowly around the room"
    }

    func stopScan() {
        guard isScanning, let vc = captureViewController else { return }
        vc.roomCaptureView.captureSession.stop()
        isScanning = false
        statusMessage = "Processing scan..."
    }
}
