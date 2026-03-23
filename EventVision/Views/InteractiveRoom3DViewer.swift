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
        context.coordinator.syncProps(placedProps)
        context.coordinator.updateSelection(selectedPropID)
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
        private var rotationHandleNode: SCNNode?
        private var yRotationHandleNode: SCNNode?

        // Drag state
        private enum DragMode { case move, rotateZ, rotateY }
        private var dragMode: DragMode = .move
        private var dragStartScreenZ: CGFloat = 0
        private var dragStartWorldPos: simd_float3 = .zero
        private var isDragging = false

        init(parent: InteractiveRoom3DViewer) {
            self.parent = parent
        }

        // MARK: - Gesture Delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer else { return true }
            guard let scnView = scnView, let selectedID = parent.selectedPropID else { return false }

            let location = gestureRecognizer.location(in: scnView)
            let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                // Allow if hitting either rotation handle
                if hit.node.name == "rotationHandle" || hit.node.name == "yRotationHandle" { return true }
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
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

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

        private var rotateStartTransform: simd_float4x4 = matrix_identity_float4x4

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView,
                  let selectedID = parent.selectedPropID,
                  let node = propNodes[selectedID] else { return }

            switch gesture.state {
            case .began:
                isDragging = true
                scnView.allowsCameraControl = false

                // Determine what we started dragging
                let location = gesture.location(in: scnView)
                let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])

                if hits.contains(where: { $0.node.name == "rotationHandle" }) {
                    dragMode = .rotateZ
                    rotateStartTransform = node.simdTransform
                } else if hits.contains(where: { $0.node.name == "yRotationHandle" }) {
                    dragMode = .rotateY
                    rotateStartTransform = node.simdTransform
                } else {
                    dragMode = .move
                    let projected = scnView.projectPoint(node.position)
                    dragStartScreenZ = CGFloat(projected.z)
                    dragStartWorldPos = node.simdWorldPosition
                }

            case .changed:
                let translation = gesture.translation(in: scnView)

                switch dragMode {
                case .rotateZ:
                    // Horizontal drag = rotation around surface normal (Z axis)
                    let angle = Float(translation.x) * 0.01
                    let localZ = simd_float3(rotateStartTransform.columns.2.x, rotateStartTransform.columns.2.y, rotateStartTransform.columns.2.z)
                    applyRotation(to: node, angle: angle, axis: localZ)

                case .rotateY:
                    // Horizontal drag = rotation around world Y axis (turntable)
                    let angle = Float(translation.x) * 0.01
                    applyRotation(to: node, angle: angle, axis: simd_float3(0, 1, 0))

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
                scnView.allowsCameraControl = true
                commitTransform(for: selectedID, from: node)

            default: break
            }
        }

        private func applyRotation(to node: SCNNode, angle: Float, axis: simd_float3) {
            let rotation = simd_quatf(angle: angle, axis: simd_normalize(axis))
            let rotMatrix = simd_float4x4(rotation)
            let pos = simd_float3(rotateStartTransform.columns.3.x, rotateStartTransform.columns.3.y, rotateStartTransform.columns.3.z)
            var t = rotateStartTransform
            t.columns.3 = simd_float4(0, 0, 0, 1)
            t = simd_mul(rotMatrix, t)
            t.columns.3 = simd_float4(pos, 1)
            node.simdTransform = t
        }

        // MARK: - Commit transform to binding

        private func commitTransform(for propID: UUID, from node: SCNNode) {
            DispatchQueue.main.async {
                if let idx = self.parent.placedProps.firstIndex(where: { $0.id == propID }) {
                    self.parent.placedProps[idx].transform = CodableMatrix4x4(node.simdTransform)
                }
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

                    // Sync transform (e.g. after commit from gesture)
                    existingNode.simdTransform = prop.transform.matrix
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
            rotationHandleNode?.removeFromParentNode()
            rotationHandleNode = nil
            yRotationHandleNode?.removeFromParentNode()
            yRotationHandleNode = nil

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

            // Rotation handle — circular arrow icon to the right of the prop
            let handleImage = renderRotationHandleImage()
            let handleSize: CGFloat = max(0.15, faceHeight * 0.35)
            let handlePlane = SCNPlane(width: handleSize, height: handleSize)
            let handleMat = SCNMaterial()
            handleMat.diffuse.contents = handleImage
            handleMat.lightingModel = .constant
            handleMat.isDoubleSided = true
            handlePlane.materials = [handleMat]

            let handle = SCNNode(geometry: handlePlane)
            handle.name = "rotationHandle"
            handle.position = SCNVector3(Float(faceWidth / 2) + Float(handleSize / 2) + 0.04, 0, 0.01)
            handle.constraints = [SCNBillboardConstraint()]
            node.addChildNode(handle)
            rotationHandleNode = handle

            // Y-axis rotation handle — below the prop, orange
            let yHandleImage = renderRotationHandleImage(color: .systemOrange, symbolName: "arrow.trianglehead.left.and.right.rotation")
            let yHandlePlane = SCNPlane(width: handleSize, height: handleSize)
            let yHandleMat = SCNMaterial()
            yHandleMat.diffuse.contents = yHandleImage
            yHandleMat.lightingModel = .constant
            yHandleMat.isDoubleSided = true
            yHandlePlane.materials = [yHandleMat]

            let yHandle = SCNNode(geometry: yHandlePlane)
            yHandle.name = "yRotationHandle"
            yHandle.position = SCNVector3(0, -Float(faceHeight / 2) - Float(handleSize / 2) - 0.04, 0.01)
            yHandle.constraints = [SCNBillboardConstraint()]
            node.addChildNode(yHandle)
            yRotationHandleNode = yHandle
        }

        private func renderRotationHandleImage(color: UIColor = .systemBlue, symbolName: String = "arrow.trianglehead.2.clockwise.rotate.90") -> UIImage {
            let size = CGSize(width: 80, height: 80)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                color.withAlphaComponent(0.85).setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()

                let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .bold)
                if let symbol = UIImage(systemName: symbolName, withConfiguration: config) {
                    let tinted = symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                    let symbolSize = tinted.size
                    let origin = CGPoint(x: (size.width - symbolSize.width) / 2, y: (size.height - symbolSize.height) / 2)
                    tinted.draw(at: origin)
                }
            }
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
