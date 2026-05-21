import SwiftUI
import AVFoundation

/// An elegant, high-contrast visual QR scanner leveraging AVFoundation.
/// Displays a modern, animated focus target overlay.
/// Falls back gracefully with interactive mock controls on Simulators or when permissions are missing.
public struct QRScannerView: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    
    @State private var scanLineY: CGFloat = 0.0
    @State private var isAnimating = false
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    
    public init(onScan: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onScan = onScan
        self.onCancel = onCancel
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            #if targetEnvironment(simulator)
            simulatorFallbackView
            #else
            if cameraPermission == .authorized {
                CameraScannerBridge(onScan: onScan)
                    .ignoresSafeArea()
                
                scannerOverlay
            } else if cameraPermission == .denied || cameraPermission == .restricted {
                permissionDeniedView
            } else {
                loadingPermissionView
            }
            #endif
            
            // --- Navigation Bar ---
            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.66), .white.opacity(0.18))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }
    
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self.cameraPermission = status
        
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { authorized in
                DispatchQueue.main.async {
                    self.cameraPermission = authorized ? .authorized : .denied
                }
            }
        }
    }
    
    // --- UI Components ---
    
    private var scannerOverlay: some View {
        GeometryReader { proxy in
            let scanSize = min(proxy.size.width, proxy.size.height) * 0.64
            let scanRect = CGRect(
                x: (proxy.size.width - scanSize) / 2,
                y: (proxy.size.height - scanSize) / 2,
                width: scanSize,
                height: scanSize
            )
            
            ZStack {
                // Dim surround background
                Color.black.opacity(0.5)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .frame(width: scanSize, height: scanSize)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                
                // Active Scan Frame Accents
                Group {
                    // Frame Corners
                    ScannerFrameCorner(corner: .topLeft, size: scanSize)
                    ScannerFrameCorner(corner: .topRight, size: scanSize)
                    ScannerFrameCorner(corner: .bottomLeft, size: scanSize)
                    ScannerFrameCorner(corner: .bottomRight, size: scanSize)
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .frame(width: scanSize, height: scanSize)
                
                // Animated laser line
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, .yellow.opacity(0.88), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: scanSize - 8, height: 3)
                    .position(
                        x: proxy.size.width / 2,
                        y: scanRect.minY + 4 + (scanSize - 8) * scanLineY
                    )
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                            scanLineY = 1.0
                        }
                    }
                
                VStack(spacing: 12) {
                    Spacer()
                    
                    Text("对准 UCLAW 桌面端的配对二维码")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.48), in: Capsule())
                    
                    Spacer()
                        .frame(height: max(10, proxy.size.height - scanRect.maxY - 80))
                }
            }
        }
    }
    
    private var simulatorFallbackView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            
            VStack(spacing: 8) {
                Text("Simulator Scan Mock")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("You are running on a Simulator. Tap below to automatically simulate scanning the mock QR Code generated by the Developer Pairing Simulator.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                // Instantly inject the current simulator pairing URI
                let mockURI = PairingSimulator.shared.pairingURI
                onScan(mockURI)
            } label: {
                Label("Simulate QR Scan", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 24)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("需要相机权限来扫描二维码")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Button("去设置中开启") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
    
    private var loadingPermissionView: some View {
        VStack {
            ProgressView()
                .tint(.white)
            Text("Requesting Camera Access...")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
    }
}

// --- Mask inversion helper ---

extension View {
    func reverseMask<Mask: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(
                    mask()
                        .blendMode(.destinationOut)
                )
        }
    }
}

// --- Frame Corners Drawing ---

private enum ScannerCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

private struct ScannerFrameCorner: View {
    let corner: ScannerCorner
    let size: CGFloat
    
    var body: some View {
        let length: CGFloat = 22
        let thickness: CGFloat = 4
        let radius: CGFloat = 16
        
        Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: radius))
                path.addArc(
                    center: CGPoint(x: radius, y: radius),
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: length, y: 0))
                
            case .topRight:
                path.move(to: CGPoint(x: size - length, y: 0))
                path.addLine(to: CGPoint(x: size - radius, y: 0))
                path.addArc(
                    center: CGPoint(x: size - radius, y: radius),
                    radius: radius,
                    startAngle: .degrees(270),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: size, y: length))
                
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: size - length))
                path.addLine(to: CGPoint(x: 0, y: size - radius))
                path.addArc(
                    center: CGPoint(x: radius, y: size - radius),
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true
                )
                path.addLine(to: CGPoint(x: length, y: size))
                
            case .bottomRight:
                path.move(to: CGPoint(x: size - length, y: size))
                path.addLine(to: CGPoint(x: size - radius, y: size))
                path.addArc(
                    center: CGPoint(x: size - radius, y: size - radius),
                    radius: radius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: size, y: size - length))
            }
        }
        .stroke(.yellow, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

// --- AVCapture UIViewController Representable ---

#if !targetEnvironment(simulator)
private struct CameraScannerBridge: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    
    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let controller = CameraScannerViewController()
        controller.onScan = onScan
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {}
}

private class CameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        let session = AVCaptureSession()
        self.captureSession = session
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        captureSession?.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                return
            }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onScan?(stringValue)
        }
    }
}
#endif
