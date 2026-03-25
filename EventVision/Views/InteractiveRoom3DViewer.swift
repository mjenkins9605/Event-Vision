import SwiftUI
import SceneKit
import simd

struct InteractiveRoom3DViewer: UIViewRepresentable {
    let scan: SavedScan
    let assetStore: AssetStore
    @Binding var placedProps: [PlacedProp]
    @Binding var selectedPropID: UUID?
    var selectedAsset: ImageAsset?
    var isPlacementMode: Bool
    var presetWidth: Float?
    var presetHeight: Float?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene
        context.coordinator.scnView = scnView
        context.coordinator.scene = scene

        // Build room geometry
        buildRoom(in: scene)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(0, 5, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        // Tap gesture for placement / selection
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        // Pan gesture for moving props or dragging rotation handle
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        scnView.addGestureRecognizer(pan)

        // Load existing placed props
        context.coordinator.syncProps(placedProps)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isDragging && !context.coordinator.suppressTransformSync {
            context.coordinator.syncProps(placedProps)
            context.coordinator.updateSelection(selectedPropID)
        }
    }

    // MARK: - Build Room (reuses Room3DViewer patterns)

    private func buildRoom(in scene: SCNScene) {
        var lowestY: Float = 0

        for wall in scan.walls {
            addSurface(to: scene, dimensions: wall.dimensions, transform: wall.simdTransform, color: UIColor.systemBlue.withAlphaComponent(0.3), edgeColor: .systemBlue)
            let bottomY = wall.simdTransform.columns.3.y - wall.dimensionsY / 2
            lowestY = min(lowestY, bottomY)
        }
        for door in scan.doors {
            addSurface(to: scene, dimensions: door.dimensions, transform: door.simdTransform, color: UIColor.systemGreen.withAlphaComponent(0.3), edgeColor: .systemGreen)
        }
        for window in scan.windows {
            addSurface(to: scene, dimensions: window.dimensions, transform: window.simdTransform, color: UIColor.systemOrange.withAlphaComponent(0.3), edgeColor: .systemOrange)
        }
        for opening in scan.openings {
            addSurface(to: scene, dimensions: opening.dimensions, transform: opening.simdTransform, color: UIColor.systemPurple.withAlphaComponent(0.3), edgeColor: .systemPurple)
        }

        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor.darkGray.withAlphaComponent(0.2)
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
        // Tag surface nodes so we can identify them in hit tests
        planeNode.name = "surface"
        scene.rootNode.addChildNode(planeNode)

        let tl = simd_make_float3(transform * simd_float4(-hw,  hh, 0, 1))
        let tr = simd_make_float3(transform * simd_float4( hw,  hh, 0, 1))
        let br = simd_make_float3(transform * simd_float4( hw, -hh, 0, 1))
        let bl = simd_make_float3(transform * simd_float4(-hw, -hh, 0, 1))

        addLine(to: scene, from: tl, to: tr, color: edgeColor)
        addLine(to: scene, from: tr, to: br, color: edgeColor)
        addLine(to: scene, from: br, to: bl, color: edgeColor)
        addLine(to: scene, from: bl, to: tl, color: edgeColor)

        let topMid = (tl + tr) / 2
        let widthLabel = PropNodeBuilder.makeImageLabel(text: MeasurementFormatter.feetInches(w), color: edgeColor)
        widthLabel.simdWorldPosition = topMid
        widthLabel.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(widthLabel)

        let leftMid = (tl + bl) / 2
        let heightLabel = PropNodeBuilder.makeImageLabel(text: MeasurementFormatter.feetInches(h), color: edgeColor)
        heightLabel.simdWorldPosition = leftMid
        heightLabel.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(heightLabel)
    }

    private func addLine(to scene: SCNScene, from a: simd_float3, to b: simd_float3, color: UIColor) {
        let vertices = [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)]
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: [UInt16(0), UInt16(1)], primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        geometry.materials = [mat]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: InteractiveRoom3DViewer
        weak var scnView: SCNView?
        var scene: SCNScene?
        var propNodes: [UUID: SCNNode] = [:]
        private var selectionHighlight: SCNNode?
        private var gizmoNode: SCNNode?

        // Drag state
        private enum DragMode { case move, rotateAxis(simd_float3) }
        private var dragMode: DragMode = .move
        private var dragStartScreenZ: CGFloat = 0
        private var dragStartWorldPos: simd_float3 = .zero
        var isDragging = false
        var suppressTransformSync = false
        private var lastDragLocation: CGPoint = .zero

        init(parent: InteractiveRoom3DViewer) {
            self.parent = parent
        }

        // MARK: - Gesture Delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer else { return true }
            guard let scnView = scnView, let selectedID = parent.selectedPropID else { return false }

            let location = gestureRecognizer.location(in: scnView)
            let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for hit in hits {
                // Allow if hitting a rotation ring
                if PropNodeBuilder.rotationAxis(for: hit.node) != nil { return true }
                // Allow if hitting the selected prop directly
                if let name = hit.node.name, let propID = UUID(uuidString: name), propID == selectedID {
                    return true
                }
                // Allow if hitting a child of the selected prop
                if let propNode = propNodes[selectedID], isDescendant(hit.node, of: propNode) {
                    return true
                }
            }
            return false
        }

        // MARK: - Tap (select / place)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView, parent.isPlacementMode else { return }

            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            // Check if we tapped a rotation ring — rotate 45° on that axis
            if let selectedID = parent.selectedPropID, let node = propNodes[selectedID] {
                for result in hitResults {
                    if let axis = PropNodeBuilder.rotationAxis(for: result.node) {
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

            // Check if we tapped an existing prop
            for result in hitResults {
                if let nodeName = result.node.name,
                   let propID = UUID(uuidString: nodeName),
                   propNodes[propID] != nil {
                    DispatchQueue.main.async {
                        self.parent.selectedPropID = propID
                    }
                    return
                }
            }

            // Check if we tapped a surface — place a new prop
            guard let asset = parent.selectedAsset else { return }

            for result in hitResults {
                if result.node.name == "surface" {
                    let hitPoint = simd_float3(result.worldCoordinates.x, result.worldCoordinates.y, result.worldCoordinates.z)
                    var normal = simd_float3(result.worldNormal.x, result.worldNormal.y, result.worldNormal.z)

                    // Ensure the prop faces the camera — flip normal if it points away
                    if let cameraPos = scnView.pointOfView?.simdWorldPosition {
                        let toCamera = cameraPos - hitPoint
                        if simd_dot(normal, toCamera) < 0 {
                            normal = -normal
                        }
                    }

                    let transform = PropNodeBuilder.surfaceAlignedTransform(hitPoint: hitPoint, surfaceNormal: normal)

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
                    return
                }
            }
        }

        // MARK: - Pan (move prop or rotate via handle)

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView,
                  let selectedID = parent.selectedPropID,
                  let node = propNodes[selectedID] else { return }

            switch gesture.state {
            case .began:
                isDragging = true
                scnView.allowsCameraControl = false
                lastDragLocation = gesture.location(in: scnView)

                // Determine what we started dragging
                let location = gesture.location(in: scnView)
                let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

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
                    let projected = scnView.projectPoint(node.position)
                    dragStartScreenZ = CGFloat(projected.z)
                    dragStartWorldPos = node.simdWorldPosition
                }

            case .changed:
                switch dragMode {
                case .rotateAxis(let axis):
                    let currentLocation = gesture.location(in: scnView)
                    let angle = screenDragToRotationAngle(
                        from: lastDragLocation, to: currentLocation,
                        nodePosition: node.simdWorldPosition,
                        axis: axis, scnView: scnView
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
                    let location = gesture.location(in: scnView)
                    let unprojected = scnView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), Float(dragStartScreenZ)))
                    let newWorldPos = simd_float3(unprojected.x, unprojected.y, unprojected.z)
                    let delta = newWorldPos - dragStartWorldPos

                    if let idx = parent.placedProps.firstIndex(where: { $0.id == selectedID }) {
                        var original = parent.placedProps[idx].transform.matrix
                        original.columns.3 = simd_float4(
                            dragStartWorldPos.x + delta.x,
                            dragStartWorldPos.y + delta.y,
                            dragStartWorldPos.z + delta.z,
                            1
                        )
                        node.simdTransform = original
                    }
                }

            case .ended, .cancelled:
                isDragging = false
                suppressTransformSync = true
                scnView.allowsCameraControl = true
                gizmoNode?.isHidden = false
                commitTransform(for: selectedID, from: node)

            default: break
            }
        }

        // MARK: - Commit transform to binding

        private func commitTransform(for propID: UUID, from node: SCNNode) {
            let finalTransform = node.simdTransform
            DispatchQueue.main.async {
                if let idx = self.parent.placedProps.firstIndex(where: { $0.id == propID }) {
                    self.parent.placedProps[idx].transform = CodableMatrix4x4(finalTransform)
                }
                // Allow sync again after binding is updated
                self.suppressTransformSync = false
            }
        }

        // MARK: - Sync & Selection

        func syncProps(_ props: [PlacedProp]) {
            guard let scene = scene else { return }
            // Don't sync transforms while user is dragging
            if isDragging { return }

            let currentIDs = Set(props.map(\.id))
            let existingIDs = Set(propNodes.keys)

            // Remove nodes for deleted props
            for id in existingIDs.subtracting(currentIDs) {
                propNodes[id]?.removeFromParentNode()
                propNodes.removeValue(forKey: id)
            }

            // Update existing nodes whose size changed
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

                    // Sync transform — skip if we just finished a gesture
                    // to avoid snapping back to stale binding data
                    if !suppressTransformSync {
                        existingNode.simdTransform = prop.transform.matrix
                    }
                }
            }

            // Add nodes for new props
            for prop in props where propNodes[prop.id] == nil {
                let asset = findAsset(prop.assetID)
                if let image = parent.assetStore.loadImage(for: asset) {
                    let node = PropNodeBuilder.makeNode(for: prop, image: image, assetName: asset.name)
                    scene.rootNode.addChildNode(node)
                    propNodes[prop.id] = node
                }
            }
        }

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

        /// Converts a screen-space drag into a rotation angle that feels natural.
        /// Projects the rotation axis to screen space, then uses the perpendicular
        /// component of the drag to determine rotation magnitude and direction.
        private func screenDragToRotationAngle(
            from startPt: CGPoint, to endPt: CGPoint,
            nodePosition: simd_float3, axis: simd_float3,
            scnView: SCNView
        ) -> Float {
            // Project the node center and a point along the axis to screen space
            let center3D = SCNVector3(nodePosition.x, nodePosition.y, nodePosition.z)
            let axisEnd3D = SCNVector3(nodePosition.x + axis.x, nodePosition.y + axis.y, nodePosition.z + axis.z)
            let centerScreen = scnView.projectPoint(center3D)
            let axisEndScreen = scnView.projectPoint(axisEnd3D)

            // Screen-space axis direction
            let axisScreenDir = CGPoint(x: CGFloat(axisEndScreen.x - centerScreen.x),
                                         y: CGFloat(axisEndScreen.y - centerScreen.y))

            // Drag vector
            let dragDx = endPt.x - startPt.x
            let dragDy = endPt.y - startPt.y

            // Cross product (2D) of axis direction with drag direction gives signed rotation
            let cross = axisScreenDir.x * dragDy - axisScreenDir.y * dragDx

            // Scale: total drag magnitude gives speed, cross sign gives direction
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
