//
//  MessageDetailView.swift
//  Ash
//
//  Message details - Modern redesign with accent color
//

import SwiftUI

struct MessageDetailView: View {
    let message: Message
    var accentColor: Color = .ashAccent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.15))
                                .frame(width: 70, height: 70)

                            Image(systemName: message.isOutgoing ? "arrow.up.circle" : "arrow.down.circle")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(accentColor)
                        }

                        Text(message.isOutgoing ? "Sent Message" : "Received Message")
                            .font(.title3.bold())
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    // Content Section
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: contentIcon)
                                .font(.title3)
                                .foregroundStyle(accentColor)
                                .frame(width: 32)
                            Text("Content")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(16)

                        Divider().padding(.leading, 56)

                        switch message.content {
                        case .text(let text):
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                        case .location(let lat, let lon):
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Latitude")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.6f", lat))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .textSelection(.enabled)
                                }

                                HStack {
                                    Text("Longitude")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.6f", lon))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .textSelection(.enabled)
                                }

                                Divider()

                                Button {
                                    openInMaps(lat: lat, lon: lon)
                                } label: {
                                    HStack {
                                        Image(systemName: "map.fill")
                                        Text("Open in Maps")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    // Status Section
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "clock")
                                .font(.title3)
                                .foregroundStyle(accentColor)
                                .frame(width: 32)
                            Text("Status")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(16)

                        Divider().padding(.leading, 56)

                        // Sent time
                        HStack {
                            Text("Sent")
                                .font(.subheadline)
                            Spacer()
                            Text(message.timestamp, style: .relative)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        // Delivery status (for outgoing)
                        if message.isOutgoing {
                            Divider().padding(.leading, 56)
                            HStack {
                                Text("Delivery")
                                    .font(.subheadline)
                                Spacer()
                                deliveryStatusView
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        // Expiry (if present)
                        if let expiresAt = message.expiresAt {
                            Divider().padding(.leading, 56)
                            HStack {
                                Text("Expires")
                                    .font(.subheadline)
                                Spacer()
                                Text(expiresAt, style: .relative)
                                    .font(.subheadline)
                                    .foregroundStyle(expiresAt < Date() ? .red : .secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Copy button
                    Button {
                        copyContent()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy to Clipboard")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accentColor, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(accentColor)
                }
            }
        }
    }

    private var contentIcon: String {
        switch message.content {
        case .text: return "text.bubble"
        case .location: return "location.fill"
        }
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        switch message.deliveryStatus {
        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sending...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .sent:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text("Sent to server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .delivered:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Delivered")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .none:
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func copyContent() {
        switch message.content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .location(let lat, let lon):
            UIPasteboard.general.string = "\(lat), \(lon)"
        }
    }

    private func openInMaps(lat: Double, lon: Double) {
        let urlString = "maps://?ll=\(lat),\(lon)&q=Shared%20Location"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
