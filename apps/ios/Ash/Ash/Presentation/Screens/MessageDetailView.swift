//
//  MessageDetailView.swift
//  Ash
//
//  Message details view
//  Apple HIG compliant design
//

import SwiftUI

struct MessageDetailView: View {
    let message: Message
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Content
                Section {
                    switch message.content {
                    case .text(let text):
                        Text(text)
                            .textSelection(.enabled)

                    case .location(let lat, let lon):
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Latitude") {
                                Text(String(format: "%.6f", lat))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            LabeledContent("Longitude") {
                                Text(String(format: "%.6f", lon))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                // Status
                Section {
                    LabeledContent("Sent") {
                        Text(message.timestamp, style: .relative)
                            .foregroundStyle(.secondary)
                    }

                    if message.isOutgoing {
                        LabeledContent("Status") {
                            deliveryStatusLabel
                        }
                    }

                    if let expiresAt = message.expiresAt {
                        LabeledContent("Expires") {
                            Text(expiresAt, style: .relative)
                                .foregroundStyle(expiresAt < Date() ? .red : .secondary)
                        }
                    }
                }
            }
            .navigationTitle(message.isOutgoing ? "Sent Message" : "Received Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var deliveryStatusLabel: some View {
        switch message.deliveryStatus {
        case .sending:
            Label("Sending", systemImage: "arrow.up.circle")
                .foregroundStyle(.secondary)
        case .sent:
            Label("Delivered", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            VStack(alignment: .trailing) {
                Label("Failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .none:
            Text("—")
                .foregroundStyle(.secondary)
        }
    }
}
