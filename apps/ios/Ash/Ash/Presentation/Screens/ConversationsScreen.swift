//
//  ConversationsScreen.swift
//  Ash
//
//  Conversations list
//

import SwiftUI

// Liquid Glass redesign applied

struct ConversationsScreen: View {
    @Bindable var viewModel: AppViewModel
    @State private var conversationToBurn: Conversation?

    var body: some View {
        GlassEffectContainer {
            Group {
                if viewModel.conversations.isEmpty {
                    emptyState
                } else {
                    conversationsList
                }
            }
            .glassEffect()
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.glassProminent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .sheet(item: $conversationToBurn) { conversation in
                BurnConfirmationView(
                    burnType: .conversation(name: conversation.displayName),
                    onConfirm: {
                        // Capture conversation before dismissing sheet
                        let conversationToDelete = conversation
                        // First dismiss the sheet
                        conversationToBurn = nil
                        // Then burn after a brief delay to allow UI to update
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                            await viewModel.burnConversation(conversationToDelete)
                        }
                    },
                    onCancel: {
                        conversationToBurn = nil
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Start a secure conversation by performing a ceremony with another device.")
        } actions: {
            Button {
                viewModel.startNewConversation()
            } label: {
                Text("New Conversation")
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - List

    private var conversationsList: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectConversation(conversation)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            conversationToBurn = conversation
                        } label: {
                            Label("Burn", systemImage: "flame.fill")
                        }
                        .tint(Color.ashDanger)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadConversations()
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: Conversation

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.lastActivity, relativeTo: Date())
    }

    private var statusColor: Color {
        if conversation.isExhausted { return .red }
        if conversation.usagePercentage > 0.9 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Text(conversation.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if conversation.isExhausted || conversation.usagePercentage > 0.9 {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                Text(timeAgo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }

            // Subtitle row
            HStack {
                // Mnemonic
                Text(conversation.mnemonicChecksum.prefix(3).joined(separator: " "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Remaining
                Text(conversation.formattedRemaining)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
            }

            // Usage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(Color(uiColor: .systemFill))

                    // My usage (from left)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * min(1, conversation.myUsagePercentage))

                    // Peer usage (from right)
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: geo.size.width * min(1, conversation.peerUsagePercentage))
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.displayName), \(conversation.formattedRemaining) remaining")
    }
}

#Preview {
    NavigationStack {
        ConversationsScreen(viewModel: AppViewModel(dependencies: Dependencies()))
    }
}
