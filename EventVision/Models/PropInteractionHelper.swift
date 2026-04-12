import SceneKit
import simd

/// Shared prop interaction logic used by both the offline 3D viewer
/// (`InteractiveRoom3DViewer.Coordinator`) and the live AR viewer
/// (`ARPlaceSceneView.Coordinator`).
class PropInteractionHelper {
    enum InteractionMode { case move, rotate }
    var interactionMode: InteractionMode = .move

    var propNodes: [UUID: SCNNode] = [:]
    private(set) var selectionHighlight: SCNNode?
    private(set) var gizmoNode: SCNNode?

    // Drag state
    enum DragMode { case move, rotateAxis(simd_float3) }
    var dragMode: DragMode = .move
    var isDragging = false
    var suppressTransformSync = false
    var lastDragLocation: CGPoint = .zero

    // MARK: - Prop Sync

    /// Diffs `propNodes` against the current `props` array: removes deleted,
    /// updates resized, adds new. Skips transform sync while dragging or suppressed.
    func syncProps(
        _ props: [PlacedProp],
        rootNode: SCNNode,
        assetStore: AssetStore
    ) {
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
                    let asset = findAsset(prop.assetID, in: assetStore)
                    if let image = assetStore.loadImage(for: asset) {
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
            let asset = findAsset(prop.assetID, in: assetStore)
            if let image = assetStore.loadImage(for: asset) {
                let node = PropNodeBuilder.makeNode(for: prop, image: image, assetName: asset.name)
                rootNode.addChildNode(node)
                propNodes[prop.id] = node

                // Placement bounce animation
                node.scale = SCNVector3(0.01, 0.01, 0.01)
                let bounce = SCNAction.sequence([
                    SCNAction.scale(to: 1.08, duration: 0.2),
                    SCNAction.scale(to: 1.0, duration: 0.12)
                ])
                bounce.timingMode = .easeOut
                node.runAction(bounce)
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

        // 3-axis rotation rings (only in rotate mode)
        if interactionMode == .rotate {
            let gizmo = PropNodeBuilder.makeRotationGizmo(faceWidth: faceWidth, faceHeight: faceHeight)
            node.addChildNode(gizmo)
            gizmoNode = gizmo
        }
    }

    // MARK: - Rotation

    /// Maps axis name ("X", "Y", "Z") to the world-space axis vector from the prop transform.
    func rotationAxisVector(_ axis: String, transform: simd_float4x4) -> simd_float3 {
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

    /// Applies a 45-degree rotation on the given axis to the node. Returns the updated transform.
    func applyRotation45(to node: SCNNode, axis: String) {
        let rotAxis = rotationAxisVector(axis, transform: node.simdTransform)
        let rotation = simd_quatf(angle: .pi / 4, axis: simd_normalize(rotAxis))
        let rotMatrix = simd_float4x4(rotation)
        let pos = simd_float3(node.simdTransform.columns.3.x, node.simdTransform.columns.3.y, node.simdTransform.columns.3.z)
        var t = node.simdTransform
        t.columns.3 = simd_float4(0, 0, 0, 1)
        t = simd_mul(rotMatrix, t)
        t.columns.3 = simd_float4(pos, 1)
        node.simdTransform = t
    }

    /// Applies incremental drag rotation on the given axis. Updates `lastDragLocation`.
    func applyDragRotation(to node: SCNNode, axis: simd_float3, currentLocation: CGPoint, scnView: SCNView) {
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
    }

    /// Converts a screen-space drag into a rotation angle using 2D cross product
    /// of the projected axis direction and drag vector.
    func screenDragToRotationAngle(
        from startPt: CGPoint, to endPt: CGPoint,
        nodePosition: simd_float3, axis: simd_float3,
        scnView: SCNView
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

    // MARK: - Transform Commit

    /// Writes the node's current transform to the binding asynchronously,
    /// then clears `suppressTransformSync`.
    func commitTransform(for propID: UUID, from node: SCNNode, updateBinding: @escaping (UUID, simd_float4x4) -> Void) {
        let finalTransform = node.simdTransform
        DispatchQueue.main.async {
            updateBinding(propID, finalTransform)
            self.suppressTransformSync = false
        }
    }

    /// Ends a drag gesture: resets drag state, restores gizmo visibility,
    /// and prepares for transform commit.
    func endDrag() {
        isDragging = false
        suppressTransformSync = true
        if interactionMode == .rotate {
            gizmoNode?.isHidden = false
        }
    }

    // MARK: - Gesture Helpers

    /// Checks whether a pan gesture should begin based on hitting the selected prop or its rotation rings.
    /// In `.move` mode, only prop body hits are allowed. In `.rotate` mode, only ring hits are allowed.
    func shouldBeginPan(at location: CGPoint, in scnView: SCNView, selectedID: UUID?) -> Bool {
        guard let selectedID = selectedID else { return false }
        let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

        switch interactionMode {
        case .move:
            for hit in hits {
                if PropNodeBuilder.rotationAxis(for: hit.node) != nil { continue }
                if let name = hit.node.name, let propID = UUID(uuidString: name), propID == selectedID {
                    return true
                }
                if let propNode = propNodes[selectedID], isDescendant(hit.node, of: propNode) {
                    if PropNodeBuilder.rotationAxis(for: hit.node) != nil { continue }
                    return true
                }
            }
            return false

        case .rotate:
            for hit in hits {
                if PropNodeBuilder.rotationAxis(for: hit.node) != nil { return true }
            }
            return false
        }
    }

    /// Detects which rotation ring (if any) was hit, and configures drag mode accordingly.
    /// In `.move` mode, always sets `.move`. In `.rotate` mode, detects which ring was hit.
    func detectDragMode(at location: CGPoint, in scnView: SCNView, nodeTransform: simd_float4x4) -> String? {
        switch interactionMode {
        case .move:
            dragMode = .move
            return nil

        case .rotate:
            let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for hit in hits {
                if let axis = PropNodeBuilder.rotationAxis(for: hit.node) {
                    let axisVec = rotationAxisVector(axis, transform: nodeTransform)
                    dragMode = .rotateAxis(axisVec)
                    gizmoNode?.isHidden = true
                    return axis
                }
            }
            dragMode = .move
            return nil
        }
    }

    // MARK: - Utility

    func findAsset(_ assetID: UUID, in assetStore: AssetStore) -> ImageAsset {
        assetStore.assets.first { $0.id == assetID } ?? ImageAsset(name: "Missing", filename: "", width: 1, height: 1)
    }

    func isDescendant(_ node: SCNNode, of ancestor: SCNNode) -> Bool {
        var current: SCNNode? = node.parent
        while let n = current {
            if n === ancestor { return true }
            current = n.parent
        }
        return false
    }

    /// Finds the first prop hit in a SceneKit hit test results array.
    func findTappedProp(in hits: [SCNHitTestResult]) -> UUID? {
        for hit in hits {
            if let nodeName = hit.node.name,
               let propID = UUID(uuidString: nodeName),
               propNodes[propID] != nil {
                return propID
            }
            for (id, propNode) in propNodes {
                if isDescendant(hit.node, of: propNode) {
                    return id
                }
            }
        }
        return nil
    }

    /// Checks hit results for a rotation ring tap and applies 45-degree rotation if found.
    /// Returns true if a ring was hit and rotation applied. Only active in `.rotate` mode.
    func handleRingTap(in hits: [SCNHitTestResult], selectedID: UUID?) -> Bool {
        guard interactionMode == .rotate else { return false }
        guard let selectedID = selectedID,
              let node = propNodes[selectedID] else { return false }
        for hit in hits {
            if let axis = PropNodeBuilder.rotationAxis(for: hit.node) {
                applyRotation45(to: node, axis: axis)
                return true
            }
        }
        return false
    }
}
