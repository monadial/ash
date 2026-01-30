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
        let plaintextBytes = content.byteCount
        // Total pad consumption: 64 bytes auth + plaintext length
        let totalPadConsumption = cryptoService.calculatePadConsumption(plaintextLength: plaintextBytes)
        Log.debug(.crypto, "Encrypting message (\(plaintextBytes) bytes plaintext, \(totalPadConsumption) bytes pad)")

        // Convert conversation role to Rust Role
        let role: Role = conversation.role == .initiator ? .initiator : .responder

        // Use Rust Pad for allocation check (shared logic with Android)
        let canSend = try await padManager.canSend(
            length: UInt32(totalPadConsumption),
            role: role,
            for: conversation.id
        )

        guard canSend else {
            Log.warning(.crypto, "Insufficient pad!")
            throw SendMessageError.insufficientPad
        }

        // Calculate sequence (offset where key material STARTS)
        // - Initiator: key starts at consumed_front (before consume)
        // - Responder: key starts at total_size - consumed_back - total_pad_consumption
        let sequence: UInt64
        if role == .responder {
            let padState = try await padManager.getPadState(for: conversation.id)
            sequence = padState.totalBytes - padState.consumedBack - UInt64(totalPadConsumption)
        } else {
            sequence = try await padManager.nextSendOffset(role: role, for: conversation.id)
        }
        Log.verbose(.crypto, "Pad allocation successful, sequence: \(sequence)")

        // Consume pad bytes and get key material (uses Rust Pad)
        // Total: 64 bytes auth key + plaintext length encryption key
        let keyBytes = try await padManager.consumeForSending(
            length: UInt32(totalPadConsumption),
            role: role,
            for: conversation.id
        )

        // Split key material: first 64 bytes for auth, rest for encryption
        let authKey = Array(keyBytes.prefix(AUTH_OVERHEAD))
        let encryptionKey = Array(keyBytes.dropFirst(AUTH_OVERHEAD))
        Log.verbose(.crypto, "Key material split: \(authKey.count) auth + \(encryptionKey.count) encryption bytes")

        let plaintext = encodeContent(content)
        let messageType = content.messageType
        let ciphertext = try cryptoService.encryptAuthenticated(
            plaintext: plaintext,
            authKey: authKey,
            encryptionKey: encryptionKey,
            messageType: messageType
        )
        Log.verbose(.crypto, "Authenticated encryption complete")

        // Update conversation state with total pad consumption
        let updatedConversation = conversation.afterSending(bytes: UInt64(totalPadConsumption))
        try await conversationRepository.save(updatedConversation)

        Log.debug(.crypto, "Conversation state updated")

        // Server uses fixed 5-minute (300s) TTL - use this as initial estimate
        // The actual expiry will be updated from server response via withServerExpiresAt()
        let message = createOutgoingMessage(
            for: content,
            sequence: sequence,
            ttl: 300
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
            return Message.outgoing(text: text, sequence: sequence, serverTTLSeconds: ttl)
        case .location(let lat, let lon):
            return Message.outgoingLocation(latitude: lat, longitude: lon, sequence: sequence, serverTTLSeconds: ttl)
        }
    }
}
