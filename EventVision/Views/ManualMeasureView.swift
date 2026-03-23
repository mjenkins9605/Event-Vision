import SwiftUI
import ARKit
import AVFoundation
import SceneKit

struct ManualMeasureView: View {
    @StateObject private var measure = ManualMeasureManager()
    @State private var flashlightOn = false

    var body: some View {
        ZStack {
            ARSceneViewRepresentable(manager: measure)
                .ignoresSafeArea()

            // Crosshair
            CrosshairView()

            VStack {
                // Top bar: status + flashlight
                HStack {
                    Text(measure.statusMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)

                    Spacer()

                    // Mode toggle
                    Picker("Mode", selection: $measure.mode) {
                        Text("Walk").tag(MeasureMode.walk)
                        Text("Point").tag(MeasureMode.point)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)

                    Button {
                        flashlightOn.toggle()
                        measure.setFlashlight(on: flashlightOn)
                    } label: {
                        Image(systemName: flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 20))
                            .foregroundColor(flashlightOn ? .yellow : .white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Segment measurements list
                if !measure.segments.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(measure.segments.enumerated()), id: \.offset) { i, seg in
                            HStack {
                                Text("Seg \(i + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(measure.formatDistance(seg))
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        Divider().background(Color.white.opacity(0.3))
                        HStack {
                            Text("Total")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(measure.formatDistance(measure.totalDistance))
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Live distance
                if let live = measure.liveDistance {
                    Text(measure.formatDistance(live))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.bottom, 8)
                }

                // Debug info — shows raw values so we can diagnose accuracy
                if !measure.debugLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(measure.debugLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Mode hint
                if measure.mode == .walk {
                    Text(measure.points.isEmpty
                         ? "Walk to start point, hold phone steady, tap Drop Pin"
                         : "Walk to next point and tap Drop Pin")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }

                // Controls
                HStack(spacing: 24) {
                    if !measure.points.isEmpty {
                        Button {
                            measure.undoLastPoint()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }

                        Button {
                            measure.clearAll()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }
                    }

                    Button {
                        measure.dropPin()
                    } label: {
                        Label("Drop Pin", systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(measure.canPlace ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                    }
                    .disabled(!measure.canPlace)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            flashlightOn = true
            measure.flashlightRequested = true
        }
        .onDisappear {
            flashlightOn = false
            measure.setFlashlight(on: false)
        }
    }
}

// MARK: - Measure Mode

enum MeasureMode {
    case walk   // Use camera position (accurate)
    case point  // Use raycast (for when you can't walk to both points)
}

// MARK: - Crosshair

struct CrosshairView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 4, height: 4)
        }
    }
}

// MARK: - AR SceneKit View

struct ARSceneViewRepresentable: UIViewRepresentable {
    let manager: ManualMeasureManager

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = manager
        sceneView.session.delegate = manager
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.debugOptions = [.showFeaturePoints]

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        manager.sceneView = sceneView
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - Measure Manager

class ManualMeasureManager: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    @Published var statusMessage = "Move phone slowly to scan surfaces..."
    @Published var mode: MeasureMode = .walk
    @Published var points: [SCNVector3] = []
    @Published var segments: [Float] = []
    @Published var liveDistance: Float?
    @Published var trackingReady = false
    @Published var surfaceDetected = false
    @Published var debugLines: [String] = []

    var flashlightRequested = false
    private var flashlightActivated = false

    weak var sceneView: ARSCNView?
    private var pinNodes: [SCNNode] = []
    private var lineNodes: [SCNNode] = []
    private var liveLineNode: SCNNode?
    private var planeNodes: [UUID: SCNNode] = [:]

    var canPlace: Bool {
        return trackingReady
    }

    var totalDistance: Float {
        segments.reduce(0, +)
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state = frame.camera.trackingState
        DispatchQueue.main.async {
            switch state {
            case .normal:
                self.trackingReady = true
                if self.flashlightRequested && !self.flashlightActivated {
                    self.flashlightActivated = true
                    self.setFlashlight(on: true)
                }
                if self.points.isEmpty {
                    self.statusMessage = self.surfaceDetected
                        ? "Ready \u{2014} walk to your start point"
                        : "Keep moving \u{2014} looking for surfaces..."
                }
            case .notAvailable:
                self.trackingReady = false
                self.statusMessage = "AR not available"
            case .limited(let reason):
                self.trackingReady = false
                switch reason {
                case .initializing:
                    self.statusMessage = "Initializing \u{2014} move phone slowly..."
                case .excessiveMotion:
                    self.statusMessage = "Slow down \u{2014} moving too fast"
                case .insufficientFeatures:
                    self.statusMessage = "Need more visual detail"
                case .relocalizing:
                    self.statusMessage = "Relocalizing..."
                @unknown default:
                    self.statusMessage = "Limited tracking"
                }
            }
        }

        // Live distance update
        if !points.isEmpty {
            updateLiveDistance(frame: frame)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor is ARPlaneAnchor {
                DispatchQueue.main.async {
                    self.surfaceDetected = true
                }
            }
        }
    }

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        let planeNode = createPlaneNode(for: planeAnchor)
        node.addChildNode(planeNode)
        planeNodes[anchor.identifier] = planeNode
    }

    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
              let planeNode = planeNodes[anchor.identifier] else { return }
        updatePlaneNode(planeNode, for: planeAnchor)
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        planeNodes.removeValue(forKey: anchor.identifier)
    }

    // MARK: - Drop Pin

    func dropPin() {
        guard let sceneView = sceneView,
              let frame = sceneView.session.currentFrame else { return }

        let point: SCNVector3

        switch mode {
        case .walk:
            // Use camera's actual position in world space — this is what ARKit tracks best
            let cam = frame.camera.transform
            point = SCNVector3(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)

        case .point:
            // Raycast from screen center
            let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            guard let hit = hitTest(at: center) else {
                statusMessage = "No surface found \u{2014} aim at a wall or floor"
                return
            }
            point = hit
        }

        // Debug: log raw position
        let pinIndex = points.count
        var newDebug: [String] = []
        newDebug.append("Pin \(pinIndex + 1): x=\(String(format: "%.4f", point.x)) y=\(String(format: "%.4f", point.y)) z=\(String(format: "%.4f", point.z))")

        // Add visual pin
        let pinNode = addPin(at: point, index: pinIndex)
        if let pinNode = pinNode {
            pinNodes.append(pinNode)
        }

        // If we have a previous point, draw a line and record the segment
        if let lastPoint = points.last {
            let dist = distance(from: lastPoint, to: point)
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            let dz = point.z - lastPoint.z
            newDebug.append("dx=\(String(format: "%.4f", dx)) dy=\(String(format: "%.4f", dy)) dz=\(String(format: "%.4f", dz))")
            newDebug.append("dist=\(String(format: "%.4f", dist))m = \(String(format: "%.1f", dist * 39.3701))in")
            segments.append(dist)
            if let lineNode = addLine(from: lastPoint, to: point, color: .white) {
                lineNodes.append(lineNode)
            }
        }

        debugLines = newDebug

        points.append(point)
        liveDistance = nil
        liveLineNode?.removeFromParentNode()
        liveLineNode = nil

        let count = points.count
        statusMessage = "\(count) pin\(count == 1 ? "" : "s") placed \u{2014} walk to next point or Clear"
    }

    // MARK: - Undo / Clear

    func undoLastPoint() {
        guard !points.isEmpty else { return }

        // Remove last pin
        pinNodes.last?.removeFromParentNode()
        pinNodes.removeLast()
        points.removeLast()

        // Remove last line segment
        if !lineNodes.isEmpty {
            lineNodes.last?.removeFromParentNode()
            lineNodes.removeLast()
            segments.removeLast()
        }

        liveLineNode?.removeFromParentNode()
        liveLineNode = nil
        liveDistance = nil

        if points.isEmpty {
            statusMessage = "Ready \u{2014} walk to your start point"
        } else {
            statusMessage = "\(points.count) pin\(points.count == 1 ? "" : "s") placed"
        }
    }

    func clearAll() {
        for node in pinNodes { node.removeFromParentNode() }
        for node in lineNodes { node.removeFromParentNode() }
        liveLineNode?.removeFromParentNode()

        pinNodes.removeAll()
        lineNodes.removeAll()
        liveLineNode = nil
        points.removeAll()
        segments.removeAll()
        liveDistance = nil
        debugLines = []
        statusMessage = "Ready \u{2014} walk to your start point"
    }

    // MARK: - Live Distance

    private func updateLiveDistance(frame: ARFrame) {
        guard let lastPoint = points.last else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sceneView = self.sceneView else { return }

            let currentPoint: SCNVector3

            switch self.mode {
            case .walk:
                let cam = frame.camera.transform
                currentPoint = SCNVector3(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            case .point:
                let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
                guard let hit = self.hitTest(at: center) else { return }
                currentPoint = hit
            }

            let dist = self.distance(from: lastPoint, to: currentPoint)
            self.liveDistance = dist

            self.liveLineNode?.removeFromParentNode()
            self.liveLineNode = self.addLine(from: lastPoint, to: currentPoint, color: .yellow)
        }
    }

    // MARK: - Raycast (for Point mode)

    private func hitTest(at screenCenter: CGPoint) -> SCNVector3? {
        guard let sceneView = sceneView else { return nil }

        // Try existing plane geometry first (most accurate)
        if let query = sceneView.raycastQuery(from: screenCenter, allowing: .existingPlaneGeometry, alignment: .any),
           let result = sceneView.session.raycast(query).first {
            let pos = result.worldTransform.columns.3
            return SCNVector3(pos.x, pos.y, pos.z)
        }

        // Fall back to estimated planes
        if let query = sceneView.raycastQuery(from: screenCenter, allowing: .estimatedPlane, alignment: .any),
           let result = sceneView.session.raycast(query).first {
            let pos = result.worldTransform.columns.3
            return SCNVector3(pos.x, pos.y, pos.z)
        }

        return nil
    }

    // MARK: - Flashlight

    func setFlashlight(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Flashlight error: \(error)")
        }
        if !on {
            flashlightActivated = false
        }
    }

    // MARK: - Formatting

    func formatDistance(_ meters: Float) -> String {
        MeasurementFormatter.feetInches(meters)
    }

    // MARK: - Geometry Helpers

    private func distance(from a: SCNVector3, to b: SCNVector3) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private func addPin(at position: SCNVector3, index: Int) -> SCNNode? {
        guard let sceneView = sceneView else { return nil }

        // Sphere marker
        let sphere = SCNSphere(radius: 0.015)
        let color: UIColor = index == 0 ? .systemBlue : .systemGreen
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: sphere)
        node.position = position

        // Small label showing pin number
        let text = SCNText(string: " \(index + 1) ", extrusionDepth: 0.001)
        text.font = UIFont.boldSystemFont(ofSize: 0.04)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.lightingModel = .constant
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(0, 0.025, 0)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)

        // Make text face camera
        let constraint = SCNBillboardConstraint()
        textNode.constraints = [constraint]

        node.addChildNode(textNode)
        sceneView.scene.rootNode.addChildNode(node)
        return node
    }

    private func addLine(from start: SCNVector3, to end: SCNVector3, color: UIColor) -> SCNNode? {
        guard let sceneView = sceneView else { return nil }

        let vertices: [SCNVector3] = [start, end]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [UInt16] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        sceneView.scene.rootNode.addChildNode(node)
        return node
    }

    private func createPlaneNode(for anchor: ARPlaneAnchor) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(anchor.planeExtent.width),
                           height: CGFloat(anchor.planeExtent.height))
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.15)
        material.isDoubleSided = true
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(anchor.center.x, 0, anchor.center.z)
        return node
    }

    private func updatePlaneNode(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        guard let plane = node.geometry as? SCNPlane else { return }
        plane.width = CGFloat(anchor.planeExtent.width)
        plane.height = CGFloat(anchor.planeExtent.height)
        node.position = SCNVector3(anchor.center.x, 0, anchor.center.z)
    }
}
