//
//  QRScannerService.swift
//  Ash
//

@preconcurrency import AVFoundation
import UIKit

protocol QRScannerDelegate: AnyObject {
    func didScanQRCode(_ data: Data)
    func didFailWithError(_ error: QRScannerError)
}

enum QRScannerError: Error, Sendable {
    case cameraUnavailable
    case permissionDenied
    case setupFailed
    case invalidQRData
}

final class QRScannerService: NSObject {
    weak var delegate: QRScannerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recentScans: Set<String> = []
    private var lastScanTime: Date = .distantPast
    private let deduplicationInterval: TimeInterval = 0.3

    static var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func setup() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            throw QRScannerError.cameraUnavailable
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            throw QRScannerError.setupFailed
        }

        guard session.canAddInput(videoInput) else {
            throw QRScannerError.setupFailed
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            throw QRScannerError.setupFailed
        }
        session.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        self.captureSession = session
    }

    func getPreviewLayer(for bounds: CGRect) -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer

        return layer
    }

    func startScanning() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stopScanning() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    func clearRecentScans() {
        recentScans.removeAll()
    }
}

extension QRScannerService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for metadata in metadataObjects {
            guard let qrCode = metadata as? AVMetadataMachineReadableCodeObject,
                  qrCode.type == .qr,
                  let stringValue = qrCode.stringValue else {
                continue
            }

            let now = Date()
            if now.timeIntervalSince(lastScanTime) < deduplicationInterval,
               recentScans.contains(stringValue) {
                continue
            }

            lastScanTime = now
            recentScans.insert(stringValue)

            if recentScans.count > 100 {
                recentScans.removeAll()
            }

            guard let data = Data(base64Encoded: stringValue) else {
                delegate?.didFailWithError(.invalidQRData)
                continue
            }

            delegate?.didScanQRCode(data)
        }
    }
}
