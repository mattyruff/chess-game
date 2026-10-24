import SwiftUI
import SceneKit
import ChessCore

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
private typealias SceneScalar = CGFloat
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
private typealias SceneScalar = Float

private extension UIBezierPath {
    func line(to point: CGPoint) { addLine(to: point) }
    func curve(to point: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}
#endif

/// A self-contained, asset-free studio set with sculpted Staunton pieces.
@MainActor
final class ChessScene: NSObject, ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    var onSquareTapped: ((Square) -> Void)?

    private let moveDuration: TimeInterval = 0.85
    private let piecesRoot = SCNNode()
    private let markersRoot = SCNNode()
    private var pieceNodes: [Square: SCNNode] = [:]
    private var renderedPieces: [Square: Piece] = [:]
    private var cameraSide: Side?
    private let pieceHeight: SceneScalar = 0.066
    private lazy var ivory = Self.material(color: Self.color(0.91, 0.865, 0.75), roughness: 0.23, metalness: 0.035)
    private lazy var ebony = Self.material(color: Self.color(0.032, 0.039, 0.047), roughness: 0.22, metalness: 0.12)
    private lazy var ivoryDetail = Self.material(color: Self.color(0.66, 0.57, 0.39), roughness: 0.34, metalness: 0.25)
    private lazy var ebonyDetail = Self.material(color: Self.color(0.11, 0.12, 0.13), roughness: 0.28, metalness: 0.25)

    override init() {
        super.init()
        buildStudio()
        buildBoard()
        scene.rootNode.addChildNode(markersRoot)
        scene.rootNode.addChildNode(piecesRoot)
    }

    func update(position: Position, selected: Square?, legalTargets: [Square],
                lastMove: Move?, perspective: Side, animated: Bool) {
        var next: [Square: Piece] = [:]
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                if let piece = position.piece(at: square) { next[square] = piece }
            }
        }
        if next != renderedPieces {
            updatePieces(next, lastMove: lastMove, animated: animated)
            renderedPieces = next
        }
        updateMarkers(selected: selected, legalTargets: legalTargets, lastMove: lastMove)
        updateCamera(perspective, animated: animated)
    }

    func handleHit(at point: CGPoint, in view: SCNView) {
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .categoryBitMask: 1,
            .ignoreHiddenNodes: true
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let candidate = node {
                if let name = candidate.name, name.hasPrefix("square:") {
                    let fields = name.split(separator: ":")
                    if fields.count == 3, let file = Int(fields[1]), let rank = Int(fields[2]) {
                        onSquareTapped?(Square(file: file, rank: rank))
                        return
                    }
                }
                node = candidate.parent
            }
        }
    }

    // MARK: - Board and studio

    private func buildStudio() {
        scene.background.contents = Self.color(0.035, 0.047, 0.055)
        scene.lightingEnvironment.contents = Self.environmentTexture()
        scene.lightingEnvironment.intensity = 0.75

        let camera = SCNCamera()
        camera.fieldOfView = 39
        camera.zNear = 0.1
        camera.zFar = 70
        camera.wantsHDR = true
        camera.exposureOffset = 0.2
        camera.bloomIntensity = 0.12
        camera.bloomThreshold = 1.2
        camera.bloomBlurRadius = 4
        camera.screenSpaceAmbientOcclusionIntensity = 0.7
        camera.screenSpaceAmbientOcclusionRadius = 1.5
        camera.screenSpaceAmbientOcclusionBias = 0.035
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        updateCamera(.white, animated: false)

        let key = SCNLight()
        key.type = .directional
        key.color = Self.color(1, 0.91, 0.77)
        key.intensity = 1400
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowRadius = 5
        key.shadowColor = Self.color(0, 0, 0, 0.58)
        key.orthographicScale = 14
        key.zNear = 0.1
        key.zFar = 35
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-5, 10, 6)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        addLight(position: SCNVector3(6, 5, 1), color: Self.color(0.72, 0.83, 1), intensity: 550)
        addLight(position: SCNVector3(0, 6, -6), color: Self.color(1, 0.88, 0.66), intensity: 900)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = Self.color(0.68, 0.75, 0.85)
        ambient.intensity = 130
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let floor = SCNFloor()
        floor.reflectivity = 0.06
        floor.reflectionFalloffEnd = 8
        floor.materials = [Self.material(color: Self.color(0.055, 0.07, 0.077), roughness: 0.76)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.43
        floorNode.categoryBitMask = 2
        scene.rootNode.addChildNode(floorNode)
    }

    private func addLight(position: SCNVector3, color: PlatformColor, intensity: CGFloat) {
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = intensity
        light.attenuationStartDistance = 2
        light.attenuationEndDistance = 22
        let node = SCNNode()
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private func buildBoard() {
        let wood = Self.material(color: Self.color(0.25, 0.12, 0.055), roughness: 0.34)
        wood.diffuse.contents = Self.woodTexture(base: (0.26, 0.135, 0.065), variation: 0.1)
        let plinth = SCNBox(width: 9.08, height: 0.38, length: 9.08, chamferRadius: 0.11)
        plinth.materials = [wood]
        let plinthNode = SCNNode(geometry: plinth)
        plinthNode.position.y = -0.20
        plinthNode.categoryBitMask = 2
        scene.rootNode.addChildNode(plinthNode)

        let brass = Self.material(color: Self.color(0.61, 0.45, 0.22), roughness: 0.32, metalness: 0.72)
        for offset in [-1.0, 1.0] {
            let across = SCNBox(width: 8.15, height: 0.017, length: 0.025, chamferRadius: 0.006)
            across.materials = [brass]
            let acrossNode = SCNNode(geometry: across)
            acrossNode.position = SCNVector3(0, 0.012, SceneScalar(offset * 4.065))
            acrossNode.categoryBitMask = 2
            scene.rootNode.addChildNode(acrossNode)
            let along = SCNBox(width: 0.025, height: 0.017, length: 8.15, chamferRadius: 0.006)
            along.materials = [brass]
            let alongNode = SCNNode(geometry: along)
            alongNode.position = SCNVector3(SceneScalar(offset * 4.065), 0.012, 0)
            alongNode.categoryBitMask = 2
            scene.rootNode.addChildNode(alongNode)
        }

        let light = Self.material(color: Self.color(0.77, 0.65, 0.46), roughness: 0.39)
        light.diffuse.contents = Self.woodTexture(base: (0.76, 0.66, 0.49), variation: 0.055)
        let dark = Self.material(color: Self.color(0.21, 0.12, 0.073), roughness: 0.34)
        dark.diffuse.contents = Self.woodTexture(base: (0.23, 0.13, 0.077), variation: 0.07)
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                let geometry = SCNBox(width: 0.996, height: 0.10, length: 0.996, chamferRadius: 0.009)
                geometry.materials = [(file + rank).isMultiple(of: 2) ? dark : light]
                let node = SCNNode(geometry: geometry)
                node.name = name(for: square)
                node.position = boardPoint(square, height: 0)
                node.castsShadow = false
                scene.rootNode.addChildNode(node)
            }
        }
        let letters = Array("ABCDEFGH")
        for i in 0..<8 {
            addLabel(String(letters[i]), at: SCNVector3(SceneScalar(i) - 3.5, 0.015, 4.28), flipped: false)
            addLabel(String(letters[i]), at: SCNVector3(SceneScalar(i) - 3.5, 0.015, -4.28), flipped: true)
            addLabel(String(i + 1), at: SCNVector3(-4.28, 0.015, 3.5 - SceneScalar(i)), flipped: false)
            addLabel(String(i + 1), at: SCNVector3(4.28, 0.015, 3.5 - SceneScalar(i)), flipped: true)
        }
    }

    private func addLabel(_ string: String, at position: SCNVector3, flipped: Bool) {
        let text = SCNText(string: string, extrusionDepth: 0.001)
        text.font = PlatformFont.systemFont(ofSize: 0.18, weight: .medium)
        text.flatness = 0.2
        text.materials = [Self.material(color: Self.color(0.77, 0.63, 0.40), roughness: 0.6)]
        let node = SCNNode(geometry: text)
        let bounds = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((bounds.min.x + bounds.max.x) / 2,
                                             (bounds.min.y + bounds.max.y) / 2, 0)
        node.eulerAngles = SCNVector3(-SceneScalar.pi / 2, 0, flipped ? SceneScalar.pi : 0)
        node.position = position
        node.categoryBitMask = 2
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    private func updateCamera(_ side: Side, animated: Bool) {
        guard cameraSide != side else { return }
        let hadCamera = cameraSide != nil
        cameraSide = side
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated && hadCamera ? 0.7 : 0
        cameraNode.position = SCNVector3(0, 11.8, side == .white ? 12.4 : -12.4)
        cameraNode.look(at: SCNVector3(0, 0.05, 0))
        SCNTransaction.commit()
    }

    // MARK: - Piece geometry

    private func makePiece(_ piece: Piece, at square: Square) -> SCNNode {
        let root = SCNNode()
        root.name = name(for: square)
        root.position = boardPoint(square, height: pieceHeight)
        let body = piece.side == .white ? ivory : ebony
        let detail = piece.side == .white ? ivoryDetail : ebonyDetail

        // Broad weighted foot, concentric mouldings, and a tapered pedestal.
        addLathe([(0, 0.31), (0.025, 0.35), (0.06, 0.365), (0.10, 0.35),
                  (0.125, 0.31), (0.155, 0.305), (0.18, 0.28), (0.205, 0.275),
                  (0.23, 0.24)], to: root, material: body)
        addTorus(radius: 0.333, tube: 0.009, y: 0.075, to: root, material: detail)
        addTorus(radius: 0.292, tube: 0.008, y: 0.161, to: root, material: detail)

        switch piece.kind {
        case .pawn:
            addLathe([(0.22, 0.24), (0.27, 0.20), (0.32, 0.15), (0.45, 0.125),
                      (0.54, 0.155), (0.56, 0.205), (0.60, 0.205), (0.625, 0.15)], to: root, material: body)
            addSphere(radius: 0.205, position: SCNVector3(0, 0.79, 0), to: root, material: body)

        case .rook:
            addLathe([(0.22, 0.24), (0.28, 0.22), (0.34, 0.19), (0.75, 0.195),
                      (0.82, 0.235), (0.845, 0.29), (0.91, 0.29), (0.94, 0.27),
                      (1.055, 0.27)], to: root, material: body)
            addCylinder(radius: 0.235, height: 0.025, y: 1.06, to: root, material: detail)
            for i in 0..<6 {
                let angle = SceneScalar(i) * .pi / 3
                let block = SCNBox(width: 0.16, height: 0.17, length: 0.15, chamferRadius: 0.014)
                block.materials = [body]
                let node = SCNNode(geometry: block)
                node.position = SCNVector3(sin(angle) * 0.21, 1.12, cos(angle) * 0.21)
                node.eulerAngles.y = angle
                root.addChildNode(node)
            }

        case .knight:
            addLathe([(0.22, 0.24), (0.27, 0.23), (0.32, 0.24), (0.35, 0.24),
                      (0.38, 0.20)], to: root, material: body)
            let horse = makeHorse(material: body, detail: detail)
            // Both horses face their opponent across the board.
            horse.eulerAngles.y = piece.side == .white ? SceneScalar.pi / 2 : -SceneScalar.pi / 2
            root.addChildNode(horse)

        case .bishop:
            addStem(top: 0.92, to: root, material: body)
            addLathe([(0.91, 0.14), (0.96, 0.21), (1.02, 0.25), (1.13, 0.24),
                      (1.25, 0.185), (1.36, 0.10), (1.41, 0.028)], to: root, material: body,
                     slit: true)
            addSphere(radius: 0.047, position: SCNVector3(0, 1.425, 0), to: root, material: body)

        case .queen:
            addStem(top: 1.0, to: root, material: body)
            addLathe([(0.99, 0.14), (1.04, 0.19), (1.12, 0.20), (1.23, 0.28),
                      (1.28, 0.29)], to: root, material: body)
            addCylinder(radius: 0.25, height: 0.035, y: 1.28, to: root, material: detail)
            for i in 0..<8 {
                let angle = SceneScalar(i) * .pi / 4
                let crown = SCNCone(topRadius: 0.038, bottomRadius: 0.068, height: 0.20)
                crown.radialSegmentCount = 24
                crown.materials = [body]
                let node = SCNNode(geometry: crown)
                node.position = SCNVector3(sin(angle) * 0.24, 1.34, cos(angle) * 0.24)
                node.eulerAngles = SCNVector3(cos(angle) * 0.24, 0, -sin(angle) * 0.24)
                root.addChildNode(node)
                addSphere(radius: 0.055, position: SCNVector3(sin(angle) * 0.262, 1.44, cos(angle) * 0.262),
                          to: root, material: body)
            }
            addSphere(radius: 0.115, position: SCNVector3(0, 1.37, 0), to: root, material: body)
            addSphere(radius: 0.052, position: SCNVector3(0, 1.49, 0), to: root, material: body)

        case .king:
            addStem(top: 1.11, to: root, material: body)
            addLathe([(1.10, 0.16), (1.15, 0.215), (1.21, 0.24), (1.26, 0.225),
                      (1.30, 0.16), (1.34, 0.13)], to: root, material: body)
            addSphere(radius: 0.125, position: SCNVector3(0, 1.35, 0), to: root, material: body)
            let upright = SCNBox(width: 0.10, height: 0.36, length: 0.105, chamferRadius: 0.013)
            upright.materials = [body]
            let uprightNode = SCNNode(geometry: upright)
            uprightNode.position.y = 1.58
            root.addChildNode(uprightNode)
            let cross = SCNBox(width: 0.31, height: 0.105, length: 0.105, chamferRadius: 0.013)
            cross.materials = [body]
            let crossNode = SCNNode(geometry: cross)
            crossNode.position.y = 1.625
            root.addChildNode(crossNode)
        }
        return root
    }

    private func addStem(top: CGFloat, to parent: SCNNode, material: SCNMaterial) {
        addLathe([(0.22, 0.24), (0.27, 0.22), (0.33, 0.18), (top * 0.61, 0.115),
                  (top - 0.16, 0.14), (top - 0.12, 0.20), (top - 0.085, 0.23),
                  (top - 0.05, 0.23), (top - 0.025, 0.18), (top, 0.14)], to: parent, material: material)
    }

    private func makeHorse(material: SCNMaterial, detail: SCNMaterial) -> SCNNode {
        let horse = SCNNode()
        // A curved horse silhouette extruded through its cheeks, with a beveled muzzle.
        #if os(macOS)
        let outline = NSBezierPath()
        #else
        let outline = UIBezierPath()
        #endif
        outline.flatness = 0.008
        outline.move(to: CGPoint(x: -0.23, y: 0.36))
        outline.line(to: CGPoint(x: 0.23, y: 0.36))
        outline.curve(to: CGPoint(x: 0.08, y: 0.79), controlPoint1: CGPoint(x: 0.23, y: 0.55), controlPoint2: CGPoint(x: 0.10, y: 0.64))
        outline.line(to: CGPoint(x: 0.22, y: 0.94))
        outline.line(to: CGPoint(x: 0.39, y: 0.98))
        outline.curve(to: CGPoint(x: 0.43, y: 1.12), controlPoint1: CGPoint(x: 0.47, y: 1.00), controlPoint2: CGPoint(x: 0.48, y: 1.07))
        outline.line(to: CGPoint(x: 0.22, y: 1.27))
        outline.line(to: CGPoint(x: 0.09, y: 1.35))
        outline.line(to: CGPoint(x: -0.08, y: 1.28))
        outline.curve(to: CGPoint(x: -0.27, y: 0.85), controlPoint1: CGPoint(x: -0.25, y: 1.16), controlPoint2: CGPoint(x: -0.30, y: 0.99))
        outline.curve(to: CGPoint(x: -0.23, y: 0.36), controlPoint1: CGPoint(x: -0.24, y: 0.64), controlPoint2: CGPoint(x: -0.16, y: 0.53))
        outline.close()
        let shape = SCNShape(path: outline, extrusionDepth: 0.23)
        shape.chamferRadius = 0.052
        shape.materials = [material]
        horse.addChildNode(SCNNode(geometry: shape))

        for sign in [SceneScalar(-1), SceneScalar(1)] {
            // Ears are tapered and separated so the horse reads from either side.
            let ear = SCNCone(topRadius: 0.014, bottomRadius: 0.065, height: 0.22)
            ear.radialSegmentCount = 24
            ear.materials = [material]
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(0.015, 1.38, sign * 0.073)
            earNode.eulerAngles.z = -0.13
            horse.addChildNode(earNode)
            addSphere(radius: 0.031, position: SCNVector3(0.185, 1.205, sign * 0.143), to: horse, material: detail)
            addSphere(radius: 0.018, position: SCNVector3(0.385, 1.075, sign * 0.13), to: horse, material: detail)
        }
        // Individually carved ridges follow the back of the mane.
        for i in 0..<8 {
            let fraction = SceneScalar(i) / 7
            let y = 0.77 + fraction * 0.47
            let x = -0.28 + 0.16 * fraction * fraction
            let ridge = SCNBox(width: 0.052, height: 0.072, length: 0.25, chamferRadius: 0.019)
            ridge.materials = [material]
            let node = SCNNode(geometry: ridge)
            node.position = SCNVector3(x, y, 0)
            node.eulerAngles.z = -0.1 - fraction * 0.5
            horse.addChildNode(node)
        }
        return horse
    }

    private func addSphere(radius: CGFloat, position: SCNVector3, to parent: SCNNode, material: SCNMaterial) {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 40
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        parent.addChildNode(node)
    }

    private func addCylinder(radius: CGFloat, height: CGFloat, y: SceneScalar, to parent: SCNNode, material: SCNMaterial) {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 64
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position.y = y
        parent.addChildNode(node)
    }

    private func addTorus(radius: CGFloat, tube: CGFloat, y: SceneScalar, to parent: SCNNode, material: SCNMaterial) {
        let geometry = SCNTorus(ringRadius: radius, pipeRadius: tube)
        geometry.ringSegmentCount = 64
        geometry.pipeSegmentCount = 12
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position.y = y
        parent.addChildNode(node)
    }

    /// Rotating a profile makes continuous, smooth turned-wood forms.
    private func addLathe(_ profile: [(CGFloat, CGFloat)], to parent: SCNNode,
                          material: SCNMaterial, slit: Bool = false) {
        let segments = 80
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []
        for row in profile.indices {
            let lower = profile[max(0, row - 1)]
            let upper = profile[min(profile.count - 1, row + 1)]
            let deltaHeight = SceneScalar(upper.0 - lower.0)
            let deltaRadius = SceneScalar(upper.1 - lower.1)
            let length = max(0.00001, sqrt(deltaHeight * deltaHeight + deltaRadius * deltaRadius))
            for column in 0...segments {
                let angle = SceneScalar(column) / SceneScalar(segments) * 2 * .pi
                let radius = SceneScalar(profile[row].1)
                vertices.append(SCNVector3(cos(angle) * radius, SceneScalar(profile[row].0), sin(angle) * radius))
                normals.append(SCNVector3(cos(angle) * deltaHeight / length, -deltaRadius / length,
                                          sin(angle) * deltaHeight / length))
            }
        }
        for row in 0..<(profile.count - 1) {
            for column in 0..<segments {
                // An actual narrow slit through the upper mitre, visible from both sides.
                if slit && row >= 2 && (column == 19 || column == 20 || column == 59 || column == 60) { continue }
                let a = UInt32(row * (segments + 1) + column)
                let b = a + UInt32(segments + 1)
                indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }
        // End caps keep reflective lighting and silhouettes correct at open profile ends.
        for row in [0, profile.count - 1] {
            let center = UInt32(vertices.count)
            vertices.append(SCNVector3(0, SceneScalar(profile[row].0), 0))
            normals.append(SCNVector3(0, row == 0 ? -1 : 1, 0))
            for column in 0..<segments {
                let a = UInt32(row * (segments + 1) + column)
                indices.append(contentsOf: row == 0 ? [center, a, a + 1] : [center, a + 1, a])
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        if slit {
            let inner = material.copy() as! SCNMaterial
            inner.isDoubleSided = true
            geometry.materials = [inner]
        }
        parent.addChildNode(SCNNode(geometry: geometry))
    }

    // MARK: - Presentation and moves

    private func updatePieces(_ next: [Square: Piece], lastMove: Move?, animated: Bool) {
        guard animated, let move = lastMove, let movingPiece = renderedPieces[move.from],
              next[move.from] == nil, next[move.to]?.side == movingPiece.side,
              let movingNode = pieceNodes[move.from] else {
            piecesRoot.childNodes.forEach { $0.removeAllActions(); $0.removeFromParentNode() }
            pieceNodes.removeAll()
            for (square, piece) in next {
                let node = makePiece(piece, at: square)
                piecesRoot.addChildNode(node)
                pieceNodes[square] = node
            }
            return
        }

        var transfers: [Square: (SCNNode, Piece)] = [move.to: (movingNode, movingPiece)]
        if movingPiece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rookFrom = Square(file: move.to.file > move.from.file ? 7 : 0, rank: move.from.rank)
            let rookTo = Square(file: move.to.file > move.from.file ? 5 : 3, rank: move.from.rank)
            if let rookNode = pieceNodes[rookFrom], let rook = renderedPieces[rookFrom], next[rookTo] == rook {
                transfers[rookTo] = (rookNode, rook)
            }
        }
        var used = Set<ObjectIdentifier>()
        var replacement: [Square: SCNNode] = [:]
        for (square, piece) in next {
            if let (node, previous) = transfers[square] {
                used.insert(ObjectIdentifier(node))
                node.name = name(for: square)
                animateMove(node, to: square, knight: previous.kind == .knight)
                if previous.kind == piece.kind {
                    replacement[square] = node
                } else {
                    // A promoted pawn travels first; its new piece then rises into view.
                    let promoted = makePiece(piece, at: square)
                    promoted.opacity = 0
                    promoted.scale = SCNVector3(0.75, 0.75, 0.75)
                    piecesRoot.addChildNode(promoted)
                    promoted.runAction(.sequence([.wait(duration: moveDuration), .group([
                        .fadeIn(duration: 0.18), .scale(to: 1, duration: 0.18)
                    ])]))
                    node.runAction(.sequence([.wait(duration: moveDuration), .fadeOut(duration: 0.15), .removeFromParentNode()]))
                    replacement[square] = promoted
                }
            } else if renderedPieces[square] == piece, let node = pieceNodes[square] {
                used.insert(ObjectIdentifier(node))
                replacement[square] = node
            } else {
                let node = makePiece(piece, at: square)
                piecesRoot.addChildNode(node)
                replacement[square] = node
            }
        }
        for node in pieceNodes.values where !used.contains(ObjectIdentifier(node)) {
            node.categoryBitMask = 2
            node.enumerateChildNodes { child, _ in child.categoryBitMask = 2 }
            node.runAction(.sequence([.wait(duration: moveDuration * 0.65), .group([
                .fadeOut(duration: 0.30), .scale(to: 0.75, duration: 0.30),
                .moveBy(x: 0, y: 0.16, z: 0, duration: 0.30)
            ]), .removeFromParentNode()]))
        }
        pieceNodes = replacement
    }

    private func animateMove(_ node: SCNNode, to square: Square, knight: Bool) {
        let start = node.presentation.position
        let end = boardPoint(square, height: pieceHeight)
        node.removeAction(forKey: "travel")
        let duration = moveDuration
        let action = SCNAction.customAction(duration: duration) { node, elapsed in
            let progress = min(SceneScalar(elapsed) / SceneScalar(duration), 1)
            let eased = progress * progress * (3 - 2 * progress)
            let lift = sin(progress * .pi) * (knight ? SceneScalar(0.64) : SceneScalar(0.18))
            node.position = SCNVector3(start.x + (end.x - start.x) * eased,
                                      start.y + (end.y - start.y) * eased + lift,
                                      start.z + (end.z - start.z) * eased)
        }
        node.runAction(.sequence([action, .move(to: end, duration: 0)]), forKey: "travel")
    }

    private func updateMarkers(selected: Square?, legalTargets: [Square], lastMove: Move?) {
        markersRoot.childNodes.forEach { $0.removeFromParentNode() }
        if let move = lastMove {
            for square in [move.from, move.to] {
                addSquareMarker(square, color: Self.color(0.90, 0.68, 0.28, 0.25), outline: false)
            }
        }
        if let square = selected {
            addSquareMarker(square, color: Self.color(1, 0.82, 0.39, 0.88), outline: true)
        }
        for square in legalTargets {
            let geometry: SCNGeometry
            if renderedPieces[square] == nil {
                geometry = SCNCylinder(radius: 0.115, height: 0.012)
            } else {
                geometry = SCNTorus(ringRadius: 0.405, pipeRadius: 0.022)
            }
            let material = Self.material(color: Self.color(0.62, 0.89, 0.72, 0.90), roughness: 1)
            material.lightingModel = .constant
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position = boardPoint(square, height: 0.075)
            node.categoryBitMask = 2
            node.castsShadow = false
            markersRoot.addChildNode(node)
        }
    }

    private func addSquareMarker(_ square: Square, color: PlatformColor, outline: Bool) {
        let material = Self.material(color: color, roughness: 1)
        material.lightingModel = .constant
        let group = SCNNode()
        group.position = boardPoint(square, height: 0.061)
        group.categoryBitMask = 2
        let dimensions: [(CGFloat, CGFloat, SceneScalar, SceneScalar)] = outline
            ? [(0.94, 0.025, 0, -0.46), (0.94, 0.025, 0, 0.46),
               (0.025, 0.94, -0.46, 0), (0.025, 0.94, 0.46, 0)]
            : [(0.98, 0.98, 0, 0)]
        for (width, length, x, z) in dimensions {
            let shape = SCNBox(width: width, height: 0.008, length: length, chamferRadius: 0.004)
            shape.materials = [material]
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(x, 0, z)
            node.categoryBitMask = 2
            node.castsShadow = false
            group.addChildNode(node)
        }
        markersRoot.addChildNode(group)
    }

    private func name(for square: Square) -> String { "square:\(square.file):\(square.rank)" }

    private func boardPoint(_ square: Square, height: SceneScalar) -> SCNVector3 {
        SCNVector3(SceneScalar(square.file) - 3.5, height, 3.5 - SceneScalar(square.rank))
    }

    // MARK: - Materials

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func material(color: PlatformColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        return material
    }

    private static func woodTexture(base: (Double, Double, Double), variation: Double) -> CGImage? {
        texture(width: 128, height: 512) { x, y in
            let wave = sin(Double(x) * 0.22 + sin(Double(y) * 0.018) * 2.1)
            let fine = sin(Double(x) * 1.15 + sin(Double(y) * 0.032)) * 0.22
            let grain = (wave + fine) * variation
            return (base.0 + grain, base.1 + grain * 0.72, base.2 + grain * 0.44)
        }
    }

    private static func environmentTexture() -> CGImage? {
        texture(width: 256, height: 128) { x, y in
            let u = Double(x) / 255
            let v = Double(y) / 127
            let glow = exp(-pow((u - 0.23) / 0.065, 2) - pow((v - 0.32) / 0.25, 2))
            let rim = exp(-pow((u - 0.73) / 0.045, 2) - pow((v - 0.38) / 0.3, 2))
            let ambient = 0.18 + 0.15 * (1 - v)
            return (ambient + glow * 0.65 + rim * 0.46,
                    ambient + glow * 0.58 + rim * 0.52,
                    ambient + glow * 0.46 + rim * 0.62)
        }
    }

    private static func texture(width: Int, height: Int, pixel: (Int, Int) -> (Double, Double, Double)) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(max(0, min(255, value.0 * 255)))
                bytes[offset + 1] = UInt8(max(0, min(255, value.1 * 255)))
                bytes[offset + 2] = UInt8(max(0, min(255, value.2 * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// SceneKit is embedded directly so taps on pieces and exposed squares share one hit test.
#if os(macOS)
@MainActor
struct ChessBoardView: NSViewRepresentable {
    let controller: ChessScene

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.allowsCameraControl = false
        view.backgroundColor = .clear
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        view.addGestureRecognizer(click)
        view.setAccessibilityLabel("Three-dimensional chessboard")
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.controller = controller
        if view.scene !== controller.scene {
            view.scene = controller.scene
            view.pointOfView = controller.cameraNode
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var controller: ChessScene
        init(controller: ChessScene) { self.controller = controller }
        @objc func clicked(_ recognizer: NSClickGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            controller.handleHit(at: recognizer.location(in: view), in: view)
        }
    }
}
#else
@MainActor
struct ChessBoardView: UIViewRepresentable {
    let controller: ChessScene

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.allowsCameraControl = false
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        view.accessibilityLabel = "Three-dimensional chessboard"
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.controller = controller
        if view.scene !== controller.scene {
            view.scene = controller.scene
            view.pointOfView = controller.cameraNode
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var controller: ChessScene
        init(controller: ChessScene) { self.controller = controller }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            controller.handleHit(at: recognizer.location(in: view), in: view)
        }
    }
}
#endif
