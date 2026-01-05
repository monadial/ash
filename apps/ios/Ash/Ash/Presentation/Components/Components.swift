//
//  Components.swift
//  Ash
//
//  Reusable UI components
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemFill), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.3), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Progress: \(Int(progress * 100)) percent")
    }
}

// MARK: - Usage Bar

struct UsageBar: View {
    let progress: Double
    var height: CGFloat = 6

    private var color: Color {
        if progress > 0.9 { return .red }
        if progress > 0.7 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .systemFill))

                Capsule()
                    .fill(color)
                    .frame(width: max(0, geometry.size.width * min(1, progress)))
                    .animation(.spring(duration: 0.3), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Usage: \(Int(progress * 100)) percent")
    }
}

// MARK: - Dual Usage Bar

struct DualUsageBar: View {
    let myUsage: Double
    let peerUsage: Double
    var height: CGFloat = 6

    private var remaining: Double {
        max(0, 1 - myUsage - peerUsage)
    }

    private var remainingColor: Color {
        if remaining < 0.1 { return .red }
        if remaining < 0.3 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(remainingColor.opacity(0.2))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * min(1, myUsage)))

                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: max(0, geometry.size.width * min(1, peerUsage)))
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("My usage: \(Int(myUsage * 100)) percent, Peer: \(Int(peerUsage * 100)) percent")
    }
}

// MARK: - Mnemonic Display

struct MnemonicDisplay: View {
    let words: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            }
        }
    }
}

// MARK: - QR Code View

struct QRCodeView: View {
    let data: Data?
    var size: CGFloat = 280

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)

            if let data, let image = QRCodeGenerator.generate(from: data, size: size - 20) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else if data != nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("QR generation failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
    }
}

// MARK: - QR Code Generator

enum QRCodeGenerator {
    /// Error correction levels: L (7%), M (15%), Q (25%), H (30%)
    /// L gives highest capacity - fountain codes provide their own redundancy
    /// With L: 4,296 alphanumeric chars = ~3,200 bytes before base64
    static func generate(from data: Data, size: CGFloat, correctionLevel: String = "L") -> UIImage? {
        // Base64 encode for compatibility with AVMetadataObject.stringValue
        let base64String = data.base64EncodedString()

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(base64String.data(using: .utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Scan Progress

struct ScanProgressView: View {
    let scannedFrames: Int
    let totalFrames: Int

    var progress: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(scannedFrames) / Double(totalFrames)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 8, size: 120)

                VStack(spacing: 2) {
                    Text("\(scannedFrames)")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("of \(totalFrames)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Scanning...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Entropy Collection

struct EntropyCollectionView: View {
    @Binding var progress: Double
    let onComplete: () -> Void

    @State private var touchPoints: [CGPoint] = []

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Draw Random Patterns")
                    .font(.title2.bold())

                Text("Move your finger to generate entropy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))

                    Path { path in
                        guard touchPoints.count > 1 else { return }
                        path.move(to: touchPoints[0])
                        for point in touchPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    if touchPoints.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("Touch and drag")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            touchPoints.append(value.location)
                            if touchPoints.count > 500 {
                                touchPoints.removeFirst(100)
                            }
                            progress = min(1.0, progress + 0.002)
                            if progress >= 1.0 {
                                onComplete()
                            }
                        }
                )
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.accentColor)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(24)
    }
}
