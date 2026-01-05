//
//  SendMessageUseCase.swift
//  Ash
//

import Foundation

struct SendMessageResult: Sendable {
    let message: Message
    let updatedConversation: Conversation
    let ciphertext: Data
    let sequence: UInt64
}

protocol SendMessageUseCaseProtocol: Sendable {
    func execute(
        content: MessageContent,
        in conversation: Conversation
    ) async throws -> SendMessageResult
}

enum SendMessageError: Error, Sendable {
    case insufficientPad
    case encryptionFailed
    case conversationExhausted
}

final class SendMessageUseCase: SendMessageUseCaseProtocol, Sendable {
    private let padManager: PadManagerProtocol
    private let conversationRepository: ConversationRepository
    private let cryptoService: CryptoServiceProtocol

    init(
        padManager: PadManagerProtocol,
        conversationRepository: ConversationRepository,
        cryptoService: CryptoServiceProtocol
    ) {
        self.padManager = padManager
        self.conversationRepository = conversationRepository
        self.cryptoService = cryptoService
    }

    func execute(
        content: MessageContent,
        in conversation: Conversation
    ) async throws -> SendMessageResult {
        let messageBytes = content.byteCount
        Log.debug(.crypto, "Encrypting message (\(messageBytes) bytes)")

        // Convert conversation role to Rust Role
        let role: Role = conversation.role == .initiator ? .initiator : .responder

        // Use Rust Pad for allocation check (shared logic with Android)
        let canSend = try await padManager.canSend(
            length: UInt32(messageBytes),
            role: role,
            for: conversation.id
        )

        guard canSend else {
            Log.warning(.crypto, "Insufficient pad!")
            throw SendMessageError.insufficientPad
        }

        // Calculate sequence (offset where key material STARTS)
        // - Initiator: key starts at consumed_front (before consume)
        // - Responder: key starts at total_size - consumed_back - message_size
        let sequence: UInt64
        if role == .responder {
            let padState = try await padManager.getPadState(for: conversation.id)
            sequence = padState.totalBytes - padState.consumedBack - UInt64(messageBytes)
        } else {
            sequence = try await padManager.nextSendOffset(role: role, for: conversation.id)
        }
        Log.verbose(.crypto, "Pad allocation successful, sequence: \(sequence)")

        // Consume pad bytes and get key material (uses Rust Pad)
        let keyBytes = try await padManager.consumeForSending(
            length: UInt32(messageBytes),
            role: role,
            for: conversation.id
        )

        Log.verbose(.crypto, "Key material retrieved")

        let plaintext = encodeContent(content)
        let ciphertext = try cryptoService.encrypt(plaintext: plaintext, key: keyBytes)
        Log.verbose(.crypto, "Encryption complete")

        // Update conversation state
        let updatedConversation = conversation.afterSending(bytes: UInt64(messageBytes))
        try await conversationRepository.save(updatedConversation)

        Log.debug(.crypto, "Conversation state updated")

        let message = createOutgoingMessage(
            for: content,
            sequence: sequence,
            ttl: TimeInterval(MessageTTL.defaultSeconds)
        )

        return SendMessageResult(
            message: message,
            updatedConversation: updatedConversation,
            ciphertext: Data(ciphertext),
            sequence: sequence
        )
    }

    private func encodeContent(_ content: MessageContent) -> [UInt8] {
        switch content {
        case .text(let text):
            return Array(text.utf8)
        case .location(let lat, let lon):
            let str = String(format: "LOC:%.6f,%.6f", lat, lon)
            return Array(str.utf8)
        }
    }

    private func createOutgoingMessage(for content: MessageContent, sequence: UInt64, ttl: TimeInterval) -> Message {
        switch content {
        case .text(let text):
            return Message.outgoing(text: text, sequence: sequence, expiresIn: ttl)
        case .location(let lat, let lon):
            return Message.outgoingLocation(latitude: lat, longitude: lon, sequence: sequence, expiresIn: ttl)
        }
    }
}
