import SwiftUI
import ARKit
import SceneKit
import simd

struct ARPlaceSceneView: UIViewRepresentable {
    let assetStore: AssetStore
    @Binding var placedProps: [PlacedProp]
    @Binding var selectedPropID: UUID?
    @Binding var trackingStatus: String
    var snapshotTrigger: Int = 0
    var onSnapshot: ((UIImage) -> Void)?
    var selectedAsset: ImageAsset?
    var presetWidth: Float?
    var presetHeight: Float?
    var interactionMode: PropInteractionHelper.InteractionMode = .move

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        context.coordinator.sceneView = sceneView

        // Coaching overlay — Apple's built-in animation for surface detection guidance
        let coaching = ARCoachingOverlayView()
        coaching.session = sceneView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: sceneView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: sceneView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: sceneView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: sceneView.bottomAnchor)
        ])

        // Tap gesture for placement / selection
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tap)

        // Pan gesture for moving props or dragging rotation handle
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        sceneView.addGestureRecognizer(pan)

        // Pinch gesture for scaling props
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        sceneView.addGestureRecognizer(pinch)

        // Load any initial props
        context.coordinator.syncProps(placedProps)

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.helper.interactionMode = interactionMode
        if !context.coordinator.isDragging && !context.coordinator.suppressTransformSync {
            context.coordinator.syncProps(placedProps)
            context.coordinator.updateSelection(selectedPropID)
            context.coordinator.updateGhostAsset()
        }
        // Snapshot trigger
        if snapshotTrigger != context.coordinator.lastSnapshotTrigger {
            context.coordinator.lastSnapshotTrigger = snapshotTrigger
            let image = uiView.snapshot()
            onSnapshot?(image)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parent: ARPlaceSceneView
        weak var sceneView: ARSCNView?
        let helper = PropInteractionHelper()

        // Ghost preview
        private var ghostNode: SCNNode?
        private var ghostAssetID: UUID?
        private var ghostPresetWidth: Float?
        private var ghostPresetHeight: Float?

        // Plane visualization
        private var planeNodes: [UUID: SCNNode] = [:]
        private var firstPlaneDetected = false

        // Haptics
        private let impactLight = UIImpactFeedbackGenerator(style: .light)
        private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
        private let notificationFeedback = UINotificationFeedbackGenerator()

        // Pinch state
        private var pinchStartWidth: Float = 0
        private var pinchStartHeight: Float = 0

        // Snapshot
        var lastSnapshotTrigger = 0

        var isDragging: Bool { helper.isDragging }
        var suppressTransformSync: Bool { helper.suppressTransformSync }

        init(parent: ARPlaceSceneView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pinch alongside pan
            return (gestureRecognizer is UIPinchGestureRecognizer) || (otherGestureRecognizer is UIPinchGestureRecognizer)
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let state = frame.camera.trackingState
            DispatchQueue.main.async {
                switch state {
                case .normal:
                    if self.parent.selectedAsset != nil {
                        self.parent.trackingStatus = "Aim at a surface, then tap to place"
                    } else {
                        self.parent.trackingStatus = "Choose an asset to start placing"
                    }
                case .notAvailable:
                    self.parent.trackingStatus = "AR not available"
                case .limited(let reason):
                    switch reason {
                    case .initializing:
                        self.parent.trackingStatus = "Initializing \u{2014} move phone slowly..."
                    case .excessiveMotion:
                        self.parent.trackingStatus = "Slow down \u{2014} moving too fast"
                    case .insufficientFeatures:
                        self.parent.trackingStatus = "Need more visual detail"
                    case .relocalizing:
                        self.parent.trackingStatus = "Relocalizing..."
                    @unknown default:
                        self.parent.trackingStatus = "Limited tracking"
                    }
                }
            }

            // Update ghost preview position
            updateGhostPosition()
        }

        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async {
                self.parent.trackingStatus = "Session interrupted"
            }
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            DispatchQueue.main.async {
                self.parent.trackingStatus = "Resuming..."
            }
            // Re-run with reset to recover clean tracking
            guard let sceneView = sceneView else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            sceneView.session.run(config, options: [.resetTracking])
        }

        // MARK: - ARSCNViewDelegate (plane visualization)

        func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            if !firstPlaneDetected {
                firstPlaneDetected = true
                DispatchQueue.main.async { self.notificationFeedback.notificationOccurred(.success) }
            }
            let planeNode = makePlaneVisualization(for: planeAnchor)
            node.addChildNode(planeNode)
            planeNodes[anchor.identifier] = planeNode
        }

        func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let planeNode = planeNodes[anchor.identifier],
                  let plane = planeNode.geometry as? SCNPlane else { return }
            plane.width = CGFloat(planeAnchor.planeExtent.width)
            plane.height = CGFloat(planeAnchor.planeExtent.height)
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        }

        func renderer(_ renderer: any SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            planeNodes.removeValue(forKey: anchor.identifier)
        }

        private static var dotGridImage: UIImage = {
            let size: CGFloat = 64
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
                UIColor.cyan.withAlphaComponent(0.25).setFill()
                let dotSize: CGFloat = 4
                let spacing: CGFloat = 16
                var x: CGFloat = spacing / 2
                while x < size {
                    var y: CGFloat = spacing / 2
                    while y < size {
                        UIBezierPath(ovalIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)).fill()
                        y += spacing
                    }
                    x += spacing
                }
            }
        }()

        private func makePlaneVisualization(for anchor: ARPlaneAnchor) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(anchor.planeExtent.width),
                                 height: CGFloat(anchor.planeExtent.height))
            let material = SCNMaterial()
            material.diffuse.contents = Self.dotGridImage
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            let metersPerTile: Float = 0.2
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(
                Float(anchor.planeExtent.width) / metersPerTile,
                Float(anchor.planeExtent.height) / metersPerTile, 1)
            material.isDoubleSided = true
            material.lightingModel = .constant
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(anchor.center.x, 0, anchor.center.z)
            node.opacity = 0.7
            return node
        }

        // MARK: - Ghost Preview

        func updateGhostAsset() {
            guard let asset = parent.selectedAsset else {
                ghostNode?.removeFromParentNode()
                ghostNode = nil
                ghostAssetID = nil
                ghostPresetWidth = nil
                ghostPresetHeight = nil
                return
            }

            // Rebuild ghost if asset or preset dimensions changed
            if ghostAssetID != asset.id
                || ghostPresetWidth != parent.presetWidth
                || ghostPresetHeight != parent.presetHeight {
                ghostNode?.removeFromParentNode()
                ghostNode = nil
                ghostAssetID = asset.id
                ghostPresetWidth = parent.presetWidth
                ghostPresetHeight = parent.presetHeight

                let width = parent.presetWidth ?? asset.physicalWidthMeters ?? 0.5
                let height = parent.presetHeight ?? asset.physicalHeightMeters ?? (width / asset.aspectRatio)
                let depth = asset.physicalDepthMeters ?? 0

                let tempProp = PlacedProp(
                    assetID: asset.id,
                    transform: CodableMatrix4x4(matrix_identity_float4x4),
                    widthMeters: width,
                    heightMeters: height,
                    depthMeters: depth
                )

                if let image = parent.assetStore.loadImage(for: asset) {
                    let node = PropNodeBuilder.makeNode(for: tempProp, image: image, assetName: asset.name)
                    node.enumerateChildNodes { child, _ in
                        child.geometry?.materials.forEach { $0.transparency = 0.4 }
                    }
                    node.name = "ghost"
                    node.isHidden = true
                    // Subtle breathing pulse to draw the eye
                    let pulse = SCNAction.sequence([
                        SCNAction.fadeOpacity(to: 0.3, duration: 0.8),
                        SCNAction.fadeOpacity(to: 0.6, duration: 0.8)
                    ])
                    node.runAction(SCNAction.repeatForever(pulse))
                    sceneView?.scene.rootNode.addChildNode(node)
                    ghostNode = node
                }
            }
        }

        private func updateGhostPosition() {
            guard let sceneView = sceneView, let ghostNode = ghostNode else { return }
            guard parent.selectedAsset != nil else {
                ghostNode.isHidden = true
                return
            }

            let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            guard let result = raycast(from: center) else {
                ghostNode.isHidden = true
                return
            }

            let hitPoint = simd_float3(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)

            let normal = extractNormal(from: result)
            let ghostTransform: simd_float4x4
            if abs(simd_dot(normal, simd_float3(0, 1, 0))) > 0.7,
               let cameraTransform = sceneView.session.currentFrame?.camera.transform {
                ghostTransform = uprightTransform(at: hitPoint, cameraTransform: cameraTransform)
            } else {
                ghostTransform = PropNodeBuilder.surfaceAlignedTransform(hitPoint: hitPoint, surfaceNormal: normal)
            }
            ghostNode.simdTransform = ghostTransform
            ghostNode.isHidden = false
        }

        // MARK: - Gesture Delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer else { return true }
            guard let sceneView = sceneView else { return false }
            let location = gestureRecognizer.location(in: sceneView)
            return helper.shouldBeginPan(at: location, in: sceneView, selectedID: parent.selectedPropID)
        }

        // MARK: - Tap (select / place)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }

            let location = gesture.location(in: sceneView)
            let scnHits = sceneView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

            // Check if we tapped a rotation ring
            if helper.handleRingTap(in: scnHits, selectedID: parent.selectedPropID) {
                if let selectedID = parent.selectedPropID, let node = helper.propNodes[selectedID] {
                    commitTransform(for: selectedID, from: node)
                    helper.updateSelection(selectedID)
                }
                impactLight.impactOccurred()
                return
            }

            // Check if we tapped an existing prop
            if let propID = helper.findTappedProp(in: scnHits) {
                impactLight.impactOccurred()
                DispatchQueue.main.async {
                    self.parent.selectedPropID = propID
                }
                return
            }

            // Place a new prop via ARKit raycast
            guard let asset = parent.selectedAsset else { return }
            guard let result = raycast(from: location) else { return }

            let hitPoint = simd_float3(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)

            let normal = extractNormal(from: result)
            let transform: simd_float4x4
            if abs(simd_dot(normal, simd_float3(0, 1, 0))) > 0.7,
               let cameraTransform = sceneView.session.currentFrame?.camera.transform {
                transform = uprightTransform(at: hitPoint, cameraTransform: cameraTransform)
            } else {
                transform = PropNodeBuilder.surfaceAlignedTransform(hitPoint: hitPoint, surfaceNormal: normal)
            }

            let width = parent.presetWidth ?? asset.physicalWidthMeters ?? 0.5
            let height = parent.presetHeight ?? asset.physicalHeightMeters ?? (width / asset.aspectRatio)
            let depth = asset.physicalDepthMeters ?? 0

            let prop = PlacedProp(
                assetID: asset.id,
                transform: CodableMatrix4x4(transform),
                widthMeters: width,
                heightMeters: height,
                depthMeters: depth
            )

            impactMedium.impactOccurred()

            DispatchQueue.main.async {
                self.parent.placedProps.append(prop)
                self.parent.selectedPropID = prop.id
            }
        }

        // MARK: - Pan (move prop or rotate via handle)

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView = sceneView,
                  let selectedID = parent.selectedPropID,
                  let node = helper.propNodes[selectedID] else { return }

            switch gesture.state {
            case .began:
                helper.isDragging = true
                let location = gesture.location(in: sceneView)
                helper.lastDragLocation = location
                _ = helper.detectDragMode(at: location, in: sceneView, nodeTransform: node.simdTransform)

            case .changed:
                switch helper.dragMode {
                case .rotateAxis(let axis):
                    let currentLocation = gesture.location(in: sceneView)
                    helper.applyDragRotation(to: node, axis: axis, currentLocation: currentLocation, scnView: sceneView)

                case .move:
                    let location = gesture.location(in: sceneView)
                    if let result = raycast(from: location) {
                        let newPos = simd_float3(result.worldTransform.columns.3.x,
                                                  result.worldTransform.columns.3.y,
                                                  result.worldTransform.columns.3.z)
                        var t = node.simdTransform
                        t.columns.3 = simd_float4(newPos.x, newPos.y, newPos.z, 1)
                        node.simdTransform = t
                    }
                }

            case .ended, .cancelled:
                helper.endDrag()
                commitTransform(for: selectedID, from: node)

            default: break
            }
        }

        // MARK: - Pinch (scale prop)

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let selectedID = parent.selectedPropID,
                  let idx = parent.placedProps.firstIndex(where: { $0.id == selectedID }) else { return }

            switch gesture.state {
            case .began:
                pinchStartWidth = parent.placedProps[idx].widthMeters
                pinchStartHeight = parent.placedProps[idx].heightMeters

            case .changed:
                let scale = Float(gesture.scale)
                let newW = (pinchStartWidth * scale).clamped(to: 0.05...5.0)
                let newH = (pinchStartHeight * scale).clamped(to: 0.05...5.0)
                DispatchQueue.main.async {
                    self.parent.placedProps[idx].widthMeters = newW
                    self.parent.placedProps[idx].heightMeters = newH
                }

            case .ended, .cancelled:
                impactLight.impactOccurred()

            default: break
            }
        }

        private func commitTransform(for propID: UUID, from node: SCNNode) {
            helper.commitTransform(for: propID, from: node) { [weak self] (id: UUID, transform: simd_float4x4) in
                if let idx = self?.parent.placedProps.firstIndex(where: { $0.id == id }) {
                    self?.parent.placedProps[idx].transform = CodableMatrix4x4(transform)
                }
            }
        }

        // MARK: - Prop Sync (delegates to helper)

        func syncProps(_ props: [PlacedProp]) {
            guard let sceneView = sceneView else { return }
            helper.syncProps(props, rootNode: sceneView.scene.rootNode, assetStore: parent.assetStore)
        }

        func updateSelection(_ selectedID: UUID?) {
            helper.updateSelection(selectedID)
        }

        // MARK: - Helpers

        private func raycast(from point: CGPoint) -> ARRaycastResult? {
            guard let sceneView = sceneView,
                  let query = sceneView.raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .any) else {
                return nil
            }
            if let result = sceneView.session.raycast(query).first {
                return result
            }
            // Fall back to estimated planes
            guard let estimatedQuery = sceneView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else {
                return nil
            }
            return sceneView.session.raycast(estimatedQuery).first
        }

        /// Builds a transform for a prop standing upright on a horizontal surface, facing the camera.
        /// Uses surfaceAlignedTransform with a synthetic horizontal normal pointing toward the camera.
        private func uprightTransform(at position: simd_float3, cameraTransform: simd_float4x4) -> simd_float4x4 {
            let cameraPos = simd_float3(cameraTransform.columns.3.x,
                                         cameraTransform.columns.3.y,
                                         cameraTransform.columns.3.z)
            // Horizontal direction from prop to camera (ignore Y)
            var toCamera = cameraPos - position
            toCamera.y = 0
            let facingNormal = simd_normalize(toCamera)

            // Use the existing wall-placement logic with a horizontal facing direction
            return PropNodeBuilder.surfaceAlignedTransform(hitPoint: position, surfaceNormal: facingNormal)
        }

        private func extractNormal(from result: ARRaycastResult) -> simd_float3 {
            if let anchor = result.anchor as? ARPlaneAnchor {
                switch anchor.alignment {
                case .vertical:
                    return simd_float3(result.worldTransform.columns.2.x,
                                        result.worldTransform.columns.2.y,
                                        result.worldTransform.columns.2.z)
                case .horizontal:
                    return simd_float3(0, 1, 0)
                @unknown default:
                    return simd_float3(result.worldTransform.columns.2.x,
                                        result.worldTransform.columns.2.y,
                                        result.worldTransform.columns.2.z)
                }
            }
            return simd_float3(result.worldTransform.columns.2.x,
                                result.worldTransform.columns.2.y,
                                result.worldTransform.columns.2.z)
        }

    }
}
