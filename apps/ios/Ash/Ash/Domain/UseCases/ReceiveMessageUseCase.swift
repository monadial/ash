//
//  ReceiveMessageUseCase.swift
//  Ash
//

import Foundation

protocol ReceiveMessageUseCaseProtocol: Sendable {
    func execute(
        ciphertext: Data,
        sequence: UInt64?,
        in conversation: Conversation
    ) async throws -> (message: Message, updatedConversation: Conversation)
}

enum ReceiveMessageError: Error, Sendable {
    case insufficientPad
    case decryptionFailed
    case conversationExhausted
    case invalidCiphertext
    case missingSequence
}

final class ReceiveMessageUseCase: ReceiveMessageUseCaseProtocol, Sendable {
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
        ciphertext: Data,
        sequence: UInt64?,
        in conversation: Conversation
    ) async throws -> (message: Message, updatedConversation: Conversation) {
        let ciphertextBytes = Array(ciphertext)

        Log.debug(.crypto, "Decrypting message (\(ciphertextBytes.count) bytes)")

        // Sequence is required to know which pad offset the sender used
        // The sender includes the actual pad offset in the sequence field
        guard let offset = sequence else {
            Log.warning(.crypto, "Missing sequence!")
            throw ReceiveMessageError.missingSequence
        }

        // Validate offset is within pad bounds
        guard offset + UInt64(ciphertextBytes.count) <= conversation.totalBytes else {
            Log.warning(.crypto, "Invalid pad offset")
            throw ReceiveMessageError.insufficientPad
        }

        // Get pad bytes for decryption using the sender's offset (sequence)
        let keyBytes = try await padManager.getBytesForDecryption(
            offset: offset,
            length: UInt64(ciphertextBytes.count),
            for: conversation.id
        )

        Log.verbose(.crypto, "Key material retrieved")

        // Decrypt the message content
        let plaintext: [UInt8]
        do {
            plaintext = try cryptoService.decrypt(ciphertext: ciphertextBytes, key: keyBytes)
            Log.verbose(.crypto, "Decryption complete")
        } catch {
            Log.error(.crypto, "Decryption failed")
            throw ReceiveMessageError.decryptionFailed
        }

        // Calculate peer's consumption and update Rust Pad (shared logic with Android)
        let peerRole: Role = conversation.role == .initiator ? .responder : .initiator
        let peerConsumed = calculatePeerConsumed(
            sequence: offset,
            length: UInt64(ciphertextBytes.count),
            totalBytes: conversation.totalBytes,
            myRole: conversation.role
        )

        try await padManager.updatePeerConsumption(
            peerRole: peerRole,
            consumed: peerConsumed,
            for: conversation.id
        )

        // Update conversation state
        let updatedConversation = conversation.afterReceiving(
            sequence: offset,
            length: UInt64(ciphertextBytes.count)
        )
        try await conversationRepository.save(updatedConversation)
        Log.debug(.crypto, "Conversation state updated")

        // Decode plaintext to content (text or location)
        let content = decodeContent(plaintext)

        switch content {
        case .text:
            Log.debug(.crypto, "Content type: text")
        case .location:
            Log.debug(.crypto, "Content type: location")
        }

        // Create the incoming message with the sequence for deduplication
        // Use the conversation's TTL for local message expiration
        let message = Message.incoming(
            content: content,
            sequence: offset,
            expiresIn: TimeInterval(MessageTTL.defaultSeconds)
        )

        return (message, updatedConversation)
    }

    /// Decode plaintext bytes to MessageContent
    /// Location messages are prefixed with "LOC:" followed by "lat,lon"
    private func decodeContent(_ plaintext: [UInt8]) -> MessageContent {
        let text = String(decoding: plaintext, as: UTF8.self)

        // Check for location prefix
        if text.hasPrefix("LOC:") {
            let coordString = String(text.dropFirst(4))  // Remove "LOC:" prefix
            let parts = coordString.split(separator: ",")
            if parts.count == 2,
               let lat = Double(parts[0]),
               let lon = Double(parts[1]) {
                return .location(latitude: lat, longitude: lon)
            }
        }

        // Default to text
        return .text(text)
    }

    /// Calculate how much the peer has consumed based on their message sequence
    private func calculatePeerConsumed(
        sequence: UInt64,
        length: UInt64,
        totalBytes: UInt64,
        myRole: ConversationRole
    ) -> UInt64 {
        switch myRole {
        case .initiator:
            // We're initiator, peer is responder (consumes backward)
            // Peer's sequence is the START of their consumption from the END
            // peerConsumed = totalBytes - sequence
            return totalBytes - sequence
        case .responder:
            // We're responder, peer is initiator (consumes forward)
            // Peer's sequence is the START of their consumption from the FRONT
            // peerConsumed = sequence + length
            return sequence + length
        }
    }
}
