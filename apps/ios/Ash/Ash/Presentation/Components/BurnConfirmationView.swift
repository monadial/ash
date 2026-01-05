//
//  BurnConfirmationView.swift
//  Ash
//
//  Unified burn confirmation component
//  Simplified ephemeral design - immediate burn only
//

import SwiftUI

/// Unified burn confirmation view used across the app
/// Supports burning a single conversation or all conversations
struct BurnConfirmationView: View {
    /// Type of burn action
    enum BurnType {
        /// Burn a single conversation
        case conversation(name: String)
        /// Burn all conversations (emergency burn)
        case all
    }

    let burnType: BurnType
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmText = ""
    @State private var contentHeight: CGFloat = 0
    @FocusState private var isTextFieldFocused: Bool

    private let requiredText = "BURN"

    private var canBurn: Bool {
        confirmText.uppercased() == requiredText
    }

    private var title: String {
        switch burnType {
        case .conversation(let name):
            return "Burn \"\(name)\"?"
        case .all:
            return "Burn All Conversations?"
        }
    }

    private var subtitle: String {
        switch burnType {
        case .conversation:
            return "This conversation will be destroyed"
        case .all:
            return "All conversations will be destroyed"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)

            // Icon
            ZStack {
                Circle()
                    .fill(Color.ashDanger.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.ashDanger)
            }
            .padding(.bottom, Spacing.lg)

            // Title
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            // Subtitle
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.lg)

            // What will be destroyed
            VStack(alignment: .leading, spacing: Spacing.sm) {
                DestructionRow(icon: "key.fill", text: "Encryption pad")
                DestructionRow(icon: "bubble.left.and.bubble.right.fill", text: "All messages")
                DestructionRow(icon: "arrow.counterclockwise.circle.fill", text: "Cannot be recovered")
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal, Spacing.lg)

            Spacer()
                .frame(height: Spacing.xl)

            // Confirmation input
            VStack(spacing: Spacing.sm) {
                Text("Type \"\(requiredText)\" to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("", text: $confirmText)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .stroke(canBurn ? Color.ashDanger : Color(uiColor: .separator), lineWidth: canBurn ? 2 : 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .focused($isTextFieldFocused)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()
                .frame(height: Spacing.lg)

            // Buttons
            VStack(spacing: Spacing.sm) {
                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "flame.fill")
                        Text(burnType.isAll ? "Burn Everything" : "Burn Conversation")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(canBurn ? Color.ashDanger : Color.gray.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canBurn)

                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, Spacing.sm)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ContentHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            contentHeight = height
        }
        .presentationDetents([.height(contentHeight > 0 ? contentHeight : 600)])
        .presentationDragIndicator(.hidden)
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Helper Views

private struct DestructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.ashDanger.opacity(0.8))
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - BurnType Extension

extension BurnConfirmationView.BurnType {
    var isAll: Bool {
        if case .all = self { return true }
        return false
    }
}

// MARK: - Previews

#Preview("Single Conversation") {
    BurnConfirmationView(
        burnType: .conversation(name: "Alpha Bravo Charlie"),
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Burn All") {
    BurnConfirmationView(
        burnType: .all,
        onConfirm: {},
        onCancel: {}
    )
}
