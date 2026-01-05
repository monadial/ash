//
//  BurnedConversationScreen.swift
//  Ash
//
//  Shows a conversation that has been burned by the peer
//  Simplified ephemeral design - immediate burn only
//

import SwiftUI

struct BurnedConversationScreen: View {
    let conversationName: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Burned icon
            ZStack {
                Circle()
                    .fill(Color.ashDanger.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "flame.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.ashDanger)
            }

            VStack(spacing: Spacing.sm) {
                Text("Conversation Burned")
                    .font(.title2.bold())

                Text("\"\(conversationName)\" was burned by the other party.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Text("This conversation and all messages have been permanently destroyed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Dismiss")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Previews

#Preview {
    BurnedConversationScreen(
        conversationName: "Alpha Bravo Charlie",
        onDismiss: {}
    )
}
