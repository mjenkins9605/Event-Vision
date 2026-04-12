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
    var interactionMode: PropInteractionHelper.InteractionMode = .move

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
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
        context.coordinator.scnView = scnView
        context.coordinator.scene = scene

        // Build room geometry
        buildRoom(in: scene)

        // Compute room center for better orbit target
        var center = simd_float3.zero
        var surfaceCount: Float = 0
        for wall in scan.walls {
            center += simd_make_float3(wall.simdTransform.columns.3)
            surfaceCount += 1
        }
        if surfaceCount > 0 { center /= surfaceCount }

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(center.x, center.y + 5, center.z + 5)
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        scnView.defaultCameraController.target = SCNVector3(center.x, center.y, center.z)

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
        context.coordinator.helper.interactionMode = interactionMode
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
        let helper = PropInteractionHelper()

        // Move-specific drag state (offline viewer uses unproject, not raycast)
        private var dragStartScreenZ: CGFloat = 0
        private var dragStartWorldPos: simd_float3 = .zero

        // Wall snap state
        private var snappedWall: SavedSurface?
        private var preSnapOrientation: simd_float4x4?
        private let snapDistance: Float = 0.2
        private let unsnapDistance: Float = 0.35
        private let snapFeedback = UIImpactFeedbackGenerator(style: .medium)
        private let unsnapFeedback = UIImpactFeedbackGenerator(style: .light)

        var isDragging: Bool { helper.isDragging }
        var suppressTransformSync: Bool { helper.suppressTransformSync }

        init(parent: InteractiveRoom3DViewer) {
            self.parent = parent
        }

        // MARK: - Gesture Delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer else { return true }
            guard let scnView = scnView else { return false }
            let location = gestureRecognizer.location(in: scnView)
            return helper.shouldBeginPan(at: location, in: scnView, selectedID: parent.selectedPropID)
        }

        // MARK: - Tap (select / place)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView, parent.isPlacementMode else { return }

            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            // Check if we tapped a rotation ring
            if helper.handleRingTap(in: hitResults, selectedID: parent.selectedPropID) {
                if let selectedID = parent.selectedPropID, let node = helper.propNodes[selectedID] {
                    commitTransform(for: selectedID, from: node)
                    helper.updateSelection(selectedID)
                }
                return
            }

            // Check if we tapped an existing prop
            if let propID = helper.findTappedProp(in: hitResults) {
                DispatchQueue.main.async {
                    self.parent.selectedPropID = propID
                }
                return
            }

            // Check if we tapped a surface — place a new prop
            guard let asset = parent.selectedAsset else { return }

            for result in hitResults {
                if result.node.name == "surface" {
                    let hitPoint = simd_float3(result.worldCoordinates.x, result.worldCoordinates.y, result.worldCoordinates.z)
                    var normal = simd_float3(result.worldNormal.x, result.worldNormal.y, result.worldNormal.z)

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
                  let node = helper.propNodes[selectedID] else { return }

            switch gesture.state {
            case .began:
                helper.isDragging = true
                scnView.allowsCameraControl = false
                helper.lastDragLocation = gesture.location(in: scnView)
                snappedWall = nil
                preSnapOrientation = nil

                let location = gesture.location(in: scnView)
                if helper.detectDragMode(at: location, in: scnView, nodeTransform: node.simdTransform) == nil {
                    // Move mode — capture start position for unproject
                    let projected = scnView.projectPoint(node.position)
                    dragStartScreenZ = CGFloat(projected.z)
                    dragStartWorldPos = node.simdWorldPosition
                }

            case .changed:
                switch helper.dragMode {
                case .rotateAxis(let axis):
                    let currentLocation = gesture.location(in: scnView)
                    helper.applyDragRotation(to: node, axis: axis, currentLocation: currentLocation, scnView: scnView)

                case .move:
                    let location = gesture.location(in: scnView)
                    let unprojected = scnView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), Float(dragStartScreenZ)))
                    let newWorldPos = simd_float3(unprojected.x, unprojected.y, unprojected.z)
                    let delta = newWorldPos - dragStartWorldPos
                    let targetPos = dragStartWorldPos + delta

                    guard let idx = parent.placedProps.firstIndex(where: { $0.id == selectedID }) else { break }
                    let prop = parent.placedProps[idx]

                    if let wall = snappedWall {
                        // Currently snapped — slide along wall or unsnap
                        let wallNormal = simd_normalize(simd_make_float3(wall.simdTransform.columns.2))
                        let wallCenter = simd_make_float3(wall.simdTransform.columns.3)
                        let distToPlane = abs(simd_dot(targetPos - wallCenter, wallNormal))

                        if distToPlane > unsnapDistance {
                            // Unsnap — restore original orientation
                            snappedWall = nil
                            if let preSnap = preSnapOrientation {
                                var restored = preSnap
                                restored.columns.3 = simd_float4(targetPos, 1)
                                node.simdTransform = restored
                                preSnapOrientation = nil
                            }
                            unsnapFeedback.impactOccurred()
                        } else {
                            // Slide along wall
                            let projected = targetPos - simd_dot(targetPos - wallCenter, wallNormal) * wallNormal
                            var t = wallAlignedOrientation(wallNormal: wallNormal)
                            t.columns.3 = simd_float4(projected, 1)
                            node.simdTransform = t
                        }
                    } else {
                        // Not snapped — check proximity to walls
                        var didSnap = false
                        for wall in parent.scan.walls {
                            let wallNormal = simd_normalize(simd_make_float3(wall.simdTransform.columns.2))
                            let wallCenter = simd_make_float3(wall.simdTransform.columns.3)
                            let dist = abs(simd_dot(targetPos - wallCenter, wallNormal))

                            if dist < snapDistance && isWithinWallBounds(targetPos, wall: wall, tolerance: 0.3) {
                                // Snap to this wall
                                snappedWall = wall
                                preSnapOrientation = parent.placedProps[idx].transform.matrix

                                let projected = targetPos - simd_dot(targetPos - wallCenter, wallNormal) * wallNormal
                                let halfDepth = prop.depthMeters / 2
                                let finalPos = projected + wallNormal * halfDepth

                                var t = wallAlignedOrientation(wallNormal: wallNormal)
                                t.columns.3 = simd_float4(finalPos, 1)
                                node.simdTransform = t

                                snapFeedback.impactOccurred()
                                didSnap = true
                                break
                            }
                        }

                        if !didSnap {
                            // Free movement (original behavior)
                            var original = parent.placedProps[idx].transform.matrix
                            original.columns.3 = simd_float4(targetPos, 1)
                            node.simdTransform = original
                        }
                    }
                }

            case .ended, .cancelled:
                snappedWall = nil
                preSnapOrientation = nil
                helper.endDrag()
                scnView.allowsCameraControl = true
                commitTransform(for: selectedID, from: node)

            default: break
            }
        }

        // MARK: - Commit transform to binding

        private func commitTransform(for propID: UUID, from node: SCNNode) {
            helper.commitTransform(for: propID, from: node) { [weak self] (id: UUID, transform: simd_float4x4) in
                if let idx = self?.parent.placedProps.firstIndex(where: { $0.id == id }) {
                    self?.parent.placedProps[idx].transform = CodableMatrix4x4(transform)
                }
            }
        }

        // MARK: - Wall Snap Helpers

        /// Builds an orientation matrix with the prop facing outward from a wall.
        private func wallAlignedOrientation(wallNormal: simd_float3) -> simd_float4x4 {
            let forward = wallNormal
            let worldUp = simd_float3(0, 1, 0)
            var right = simd_cross(worldUp, forward)
            if simd_length(right) < 0.001 {
                // Wall is horizontal (ceiling/floor)
                right = simd_cross(simd_float3(0, 0, 1), forward)
            }
            right = simd_normalize(right)
            let up = simd_normalize(simd_cross(forward, right))

            var m = matrix_identity_float4x4
            m.columns.0 = simd_float4(right, 0)
            m.columns.1 = simd_float4(up, 0)
            m.columns.2 = simd_float4(forward, 0)
            return m
        }

        /// Checks if a point is within the wall&rsquo;s rectangular bounds (with tolerance).
        private func isWithinWallBounds(_ point: simd_float3, wall: SavedSurface, tolerance: Float) -> Bool {
            let inv = simd_inverse(wall.simdTransform)
            let local = simd_make_float3(inv * simd_float4(point, 1))
            let halfW = wall.dimensionsX / 2 + tolerance
            let halfH = wall.dimensionsY / 2 + tolerance
            return abs(local.x) <= halfW && abs(local.y) <= halfH
        }

        // MARK: - Sync & Selection (delegates to helper)

        func syncProps(_ props: [PlacedProp]) {
            guard let scene = scene else { return }
            helper.syncProps(props, rootNode: scene.rootNode, assetStore: parent.assetStore)
        }

        func updateSelection(_ selectedID: UUID?) {
            helper.updateSelection(selectedID)
        }
    }
}
