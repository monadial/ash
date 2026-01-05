//
//  BurnConfirmationView.swift
//  Ash
//
//  Unified burn confirmation component - Modern danger design
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
    @State private var isAnimating = false
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
            return "This action cannot be undone"
        case .all:
            return "Emergency destruction of all data"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.ashDanger.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)

            // Animated flame icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ashDanger.opacity(0.3), Color.ashDanger.opacity(0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)

                // Inner circle
                Circle()
                    .fill(Color.ashDanger.opacity(0.15))
                    .frame(width: 88, height: 88)

                // Flame icon
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.ashDanger)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
            }
            .padding(.bottom, Spacing.lg)

            // Title
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color.ashDanger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            // Subtitle
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.lg)

            // Warning card
            VStack(spacing: 0) {
                // Header
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ashDanger)

                    Text("Will be permanently destroyed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ashDanger)

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.ashDanger.opacity(0.1))

                // Items
                VStack(spacing: 0) {
                    DestructionRow(
                        icon: "key.fill",
                        text: "Encryption pad & keys",
                        isFirst: true
                    )

                    Divider().padding(.leading, 48)

                    DestructionRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        text: "All message history",
                        isFirst: false
                    )

                    Divider().padding(.leading, 48)

                    DestructionRow(
                        icon: "person.2.fill",
                        text: "Connection with peer",
                        isFirst: false
                    )

                    if burnType.isAll {
                        Divider().padding(.leading, 48)

                        DestructionRow(
                            icon: "tray.full.fill",
                            text: "All conversations",
                            isFirst: false
                        )
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .strokeBorder(Color.ashDanger.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)

            Spacer().frame(height: Spacing.xl)

            // Confirmation input section
            VStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Type \"\(requiredText)\" to confirm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.sm) {
                    TextField("", text: $confirmText)
                        .font(.title3.bold().monospaced())
                        .multilineTextAlignment(.center)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .fill(canBurn ? Color.ashDanger.opacity(0.1) : Color(uiColor: .tertiarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .strokeBorder(
                                    canBurn ? Color.ashDanger : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($isTextFieldFocused)

                    // Checkmark indicator
                    ZStack {
                        Circle()
                            .fill(canBurn ? Color.ashDanger : Color(uiColor: .systemFill))
                            .frame(width: 36, height: 36)

                        Image(systemName: canBurn ? "checkmark" : "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(canBurn ? .white : .secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)

            Spacer().frame(height: Spacing.lg)

            // Action buttons
            VStack(spacing: Spacing.sm) {
                // Burn button
                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "flame.fill")
                            .font(.headline)
                        Text(burnType.isAll ? "Burn Everything" : "Burn Forever")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(canBurn ? Color.ashDanger : Color(uiColor: .systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canBurn)
                .animation(.easeInOut(duration: 0.2), value: canBurn)

                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.plain)
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
        .presentationDetents([.height(contentHeight > 0 ? contentHeight : 650)])
        .presentationDragIndicator(.hidden)
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            isTextFieldFocused = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Destruction Row

private struct DestructionRow: View {
    let icon: String
    let text: String
    let isFirst: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.ashDanger.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.ashDanger)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.ashDanger.opacity(0.6))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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
        burnType: .conversation(name: "Alpha Bravo"),
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
