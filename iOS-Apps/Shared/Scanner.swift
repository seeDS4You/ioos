import SwiftUI
import AVFoundation

struct ScanScreen: View {
    var path = "/api/scan"
    var supervisor = false
    var recorded: () async -> Void = {}
    @EnvironmentObject var api: API
    @State private var result: Row?
    @State private var error: String?
    @State private var busy = false
    @State private var input = ""
    @State private var manual = false
    @State private var scannerID = UUID()
    var body: some View {
        Screen {
            Text(supervisor ? "Record your allocated team. Expired attendance QR codes are accepted; attendance is unchanged." : "Scan a staff QR code to record attendance.").foregroundStyle(Palette.muted).font(.subheadline)
            if result == nil && error == nil && !manual {
                CameraScanner { value in Task { await scan(value) } }.id(scannerID).frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 24))
                Button("Enter QR token manually") { manual = true }.buttonStyle(.bordered)
            }
            if manual {
                Panel { TextField("Paste QR URL or signed token", text: $input, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled(); PrimaryButton(title: "Verify QR", symbol: "qrcode", enabled: !busy && !input.isEmpty) { Task { await scan(input) } }; Button("Use camera") { manual = false; scannerID = UUID() } }
            }
            if let result {
                Panel {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.green)
                    Text(result.text("message", fallback: "Recorded successfully")).font(.title3.bold())
                    let data = result.object(supervisor ? "record" : "data")
                    Text(data.text(supervisor ? "staff_name" : "name")).font(.headline)
                    Text(data.text("venue")).foregroundStyle(Palette.muted)
                    Text(data.text(supervisor ? "recorded_at" : "signedInAt", fallback: data.text("time"))).font(.caption)
                }
            }
            if let error { Notice(text: error) }
            if result != nil || error != nil { PrimaryButton(title: "Scan next", symbol: "qrcode.viewfinder", enabled: !busy) { result = nil; error = nil; manual = false; input = ""; scannerID = UUID() } }
            if busy { ProgressView("Verifying…") }
        }.navigationTitle(supervisor ? "Staff sign in" : "Scan QR")
    }
    private func scan(_ value: String) async {
        guard !busy && result == nil && error == nil else { return }
        guard let token = QRToken.extract(value) else { error = "Invalid QR code. Use a SISS staff shift QR code."; manual = false; return }
        busy = true; defer { busy = false }; manual = false
        do { result = try await api.call(path, method: "POST", body: ["token": token]); await recorded() } catch { self.error = error.localizedDescription }
    }
}
struct CameraScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> CameraController { let controller = CameraController(); controller.onCode = onCode; return controller }
    func updateUIViewController(_ controller: CameraController, context: Context) { controller.onCode = onCode }
    static func dismantleUIViewController(_ controller: CameraController, coordinator: ()) { controller.stop() }
}
final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let capture = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "siss.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var scanned = false
    private var stopped = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in DispatchQueue.main.async { if granted { self?.setup() } else { self?.unavailable() } } }
        default: unavailable()
        }
    }
    private func unavailable() {
        let label = UILabel(); label.text = "Camera unavailable. Enable camera access in Settings or use manual entry."; label.numberOfLines = 0; label.textColor = .white; label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.centerYAnchor.constraint(equalTo: view.centerYAnchor), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)])
    }
    private func setup() {
        guard !stopped, let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), capture.canAddInput(input) else { unavailable(); return }
        capture.beginConfiguration(); capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { capture.commitConfiguration(); unavailable(); return }
        capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]; capture.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: capture); layer.videoGravity = .resizeAspectFill; view.layer.addSublayer(layer); preview = layer
        cameraQueue.async { [capture] in capture.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() { stopped = true; cameraQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !scanned, !stopped, let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        scanned = true; stop(); onCode?(value)
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); stop() }
}
