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

/// Measure-app-style flow: aim the center reticle at a point on the item,
/// tap "+" to drop the first point, aim at the second point, tap "+" again.
/// The distance shows live; assign it to W, H, or D, then measure the next
/// edge. Done returns whatever was captured (even one dimension helps —
/// the web app rescales proportionally).
final class ARMeasureViewController: UIViewController, ARSCNViewDelegate {
    var completion: ((ARMeasureResult?) -> Void)?

    private let sceneView = ARSCNView()
    private var pointA: SCNVector3?
    private var pointB: SCNVector3?
    private var markerNodes: [SCNNode] = []
    private var currentInches: Double?
    private var result = ARMeasureResult()

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

        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh   // LiDAR phones get better hits
        }
        sceneView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - UI

    private func buildUI() {
        // Center reticle
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

        // Status / instructions
        statusLabel.text = "Aim the circle at one edge of the item, then tap +"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 10
        statusLabel.clipsToBounds = true
        view.addSubview(statusLabel)

        // Live distance
        distanceLabel.text = ""
        distanceLabel.textColor = UIColor(red: 0.35, green: 0.75, blue: 0.88, alpha: 1)
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        distanceLabel.textAlignment = .center
        view.addSubview(distanceLabel)

        // Add-point button
        addButton.setTitle("+", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 34, weight: .bold)
        addButton.tintColor = .black
        addButton.backgroundColor = .white
        addButton.layer.cornerRadius = 36
        addButton.addTarget(self, action: #selector(addPoint), for: .touchUpInside)
        view.addSubview(addButton)

        // Assign buttons
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

        // Cancel / Reset / Done
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

    // MARK: - Measuring

    private func raycastCenter() -> SCNVector3? {
        guard let query = sceneView.raycastQuery(from: view.center,
                                                 allowing: .estimatedPlane,
                                                 alignment: .any),
              let hit = sceneView.session.raycast(query).first else { return nil }
        let t = hit.worldTransform.columns.3
        return SCNVector3(t.x, t.y, t.z)
    }

    @objc private func addPoint() {
        guard let pos = raycastCenter() else {
            statusLabel.text = "No surface found — move closer or add more light"
            return
        }
        if pointA == nil {
            pointA = pos
            addMarker(at: pos)
            statusLabel.text = "Now aim at the other edge and tap + again"
        } else if pointB == nil {
            pointB = pos
            addMarker(at: pos)
            drawLine(from: pointA!, to: pos)
            let meters = distance(pointA!, pos)
            currentInches = Double(meters) * 39.3701
            distanceLabel.text = String(format: "%.1f\"", currentInches!)
            statusLabel.text = "Tap W, H, or D below to save this measurement"
        } else {
            resetPoints()
            addPoint()
        }
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
        statusLabel.text = result.isEmpty ? "" : "Measure the next edge, or tap Done"
    }

    @objc private func resetPoints() {
        pointA = nil; pointB = nil; currentInches = nil
        distanceLabel.text = ""
        markerNodes.forEach { $0.removeFromParentNode() }
        markerNodes.removeAll()
        if result.isEmpty { statusLabel.text = "Aim the circle at one edge of the item, then tap +" }
    }

    @objc private func doneTapped() {
        completion?(result.isEmpty ? nil : result)
    }

    @objc private func cancelTapped() {
        completion?(nil)
    }

    // MARK: - Scene helpers

    private func addMarker(at pos: SCNVector3) {
        let sphere = SCNSphere(radius: 0.006)
        sphere.firstMaterial?.diffuse.contents = UIColor.white
        let node = SCNNode(geometry: sphere)
        node.position = pos
        sceneView.scene.rootNode.addChildNode(node)
        markerNodes.append(node)
    }

    private func drawLine(from a: SCNVector3, to b: SCNVector3) {
        let vertices = [a, b]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [Int32] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.75, blue: 0.88, alpha: 1)
        let node = SCNNode(geometry: geometry)
        sceneView.scene.rootNode.addChildNode(node)
        markerNodes.append(node)
    }

    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
