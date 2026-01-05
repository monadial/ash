//
//  QRScannerView.swift
//  Ash
//
//  SwiftUI wrapper for QR code camera scanning
//

import SwiftUI
import AVFoundation

/// SwiftUI view for QR code scanning
struct QRScannerView: View {
    let onFrameScanned: (Data) -> Void
    let onError: (QRScannerError) -> Void

    @State private var hasPermission: Bool = false
    @State private var isCheckingPermission: Bool = true

    var body: some View {
        Group {
            if isCheckingPermission {
                ProgressView()
                    .controlSize(.large)
            } else if hasPermission {
                CameraPreviewView(onFrameScanned: onFrameScanned)
            } else {
                PermissionDeniedView()
            }
        }
        .task {
            await checkPermission()
        }
    }

    private func checkPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await QRScannerService.requestPermission()
        default:
            hasPermission = false
        }

        isCheckingPermission = false
    }
}

// MARK: - Camera Preview

private struct CameraPreviewView: UIViewRepresentable {
    let onFrameScanned: (Data) -> Void

    func makeUIView(context: Context) -> CameraContainerView {
        let view = CameraContainerView()
        view.onFrameScanned = onFrameScanned
        return view
    }

    func updateUIView(_ uiView: CameraContainerView, context: Context) {
        // No updates needed
    }
}

/// UIKit container for camera preview
private class CameraContainerView: UIView, @preconcurrency QRScannerDelegate {
    private let scanner = QRScannerService()
    var onFrameScanned: ((Data) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScanner()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScanner()
    }

    private func setupScanner() {
        scanner.delegate = self

        do {
            try scanner.setup()
        } catch {
            Log.error(.ui, "Scanner setup failed")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Add preview layer if not already added
        if layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) == nil {
            if let previewLayer = scanner.getPreviewLayer(for: bounds) {
                layer.insertSublayer(previewLayer, at: 0)
            }
        } else {
            // Update existing layer frame
            layer.sublayers?.forEach { sublayer in
                if let previewLayer = sublayer as? AVCaptureVideoPreviewLayer {
                    previewLayer.frame = bounds
                }
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            scanner.startScanning()
        } else {
            scanner.stopScanning()
        }
    }

    // MARK: - QRScannerDelegate

    func didScanQRCode(_ data: Data) {
        onFrameScanned?(data)
    }

    func didFailWithError(_ error: QRScannerError) {
        Log.debug(.ui, "Scan error occurred")
    }
}

// MARK: - Permission Denied View

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)

            Text("Camera Access Required")
                .font(.headline)

            Text("Enable camera access in Settings to scan QR codes")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
