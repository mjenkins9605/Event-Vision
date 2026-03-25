import SceneKit
import UIKit

enum PropNodeBuilder {
    static func makeNode(for prop: PlacedProp, image: UIImage, assetName: String) -> SCNNode {
        let node = SCNNode()
        node.simdTransform = prop.transform.matrix
        node.name = prop.id.uuidString

        if prop.depthMeters > 0.001 {
            // 3D box: face textured with image, sides/back colored
            let box = SCNBox(
                width: CGFloat(prop.widthMeters),
                height: CGFloat(prop.heightMeters),
                length: CGFloat(prop.depthMeters),
                chamferRadius: 0
            )
            let faceMat = SCNMaterial()
            faceMat.diffuse.contents = image
            faceMat.lightingModel = .constant
            let sideMat = SCNMaterial()
            sideMat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.5)
            sideMat.lightingModel = .constant
            // SCNBox face order: front, right, back, left, top, bottom
            box.materials = [faceMat, sideMat, sideMat, sideMat, sideMat, sideMat]

            let boxNode = SCNNode(geometry: box)
            // Offset box so the front face sits at z=0 (flush with wall)
            boxNode.position = SCNVector3(0, 0, Float(prop.depthMeters) / 2)
            boxNode.name = "propBox"
            node.addChildNode(boxNode)

            // Floor footprint — a semi-transparent rectangle on the ground showing depth coverage
            addFloorFootprint(to: node, prop: prop)
        } else {
            // Flat plane (no depth)
            let plane = SCNPlane(width: CGFloat(prop.widthMeters), height: CGFloat(prop.heightMeters))
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.lightingModel = .constant
            plane.materials = [material]

            let planeNode = SCNNode(geometry: plane)
            planeNode.name = "propPlane"
            node.addChildNode(planeNode)
        }

        // Floating label above the prop
        let label = makePropLabel(assetName: assetName, widthMeters: prop.widthMeters, heightMeters: prop.heightMeters, depthMeters: prop.depthMeters)
        label.position = SCNVector3(0, Float(prop.heightMeters / 2) + 0.08, 0)
        label.constraints = [SCNBillboardConstraint()]
        node.addChildNode(label)

        return node
    }

    private static func addFloorFootprint(to node: SCNNode, prop: PlacedProp) {
        let footprint = SCNPlane(width: CGFloat(prop.widthMeters), height: CGFloat(prop.depthMeters))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemRed.withAlphaComponent(0.25)
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        footprint.materials = [mat]

        let footprintNode = SCNNode(geometry: footprint)
        // Rotate to lie flat on the ground (rotate -90 degrees around X)
        footprintNode.eulerAngles.x = -.pi / 2
        // Position at the bottom of the prop, centered along the depth
        let bottomY = -prop.heightMeters / 2
        footprintNode.position = SCNVector3(0, bottomY, Float(prop.depthMeters) / 2)
        footprintNode.name = "footprint"
        node.addChildNode(footprintNode)

        // Depth label on the footprint
        let depthStr = MeasurementFormatter.feetInches(prop.depthMeters)
        let depthLabel = makeImageLabel(text: "\(depthStr) deep", color: UIColor.systemRed)
        depthLabel.position = SCNVector3(0, bottomY + 0.01, Float(prop.depthMeters) + 0.06)
        depthLabel.constraints = [SCNBillboardConstraint()]
        depthLabel.name = "depthLabel"
        node.addChildNode(depthLabel)
    }

    static func updateNodeSize(_ node: SCNNode, prop: PlacedProp, image: UIImage, assetName: String) {
        // Remove all children and rebuild
        node.childNodes.forEach { $0.removeFromParentNode() }

        if prop.depthMeters > 0.001 {
            let box = SCNBox(
                width: CGFloat(prop.widthMeters),
                height: CGFloat(prop.heightMeters),
                length: CGFloat(prop.depthMeters),
                chamferRadius: 0
            )
            let faceMat = SCNMaterial()
            faceMat.diffuse.contents = image
            faceMat.lightingModel = .constant
            let sideMat = SCNMaterial()
            sideMat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.5)
            sideMat.lightingModel = .constant
            // SCNBox face order: front, right, back, left, top, bottom
            box.materials = [faceMat, sideMat, sideMat, sideMat, sideMat, sideMat]

            let boxNode = SCNNode(geometry: box)
            boxNode.position = SCNVector3(0, 0, Float(prop.depthMeters) / 2)
            boxNode.name = "propBox"
            node.addChildNode(boxNode)

            addFloorFootprint(to: node, prop: prop)
        } else {
            let plane = SCNPlane(width: CGFloat(prop.widthMeters), height: CGFloat(prop.heightMeters))
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.lightingModel = .constant
            plane.materials = [material]

            let planeNode = SCNNode(geometry: plane)
            planeNode.name = "propPlane"
            node.addChildNode(planeNode)
        }

        // Rebuild label
        let label = makePropLabel(assetName: assetName, widthMeters: prop.widthMeters, heightMeters: prop.heightMeters, depthMeters: prop.depthMeters)
        label.position = SCNVector3(0, Float(prop.heightMeters / 2) + 0.08, 0)
        label.constraints = [SCNBillboardConstraint()]
        node.addChildNode(label)
    }

    /// Build a transform that places a prop flush against a surface at the hit point.
    /// The prop faces outward along the surface normal.
    static func surfaceAlignedTransform(
        hitPoint: simd_float3,
        surfaceNormal: simd_float3
    ) -> simd_float4x4 {
        let normal = simd_normalize(surfaceNormal)

        // Choose an up hint that isn't parallel to the normal
        let upHint: simd_float3 = abs(simd_dot(normal, simd_float3(0, 1, 0))) > 0.99
            ? simd_float3(0, 0, 1)
            : simd_float3(0, 1, 0)

        let right = simd_normalize(simd_cross(upHint, normal))
        let up = simd_cross(normal, right)

        // Small offset along normal to prevent z-fighting
        let position = hitPoint + normal * 0.002

        var transform = simd_float4x4(1)
        transform.columns.0 = simd_float4(right, 0)
        transform.columns.1 = simd_float4(up, 0)
        transform.columns.2 = simd_float4(normal, 0)
        transform.columns.3 = simd_float4(position, 1)
        return transform
    }

    // MARK: - Rotation Gizmo Rings

    /// Builds 3 rotation rings (X=red, Y=green, Z=blue) around a prop.
    /// Each ring is an SCNTorus with arrow indicators. Returns a parent node containing all rings.
    static func makeRotationGizmo(faceWidth: CGFloat, faceHeight: CGFloat) -> SCNNode {
        let gizmo = SCNNode()
        gizmo.name = "rotationGizmo"

        let radius = CGFloat(max(Float(faceWidth), Float(faceHeight)) * 0.6 + 0.1)
        let visiblePipe: CGFloat = 0.008
        let hitPipe: CGFloat = 0.04  // Invisible fat tube for easy grabbing

        // X-axis ring (red) — pitch rotation
        let xRing = makeRing(radius: radius, visiblePipe: visiblePipe, hitPipe: hitPipe, color: .systemRed, name: "ringX")
        xRing.eulerAngles.z = .pi / 2
        gizmo.addChildNode(xRing)

        // Y-axis ring (green) — yaw/turntable rotation
        let yRing = makeRing(radius: radius, visiblePipe: visiblePipe, hitPipe: hitPipe, color: .systemGreen, name: "ringY")
        gizmo.addChildNode(yRing)

        // Z-axis ring (blue) — roll/spin on wall
        let zRing = makeRing(radius: radius, visiblePipe: visiblePipe, hitPipe: hitPipe, color: .systemBlue, name: "ringZ")
        zRing.eulerAngles.x = .pi / 2
        gizmo.addChildNode(zRing)

        // Arrow grab handles at 4 points on each ring
        addArrowIndicators(to: xRing, radius: radius, color: .systemRed)
        addArrowIndicators(to: yRing, radius: radius, color: .systemGreen)
        addArrowIndicators(to: zRing, radius: radius, color: .systemBlue)

        return gizmo
    }

    private static func makeRing(radius: CGFloat, visiblePipe: CGFloat, hitPipe: CGFloat, color: UIColor, name: String) -> SCNNode {
        let container = SCNNode()
        container.name = name

        // Visible thin ring
        let torus = SCNTorus(ringRadius: radius, pipeRadius: visiblePipe)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.7)
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        torus.materials = [mat]
        let visibleNode = SCNNode(geometry: torus)
        visibleNode.name = name
        container.addChildNode(visibleNode)

        // Invisible fat ring for hit testing
        let hitTorus = SCNTorus(ringRadius: radius, pipeRadius: hitPipe)
        let hitMat = SCNMaterial()
        hitMat.diffuse.contents = UIColor.clear
        hitMat.lightingModel = .constant
        hitMat.isDoubleSided = true
        hitMat.colorBufferWriteMask = []  // Invisible — doesn't render
        hitTorus.materials = [hitMat]
        let hitNode = SCNNode(geometry: hitTorus)
        hitNode.name = name
        hitNode.opacity = 0.001  // Nearly invisible but still hit-testable
        container.addChildNode(hitNode)

        return container
    }

    private static func addArrowIndicators(to ringNode: SCNNode, radius: CGFloat, color: UIColor) {
        let arrowImage = renderArrowImage(color: color)
        let arrowSize: CGFloat = 0.1

        // Place 4 arrows evenly around the ring for more grab targets
        for i in 0..<4 {
            let angle = Float(i) * (.pi / 2)
            let x = Float(radius) * cos(angle)
            let z = Float(radius) * sin(angle)

            let arrowPlane = SCNPlane(width: arrowSize, height: arrowSize)
            let mat = SCNMaterial()
            mat.diffuse.contents = arrowImage
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            arrowPlane.materials = [mat]

            let arrowNode = SCNNode(geometry: arrowPlane)
            arrowNode.position = SCNVector3(x, 0, z)
            arrowNode.constraints = [SCNBillboardConstraint()]
            arrowNode.name = ringNode.name
            ringNode.addChildNode(arrowNode)
        }
    }

    private static func renderArrowImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            color.withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()

            let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
            if let symbol = UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90", withConfiguration: config) {
                let tinted = symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                let symbolSize = tinted.size
                let origin = CGPoint(x: (size.width - symbolSize.width) / 2,
                                     y: (size.height - symbolSize.height) / 2)
                tinted.draw(at: origin)
            }
        }
    }

    /// Identifies which rotation axis a hit node belongs to. Returns "X", "Y", or "Z", or nil.
    static func rotationAxis(for node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let n = current {
            switch n.name {
            case "ringX": return "X"
            case "ringY": return "Y"
            case "ringZ": return "Z"
            default: break
            }
            current = n.parent
        }
        return nil
    }

    // MARK: - Label Rendering

    static func makePropLabel(assetName: String, widthMeters: Float, heightMeters: Float, depthMeters: Float = 0) -> SCNNode {
        let wStr = MeasurementFormatter.feetInches(widthMeters)
        let hStr = MeasurementFormatter.feetInches(heightMeters)
        var text = "\(assetName) \u{2014} \(wStr) \u{00D7} \(hStr)"
        if depthMeters > 0.001 {
            let dStr = MeasurementFormatter.feetInches(depthMeters)
            text += " \u{00D7} \(dStr)"
        }
        let node = makeImageLabel(text: text, color: UIColor(white: 0.2, alpha: 1.0))
        node.name = "propLabel"
        return node
    }

    static func makeImageLabel(text: String, color: UIColor) -> SCNNode {
        let image = renderLabelImage(text: text, bgColor: color)
        let aspect = image.size.width / image.size.height
        let labelHeight: CGFloat = 0.12
        let labelWidth = labelHeight * aspect

        let plane = SCNPlane(width: labelWidth, height: labelHeight)
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        plane.materials = [mat]
        return SCNNode(geometry: plane)
    }

    static func renderLabelImage(text: String, bgColor: UIColor) -> UIImage {
        let font = UIFont.systemFont(ofSize: 28, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 16
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            bgColor.withAlphaComponent(0.9).setFill()
            path.fill()
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
}
