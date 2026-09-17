import SwiftUI
import UIKit
import ARKit
import SceneKit

struct ARMeasureResult {
    var width: Double?
    var height: Double?
    var depth: Double?
    var isEmpty: Bool { width == nil && height == nil && depth == nil }
}

/// SwiftUI wrapper for the UIKit AR measurement controller.
struct ARMeasureScreen: UIViewControllerRepresentable {
    let onFinish: (ARMeasureResult?) -> Void

    func makeUIViewController(context: Context) -> ARMeasureViewController {
        let vc = ARMeasureViewController()
        vc.completion = onFinish
        return vc
    }

    func updateUIViewController(_ vc: ARMeasureViewController, context: Context) {}
}

/// Measure-app-style flow with stability fixes:
/// - points are ARAnchors, so ARKit keeps them glued to the real surface as
///   its world map refines (this is what stops the drift)
/// - a live preview dot shows exactly where the point will land before you tap
/// - Apple's coaching overlay guides the initial room scan
/// - raycasts prefer detected plane geometry over rough estimates
final class ARMeasureViewController: UIViewController, ARSCNViewDelegate {
    var completion: ((ARMeasureResult?) -> Void)?

    private let sceneView = ARSCNView()
    private var pointAnchors: [ARAnchor] = []
    private var anchorRoles: [UUID: Int] = [:]        // anchor id → 0 (first point) | 1 (second)
    private var anchorPositions: [Int: SCNVector3] = [:]
    private var lineNode: SCNNode?
    private var currentInches: Double?
    private var result = ARMeasureResult()

    private let previewDot: SCNNode = {
        let s = SCNSphere(radius: 0.005)
        s.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.75, blue: 0.88, alpha: 0.9)
        s.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: s)
        n.isHidden = true
        return n
    }()

    private let reticle = UIView()
    private let distanceLabel = UILabel()
    private let statusLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private var assignButtons: [String: UIButton] = [:]
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        view.addSubview(sceneView)

        sceneView.scene.rootNode.addChildNode(previewDot)

        // Apple's built-in "move your phone around" guidance
        let coaching = ARCoachingOverlayView()
        coaching.session = sceneView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.frame = view.bounds
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh   // LiDAR phones get precise surface hits
        }
        sceneView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - UI

    private func buildUI() {
        reticle.frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        reticle.center = view.center
        reticle.layer.cornerRadius = 13
        reticle.layer.borderColor = UIColor.white.cgColor
        reticle.layer.borderWidth = 2
        reticle.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        reticle.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin,
                                    .flexibleTopMargin, .flexibleBottomMargin]
        reticle.isUserInteractionEnabled = false
        view.addSubview(reticle)

        statusLabel.text = "Slowly sweep your phone across the item first, then aim at one edge and tap +"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 10
        statusLabel.clipsToBounds = true
        view.addSubview(statusLabel)

        distanceLabel.text = ""
        distanceLabel.textColor = UIColor(red: 0.35, green: 0.75, blue: 0.88, alpha: 1)
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        distanceLabel.textAlignment = .center
        view.addSubview(distanceLabel)

        addButton.setTitle("+", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 34, weight: .bold)
        addButton.tintColor = .black
        addButton.backgroundColor = .white
        addButton.layer.cornerRadius = 36
        addButton.addTarget(self, action: #selector(addPoint), for: .touchUpInside)
        view.addSubview(addButton)

        for key in ["W", "H", "D"] {
            let b = UIButton(type: .system)
            b.setTitle("\(key): —", for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            b.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            b.layer.cornerRadius = 10
            b.layer.borderWidth = 1.5
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
            b.accessibilityIdentifier = key
            b.addTarget(self, action: #selector(assignDimension(_:)), for: .touchUpInside)
            view.addSubview(b)
            assignButtons[key] = b
        }

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.frame = CGRect(x: 16, y: 58, width: 80, height: 36)
        view.addSubview(cancel)

        let reset = UIButton(type: .system)
        reset.setTitle("Reset", for: .normal)
        reset.setTitleColor(.white, for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        reset.addTarget(self, action: #selector(resetPoints), for: .touchUpInside)
        reset.frame = CGRect(x: view.bounds.midX - 40, y: 58, width: 80, height: 36)
        reset.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(reset)

        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(UIColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1), for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.frame = CGRect(x: view.bounds.width - 96, y: 58, width: 80, height: 36)
        doneButton.autoresizingMask = [.flexibleLeftMargin]
        view.addSubview(doneButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height
        statusLabel.frame = CGRect(x: 24, y: h - 214, width: w - 48, height: 44)
        distanceLabel.frame = CGRect(x: 0, y: h - 280, width: w, height: 44)
        addButton.frame = CGRect(x: w / 2 - 36, y: h - 150, width: 72, height: 72)
        let bw = (w - 64) / 3
        for (i, key) in ["W", "H", "D"].enumerated() {
            assignButtons[key]?.frame = CGRect(x: 16 + CGFloat(i) * (bw + 16), y: h - 62, width: bw, height: 40)
        }
    }

    // MARK: - Raycasting

    /// Prefer real detected plane geometry (stable) over rough estimates.
    private func raycastCenterHit() -> ARRaycastResult? {
        if let q = sceneView.raycastQuery(from: view.center, allowing: .existingPlaneGeometry, alignment: .any),
           let r = sceneView.session.raycast(q).first { return r }
        if let q = sceneView.raycastQuery(from: view.center, allowing: .estimatedPlane, alignment: .any),
           let r = sceneView.session.raycast(q).first { return r }
        return nil
    }

    // Live preview: show where the point would land, every frame.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            if let hit = self.raycastCenterHit() {
                let t = hit.worldTransform.columns.3
                self.previewDot.position = SCNVector3(t.x, t.y, t.z)
                self.previewDot.isHidden = false
                self.addButton.isEnabled = true
                self.addButton.alpha = 1
                self.reticle.layer.borderColor = UIColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1).cgColor
            } else {
                self.previewDot.isHidden = true
                self.addButton.isEnabled = false
                self.addButton.alpha = 0.4
                self.reticle.layer.borderColor = UIColor.white.cgColor
            }
        }
    }

    // MARK: - Measuring

    @objc private func addPoint() {
        guard let hit = raycastCenterHit() else {
            statusLabel.text = "No surface found — sweep your phone across the item slowly"
            return
        }
        let role: Int
        if anchorPositions[0] == nil { role = 0 }
        else if anchorPositions[1] == nil { role = 1 }
        else { resetPoints(); addPoint(); return }

        let anchor = ARAnchor(name: "measure-point", transform: hit.worldTransform)
        anchorRoles[anchor.identifier] = role
        pointAnchors.append(anchor)
        sceneView.session.add(anchor: anchor)

        statusLabel.text = role == 0
            ? "Now aim at the other edge and tap + again"
            : "Tap W, H, or D below to save this measurement"
    }

    // ARKit gives every anchor a node — put the marker there so it stays
    // pinned to the surface even as tracking refines.
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let role = anchorRoles[anchor.identifier] else { return }
        let sphere = SCNSphere(radius: 0.006)
        sphere.firstMaterial?.diffuse.contents = UIColor.white
        sphere.firstMaterial?.lightingModel = .constant
        node.addChildNode(SCNNode(geometry: sphere))
        let t = anchor.transform.columns.3
        DispatchQueue.main.async {
            self.anchorPositions[role] = SCNVector3(t.x, t.y, t.z)
            self.refreshMeasurement()
        }
    }

    // Tracking refinements move the anchors — keep the line and distance live.
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let role = anchorRoles[anchor.identifier] else { return }
        let t = anchor.transform.columns.3
        DispatchQueue.main.async {
            self.anchorPositions[role] = SCNVector3(t.x, t.y, t.z)
            self.refreshMeasurement()
        }
    }

    private func refreshMeasurement() {
        lineNode?.removeFromParentNode()
        lineNode = nil
        guard let a = anchorPositions[0], let b = anchorPositions[1] else { return }
        let node = makeLine(from: a, to: b)
        sceneView.scene.rootNode.addChildNode(node)
        lineNode = node
        let inches = Double(distance(a, b)) * 39.3701
        currentInches = inches
        distanceLabel.text = String(format: "%.1f\"", inches)
    }

    @objc private func assignDimension(_ sender: UIButton) {
        guard let key = sender.accessibilityIdentifier, let inches = currentInches else { return }
        let rounded = (inches * 10).rounded() / 10
        switch key {
        case "W": result.width = rounded
        case "H": result.height = rounded
        default:  result.depth = rounded
        }
        sender.setTitle("\(key): \(String(format: "%.1f", rounded))\"", for: .normal)
        sender.layer.borderColor = UIColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1).cgColor
        resetPoints()
        statusLabel.text = "Saved. Measure the next edge, or tap Done"
    }

    @objc private func resetPoints() {
        pointAnchors.forEach { sceneView.session.remove(anchor: $0) }
        pointAnchors.removeAll()
        anchorRoles.removeAll()
        anchorPositions.removeAll()
        lineNode?.removeFromParentNode()
        lineNode = nil
        currentInches = nil
        distanceLabel.text = ""
        if result.isEmpty {
            statusLabel.text = "Aim the circle at one edge of the item, then tap +"
        }
    }

    @objc private func doneTapped() {
        completion?(result.isEmpty ? nil : result)
    }

    @objc private func cancelTapped() {
        completion?(nil)
    }

    // MARK: - Scene helpers

    private func makeLine(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let dist = distance(a, b)
        let parent = SCNNode()
        parent.position = a
        parent.look(at: b)   // -Z now points at b
        let cyl = SCNCylinder(radius: 0.0018, height: CGFloat(dist))
        cyl.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.75, blue: 0.88, alpha: 1)
        cyl.firstMaterial?.lightingModel = .constant
        let cylNode = SCNNode(geometry: cyl)
        cylNode.eulerAngles.x = -.pi / 2                 // align cylinder's long axis with -Z
        cylNode.position = SCNVector3(0, 0, -dist / 2)
        parent.addChildNode(cylNode)
        return parent
    }

    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
