import SwiftUI
import ARKit
import SceneKit
import simd

struct ARPlaceSceneView: UIViewRepresentable {
    let assetStore: AssetStore
    @Binding var placedProps: [PlacedProp]
    @Binding var selectedPropID: UUID?
    @Binding var trackingStatus: String
    var selectedAsset: ImageAsset?
    var presetWidth: Float?
    var presetHeight: Float?

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

        // Tap gesture for placement / selection
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tap)

        // Pan gesture for moving props or dragging rotation handle
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        sceneView.addGestureRecognizer(pan)

        // Load any initial props
        context.coordinator.syncProps(placedProps)

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isDragging && !context.coordinator.suppressTransformSync {
            context.coordinator.syncProps(placedProps)
            context.coordinator.updateSelection(selectedPropID)
            context.coordinator.updateGhostAsset()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parent: ARPlaceSceneView
        weak var sceneView: ARSCNView?
        var propNodes: [UUID: SCNNode] = [:]
        private var selectionHighlight: SCNNode?
        private var gizmoNode: SCNNode?

        // Ghost preview
        private var ghostNode: SCNNode?
        private var ghostAssetID: UUID?

        // Plane visualization
        private var planeNodes: [UUID: SCNNode] = [:]

        // Drag state
        private enum DragMode { case move, rotateAxis(simd_float3) }
        private var dragMode: DragMode = .move
        var isDragging = false
        var suppressTransformSync = false
        private var lastDragLocation: CGPoint = .zero

        init(parent: ARPlaceSceneView) {
            self.parent = parent
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

        // MARK: - ARSCNViewDelegate (plane visualization)

        func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
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

        private func makePlaneVisualization(for anchor: ARPlaneAnchor) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(anchor.planeExtent.width),
                                 height: CGFloat(anchor.planeExtent.height))
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.08)
            material.isDoubleSided = true
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(anchor.center.x, 0, anchor.center.z)
            return node
        }

        // MARK: - Ghost Preview

        func updateGhostAsset() {
            guard let asset = parent.selectedAsset else {
                ghostNode?.removeFromParentNode()
                ghostNode = nil
                ghostAssetID = nil
                return
            }

            // Rebuild ghost if asset changed
            if ghostAssetID != asset.id {
                ghostNode?.removeFromParentNode()
                ghostNode = nil
                ghostAssetID = asset.id

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
            guard let sceneView = sceneView, let selectedID = parent.selectedPropID else { return false }

            let location = gestureRecognizer.location(in: sceneView)
            let hits = sceneView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for hit in hits {
                if PropNodeBuilder.rotationAxis(for: hit.node) != nil { return true }
                if let name = hit.node.name, let propID = UUID(uuidString: name), propID == selectedID {
                    return true
                }
                if let propNode = propNodes[selectedID], isDescendant(hit.node, of: propNode) {
                    return true
                }
            }
            return false
        }

        // MARK: - Tap (select / place)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }

            let location = gesture.location(in: sceneView)

            // Check if we tapped a rotation ring — rotate 45° on that axis
            let scnHits = sceneView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let selectedID = parent.selectedPropID, let node = propNodes[selectedID] {
                for hit in scnHits {
                    if let axis = PropNodeBuilder.rotationAxis(for: hit.node) {
                        let rotAxis = rotationAxisVector(axis, transform: node.simdTransform)
                        let rotation = simd_quatf(angle: .pi / 4, axis: simd_normalize(rotAxis))
                        let rotMatrix = simd_float4x4(rotation)
                        let pos = simd_float3(node.simdTransform.columns.3.x, node.simdTransform.columns.3.y, node.simdTransform.columns.3.z)
                        var t = node.simdTransform
                        t.columns.3 = simd_float4(0, 0, 0, 1)
                        t = simd_mul(rotMatrix, t)
                        t.columns.3 = simd_float4(pos, 1)
                        node.simdTransform = t
                        commitTransform(for: selectedID, from: node)
                        updateSelection(selectedID)
                        return
                    }
                }
            }

            // Check if we tapped an existing prop (SceneKit hit test)
            for hit in scnHits {
                if let nodeName = hit.node.name,
                   let propID = UUID(uuidString: nodeName),
                   propNodes[propID] != nil {
                    DispatchQueue.main.async {
                        self.parent.selectedPropID = propID
                    }
                    return
                }
                // Check parent nodes
                for (id, propNode) in propNodes {
                    if isDescendant(hit.node, of: propNode) {
                        DispatchQueue.main.async {
                            self.parent.selectedPropID = id
                        }
                        return
                    }
                }
            }

            // Place a new prop via ARKit raycast
            guard let asset = parent.selectedAsset else { return }
            guard let result = raycast(from: location) else { return }

            let hitPoint = simd_float3(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)

            let normal = extractNormal(from: result)
            let transform: simd_float4x4
            // If the surface is roughly horizontal (floor/table/ceiling), stand the prop upright
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

            DispatchQueue.main.async {
                self.parent.placedProps.append(prop)
                self.parent.selectedPropID = prop.id
            }
        }

        // MARK: - Pan (move prop or rotate via handle)

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView = sceneView,
                  let selectedID = parent.selectedPropID,
                  let node = propNodes[selectedID] else { return }

            switch gesture.state {
            case .began:
                isDragging = true
                sceneView.session.pause()
                lastDragLocation = gesture.location(in: sceneView)

                let location = gesture.location(in: sceneView)
                let hits = sceneView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

                // Check if we started dragging on a rotation ring
                var foundRingAxis: String?
                for hit in hits {
                    if let axis = PropNodeBuilder.rotationAxis(for: hit.node) {
                        foundRingAxis = axis
                        break
                    }
                }
                if let axis = foundRingAxis {
                    let axisVec = rotationAxisVector(axis, transform: node.simdTransform)
                    dragMode = .rotateAxis(axisVec)
                    gizmoNode?.isHidden = true
                } else {
                    dragMode = .move
                }

            case .changed:
                switch dragMode {
                case .rotateAxis(let axis):
                    let currentLocation = gesture.location(in: sceneView)
                    let angle = screenDragToRotationAngle(
                        from: lastDragLocation, to: currentLocation,
                        nodePosition: node.simdWorldPosition,
                        axis: axis, scnView: sceneView
                    )
                    lastDragLocation = currentLocation

                    if abs(angle) > 0.0001 {
                        let rotation = simd_quatf(angle: angle, axis: simd_normalize(axis))
                        let rotMatrix = simd_float4x4(rotation)
                        let pos = node.simdTransform.columns.3
                        var t = node.simdTransform
                        t.columns.3 = simd_float4(0, 0, 0, 1)
                        t = simd_mul(rotMatrix, t)
                        t.columns.3 = pos
                        node.simdTransform = t
                    }

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
                isDragging = false
                suppressTransformSync = true
                gizmoNode?.isHidden = false
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal, .vertical]
                config.environmentTexturing = .automatic
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
                sceneView.session.run(config)
                commitTransform(for: selectedID, from: node)

            default: break
            }
        }

        private func commitTransform(for propID: UUID, from node: SCNNode) {
            let finalTransform = node.simdTransform
            DispatchQueue.main.async {
                if let idx = self.parent.placedProps.firstIndex(where: { $0.id == propID }) {
                    self.parent.placedProps[idx].transform = CodableMatrix4x4(finalTransform)
                }
                self.suppressTransformSync = false
            }
        }

        // MARK: - Prop Sync

        func syncProps(_ props: [PlacedProp]) {
            guard let sceneView = sceneView else { return }
            if isDragging { return }

            let currentIDs = Set(props.map(\.id))
            let existingIDs = Set(propNodes.keys)

            // Remove deleted
            for id in existingIDs.subtracting(currentIDs) {
                propNodes[id]?.removeFromParentNode()
                propNodes.removeValue(forKey: id)
            }

            // Update existing
            for prop in props {
                if let existingNode = propNodes[prop.id] {
                    let needsUpdate: Bool
                    if let box = existingNode.childNode(withName: "propBox", recursively: false)?.geometry as? SCNBox {
                        needsUpdate = abs(Float(box.width) - prop.widthMeters) > 0.001
                                   || abs(Float(box.height) - prop.heightMeters) > 0.001
                                   || abs(Float(box.length) - prop.depthMeters) > 0.001
                    } else if let plane = existingNode.childNode(withName: "propPlane", recursively: false)?.geometry as? SCNPlane {
                        needsUpdate = abs(Float(plane.width) - prop.widthMeters) > 0.001
                                   || abs(Float(plane.height) - prop.heightMeters) > 0.001
                                   || prop.depthMeters > 0.001
                    } else {
                        needsUpdate = false
                    }
                    if needsUpdate {
                        let asset = findAsset(prop.assetID)
                        if let image = parent.assetStore.loadImage(for: asset) {
                            PropNodeBuilder.updateNodeSize(existingNode, prop: prop, image: image, assetName: asset.name)
                        }
                    }
                    if !suppressTransformSync {
                        existingNode.simdTransform = prop.transform.matrix
                    }
                }
            }

            // Add new
            for prop in props where propNodes[prop.id] == nil {
                let asset = findAsset(prop.assetID)
                if let image = parent.assetStore.loadImage(for: asset) {
                    let node = PropNodeBuilder.makeNode(for: prop, image: image, assetName: asset.name)
                    sceneView.scene.rootNode.addChildNode(node)
                    propNodes[prop.id] = node
                }
            }
        }

        // MARK: - Selection

        func updateSelection(_ selectedID: UUID?) {
            selectionHighlight?.removeFromParentNode()
            selectionHighlight = nil
            gizmoNode?.removeFromParentNode()
            gizmoNode = nil

            guard let selectedID = selectedID,
                  let node = propNodes[selectedID] else { return }

            let faceWidth: CGFloat
            let faceHeight: CGFloat
            if let box = node.childNode(withName: "propBox", recursively: false)?.geometry as? SCNBox {
                faceWidth = box.width
                faceHeight = box.height
            } else if let plane = node.childNode(withName: "propPlane", recursively: false)?.geometry as? SCNPlane {
                faceWidth = plane.width
                faceHeight = plane.height
            } else {
                return
            }

            // Yellow highlight outline
            let outline = SCNPlane(width: faceWidth + 0.02, height: faceHeight + 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.6)
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            outline.materials = [mat]
            let highlightNode = SCNNode(geometry: outline)
            highlightNode.position = SCNVector3(0, 0, -0.001)
            node.addChildNode(highlightNode)
            selectionHighlight = highlightNode

            // 3-axis rotation rings
            let gizmo = PropNodeBuilder.makeRotationGizmo(faceWidth: faceWidth, faceHeight: faceHeight)
            node.addChildNode(gizmo)
            gizmoNode = gizmo
        }

        /// Maps axis name ("X", "Y", "Z") to the actual world-space axis vector for the given prop transform.
        private func rotationAxisVector(_ axis: String, transform: simd_float4x4) -> simd_float3 {
            switch axis {
            case "X":
                return simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            case "Y":
                return simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            case "Z":
                return simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            default:
                return simd_float3(0, 1, 0)
            }
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

        private func screenDragToRotationAngle(
            from startPt: CGPoint, to endPt: CGPoint,
            nodePosition: simd_float3, axis: simd_float3,
            scnView: ARSCNView
        ) -> Float {
            let center3D = SCNVector3(nodePosition.x, nodePosition.y, nodePosition.z)
            let axisEnd3D = SCNVector3(nodePosition.x + axis.x, nodePosition.y + axis.y, nodePosition.z + axis.z)
            let centerScreen = scnView.projectPoint(center3D)
            let axisEndScreen = scnView.projectPoint(axisEnd3D)

            let axisScreenDir = CGPoint(x: CGFloat(axisEndScreen.x - centerScreen.x),
                                         y: CGFloat(axisEndScreen.y - centerScreen.y))

            let dragDx = endPt.x - startPt.x
            let dragDy = endPt.y - startPt.y

            let cross = axisScreenDir.x * dragDy - axisScreenDir.y * dragDx

            let dragMag = sqrt(dragDx * dragDx + dragDy * dragDy)
            let sign: Float = cross > 0 ? 1.0 : -1.0
            return sign * Float(dragMag) * 0.005
        }

        private func findAsset(_ assetID: UUID) -> ImageAsset {
            parent.assetStore.assets.first { $0.id == assetID } ?? ImageAsset(name: "Missing", filename: "", width: 1, height: 1)
        }

        private func isDescendant(_ node: SCNNode, of ancestor: SCNNode) -> Bool {
            var current: SCNNode? = node.parent
            while let n = current {
                if n === ancestor { return true }
                current = n.parent
            }
            return false
        }
    }
}
