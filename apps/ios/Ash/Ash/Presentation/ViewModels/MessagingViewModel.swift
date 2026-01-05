//
//  MessagingViewModel.swift
//  Ash
//

import SwiftUI

@MainActor
@Observable
final class MessagingViewModel {
    private let dependencies: Dependencies
    private let actualMessageRepository: MessageRepository
    let conversation: Conversation

    private(set) var messages: [Message] = []
    private(set) var currentConversation: Conversation
    var messageText = ""
    var isShowingBurnConfirmation = false
    private(set) var isConnected = false
    private(set) var relayError: String?
    private(set) var peerBurned = false
    private(set) var messageSizeError: String?
    private(set) var isGettingLocation = false
    private(set) var locationError: String?

    // Burn states
    var isShowingBurnedScreen = false
    private(set) var burnCompleted = false

    var currentMessageBytes: Int { messageText.utf8.count }
    var isMessageTooLarge: Bool { currentMessageBytes > MessageLimits.maxMessageBytes }
    var isApproachingLimit: Bool { currentMessageBytes > MessageLimits.warningThresholdBytes && !isMessageTooLarge }

    var formattedMessageSize: String {
        let kb = Double(currentMessageBytes) / 1024.0
        return kb < 1 ? "\(currentMessageBytes) B" : String(format: "%.1f KB", kb)
    }

    var canSendMessage: Bool {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && !isMessageTooLarge && currentConversation.canSendMessage(ofLength: currentMessageBytes)
    }

    private var expiryTimer: Timer?
    private var sseService: SSEService?
    private var sseTask: Task<Void, Never>?
    private var pollingTimer: Timer?
    private var lastCursor: RelayCursor?
    private let pollingInterval: TimeInterval = 10.0
    private var conversationRelay: RelayServiceProtocol?
    private var sentBlobIds: Set<UUID> = []
    private var sentSequences: Set<UInt64> = []
    private var processedBlobIds: Set<UUID> = []
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Never>?
    private var isSSEConnecting = false
    private var pushNotificationObserver: NSObjectProtocol?
    private var deviceTokenObserver: NSObjectProtocol?
    private var pushRegistrationTask: Task<Void, Never>?

    /// Short conversation ID for logging (first 8 chars)
    private var logId: String { String(conversation.id.prefix(8)) }

    init(conversation: Conversation, dependencies: Dependencies) {
        self.conversation = conversation
        self.currentConversation = conversation
        self.dependencies = dependencies
        self.actualMessageRepository = dependencies.messageRepository
        self.conversationRelay = dependencies.createRelayService(for: conversation.relayURL)
        self.sseService = SSEService(baseURLString: conversation.relayURL)

        // Listen for push notifications targeting this conversation
        setupPushNotificationHandling()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        // Refresh conversation from Keychain to get latest state (including processedIncomingSequences)
        if let fresh = try? await dependencies.conversationRepository.get(id: conversation.id) {
            currentConversation = fresh
            Log.debug(.storage, "[\(logId)] Refreshed conversation from Keychain, processed sequences: \(fresh.processedIncomingSequences.count)")
        }

        // Ephemeral-only: messages exist only in UI while viewing
        messages = []
        Log.info(.message, "[\(logId)] Ephemeral mode - fetching from relay")

        startExpiryTimer()
        lastCursor = currentConversation.relayCursor
        await pollForMessages()
        connectSSE()

        // Register device for push notifications with the relay
        await registerForPushNotifications()
    }

    func onDisappear() async {
        do {
            try await dependencies.conversationRepository.save(currentConversation)
            Log.debug(.storage, "[\(logId)] State saved on disappear")
        } catch {
            Log.error(.storage, "[\(logId)] Failed to save state: \(error)")
        }

        stopExpiryTimer()
        disconnectSSE()
        stopPolling()
        cleanupPushNotificationHandling()
    }

    var updatedConversation: Conversation { currentConversation }

    // MARK: - Actions

    func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageSizeError = nil
        let messageBytes = text.utf8.count

        if messageBytes > MessageLimits.maxMessageBytes {
            let currentKB = (messageBytes + 1023) / 1024
            messageSizeError = L10n.Error.messageTooLargeDetail(MessageLimits.maxMessageKB, currentKB)
            dependencies.hapticService.error()
            Log.warning(.message, "[\(logId)] Message rejected: \(messageBytes) bytes exceeds \(MessageLimits.maxMessageBytes) limit")
            return
        }

        if !currentConversation.canSendMessage(ofLength: messageBytes) {
            messageSizeError = L10n.Error.insufficientPad
            dependencies.hapticService.error()
            Log.warning(.message, "[\(logId)] Insufficient pad: need \(messageBytes) bytes, have \(currentConversation.remainingBytes)")
            return
        }

        dependencies.hapticService.light()
        Log.info(.message, "[\(logId)] Sending text: \(messageBytes) bytes, pad remaining: \(currentConversation.remainingBytes)")

        do {
            let result = try await Log.measureAsync(.crypto, "encrypt") {
                try await dependencies.sendMessageUseCase.execute(content: .text(text), in: currentConversation)
            }

            Log.debug(.message, "[\(logId)] Encrypted: \(messageBytes) → \(result.ciphertext.count) bytes, seq=\(result.sequence)")

            sentSequences.insert(result.sequence)

            // Ephemeral-only: message lives in UI while viewing (and on relay until delivered)
            insertMessageSorted(result.message)
            currentConversation = result.updatedConversation
            messageText = ""

            try? await dependencies.conversationRepository.save(currentConversation)

            await submitToRelay(messageId: result.message.id, ciphertext: result.ciphertext, sequence: result.sequence)
        } catch {
            Log.error(.message, "[\(logId)] Send failed: \(error)")
            dependencies.hapticService.error()
        }
    }

    func sendLocation() async {
        locationError = nil
        isGettingLocation = true
        defer { isGettingLocation = false }

        let estimatedBytes = 28
        guard currentConversation.canSendMessage(ofLength: estimatedBytes) else {
            locationError = L10n.Error.insufficientPad
            dependencies.hapticService.error()
            Log.warning(.message, "[\(logId)] Location rejected: need \(estimatedBytes) bytes, have \(currentConversation.remainingBytes)")
            return
        }

        do {
            let (latitude, longitude) = try await dependencies.locationService.getCurrentLocation()
            dependencies.hapticService.light()

            Log.info(.message, "[\(logId)] Sending location, pad remaining: \(currentConversation.remainingBytes)")

            let result = try await Log.measureAsync(.crypto, "encrypt location") {
                try await dependencies.sendMessageUseCase.execute(
                    content: .location(latitude: latitude, longitude: longitude),
                    in: currentConversation
                )
            }

            Log.debug(.message, "[\(logId)] Location encrypted: \(result.ciphertext.count) bytes, seq=\(result.sequence)")

            sentSequences.insert(result.sequence)

            // Ephemeral-only: message lives in UI while viewing
            insertMessageSorted(result.message)
            currentConversation = result.updatedConversation

            try? await dependencies.conversationRepository.save(currentConversation)

            await submitToRelay(messageId: result.message.id, ciphertext: result.ciphertext, sequence: result.sequence)
            dependencies.hapticService.success()

        } catch let error as LocationError {
            Log.error(.message, "[\(logId)] Location error: \(error)")
            dependencies.hapticService.error()

            switch error {
            case .permissionDenied: locationError = "Location permission denied. Enable in Settings."
            case .permissionRestricted: locationError = "Location access restricted."
            case .locationUnavailable: locationError = "Unable to get location."
            case .timeout: locationError = "Location request timed out."
            }
        } catch {
            Log.error(.message, "[\(logId)] Location send failed: \(error)")
            dependencies.hapticService.error()
            locationError = "Failed to send location."
        }
    }

    private func submitToRelay(messageId: UUID, ciphertext: Data, sequence: UInt64) async {
        guard let relay = conversationRelay else {
            Log.warning(.relay, "[\(logId)] No relay configured")
            await updateMessageDeliveryStatus(messageId, status: .failed(reason: L10n.Error.noConnection))
            return
        }

        do {
            // Ephemeral-only mode: all messages stored in RAM on server
            let blobId = try await Log.measureAsync(.relay, "submit") {
                try await relay.submitMessage(
                    conversationId: conversation.id,
                    authToken: conversation.authToken,
                    ciphertext: ciphertext,
                    sequence: sequence,
                    ttlSeconds: MessageTTL.defaultSeconds,
                    extendedTTL: false,
                    persistent: false
                )
            }
            sentBlobIds.insert(blobId)
            await updateMessageDeliveryStatus(messageId, status: .sent)
            Log.info(.relay, "[\(logId)] Submitted: \(ciphertext.count) bytes, seq=\(sequence), ttl=\(MessageTTL.defaultSeconds)s")
        } catch {
            dependencies.hapticService.error()
            await updateMessageDeliveryStatus(messageId, status: .failed(reason: L10n.Error.relayError))
            Log.error(.relay, "[\(logId)] Submit failed: \(error)")
        }
    }

    private func updateMessageDeliveryStatus(_ messageId: UUID, status: DeliveryStatus) async {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            let updatedMessage = messages[index].withDeliveryStatus(status)
            messages[index] = updatedMessage
            await actualMessageRepository.replaceMessage(updatedMessage, in: conversation.id)
        }
    }

    func retryMessage(_ message: Message) async {
        guard message.isOutgoing, case .failed = message.deliveryStatus else { return }

        Log.info(.message, "[\(logId)] Retry requested for message")
        await updateMessageDeliveryStatus(message.id, status: .sending)
        dependencies.hapticService.light()
        await updateMessageDeliveryStatus(message.id, status: .failed(reason: L10n.Error.relayError))
    }

    func burn() async {
        Log.info(.message, "[\(logId)] Burn initiated")
        dependencies.hapticService.heavy()

        do {
            try await dependencies.burnConversationUseCase.execute(conversation: currentConversation)
            burnCompleted = true
            Log.info(.message, "[\(logId)] Burn completed - conversation wiped")
        } catch {
            Log.error(.message, "[\(logId)] Burn failed: \(error)")
        }
    }

    /// Handle peer burn notification - show burned screen
    func handlePeerBurned() async {
        Log.warning(.message, "[\(logId)] Peer burned conversation")
        peerBurned = true
        isShowingBurnedScreen = true
    }

    func refresh() async {
        Log.debug(.poll, "[\(logId)] Manual refresh requested")
        await pollForMessages()
    }

    // MARK: - SSE Streaming

    private func connectSSE() {
        // Cancel any pending reconnect
        reconnectTask?.cancel()
        reconnectTask = nil

        guard !isSSEConnecting else {
            Log.debug(.sse, "[\(logId)] Already connecting, skipping")
            return
        }

        guard let sseService = sseService else {
            Log.info(.sse, "[\(logId)] SSE unavailable, using polling")
            startFallbackPolling()
            return
        }

        // Cancel existing task before creating new one
        sseTask?.cancel()
        sseTask = nil

        isSSEConnecting = true
        isConnected = false
        Log.info(.sse, "[\(logId)] Connecting to stream (attempt \(reconnectAttempts + 1))")

        sseTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = sseService.connect(conversationId: self.conversation.id, authToken: self.conversation.authToken)
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self.handleSSEEvent(event)
            }
            // Stream ended - if not cancelled and not connected, this is a disconnect
            if !Task.isCancelled && !self.isConnected {
                await MainActor.run {
                    self.isSSEConnecting = false
                }
            }
        }
    }

    private func disconnectSSE() {
        Log.debug(.sse, "[\(logId)] Disconnecting")
        reconnectTask?.cancel()
        reconnectTask = nil
        sseTask?.cancel()
        sseTask = nil
        sseService?.disconnect()
        isSSEConnecting = false
        isConnected = false
    }

    private func handleSSEEvent(_ event: SSEEvent) async {
        // Don't process events if task was cancelled
        guard sseTask?.isCancelled != true else { return }

        switch event {
        case .connected:
            Log.info(.sse, "[\(logId)] Connected, processed=\(processedBlobIds.count)")
            isSSEConnecting = false
            isConnected = true
            relayError = nil
            // Don't reset reconnectAttempts here - wait for actual message/ping
            stopPolling()

        case .disconnected:
            Log.warning(.sse, "[\(logId)] Disconnected")
            isSSEConnecting = false
            isConnected = false
            // Only schedule reconnect if we're not already reconnecting
            if reconnectTask == nil {
                scheduleReconnect()
            }

        case .message(let message):
            // Reset reconnect attempts on successful message (connection is healthy)
            reconnectAttempts = 0

            if sentBlobIds.contains(message.id) || (message.sequence.map { sentSequences.contains($0) } ?? false) {
                Log.verbose(.sse, "[\(logId)] Skipping own message")
                if message.sequence != nil { sentBlobIds.insert(message.id) }
                return
            }

            if processedBlobIds.contains(message.id) {
                Log.verbose(.sse, "[\(logId)] Skipping duplicate")
                return
            }

            Log.debug(.sse, "[\(logId)] Received: \(message.ciphertext.count) bytes, seq=\(message.sequence ?? 0)")

            let relayMessage = RelayMessage(
                id: message.id,
                sequence: message.sequence,
                ciphertext: message.ciphertext,
                receivedAt: message.receivedAt
            )

            await processReceivedMessage(relayMessage)
            processedBlobIds.insert(message.id)

        case .burned:
            Log.warning(.sse, "[\(logId)] Peer burned conversation")
            peerBurned = true
            dependencies.hapticService.warning()
            disconnectSSE()

        case .ping:
            // Reset reconnect attempts on ping (connection is healthy)
            reconnectAttempts = 0

        case .error(let error):
            Log.error(.sse, "[\(logId)] Error: \(error)")
            isSSEConnecting = false
            isConnected = false
            relayError = "Connection error"
            // Only schedule reconnect if we're not already reconnecting
            if reconnectTask == nil {
                scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        // Don't reconnect if already at max attempts
        guard reconnectAttempts < maxReconnectAttempts else {
            Log.warning(.sse, "[\(logId)] Max reconnects (\(maxReconnectAttempts)) reached, using polling")
            isSSEConnecting = false
            startFallbackPolling()
            return
        }

        // Don't schedule if there's already a pending reconnect
        guard reconnectTask == nil else {
            Log.debug(.sse, "[\(logId)] Reconnect already scheduled, skipping")
            return
        }

        reconnectAttempts += 1
        // Exponential backoff with jitter: base delay 2, 4, 8, 16, 32 seconds + random 0-1s
        let baseDelay = pow(2.0, Double(reconnectAttempts))
        let jitter = Double.random(in: 0...1)
        let delay = baseDelay + jitter

        Log.info(.sse, "[\(logId)] Reconnect \(reconnectAttempts)/\(maxReconnectAttempts) in \(String(format: "%.1f", delay))s")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.reconnectTask = nil  // Clear before connecting
                self?.connectSSE()
            }
        }
    }

    // MARK: - Polling

    private func startFallbackPolling() {
        guard conversationRelay != nil, pollingTimer == nil else { return }

        Log.info(.poll, "[\(logId)] Starting polling (interval: \(Int(pollingInterval))s)")

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.pollForMessages() }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollForMessages() async {
        guard let relay = conversationRelay else { return }

        do {
            let burnStatus = try await relay.checkBurnStatus(conversationId: conversation.id, authToken: conversation.authToken)
            if burnStatus.burned {
                Log.warning(.poll, "[\(logId)] Peer burned conversation")
                peerBurned = true
                dependencies.hapticService.warning()
                return
            }

            let response = try await relay.pollMessages(conversationId: conversation.id, authToken: conversation.authToken, cursor: lastCursor)

            if response.messages.count > 0 {
                Log.debug(.poll, "[\(logId)] Received \(response.messages.count) messages")
            }

            if response.nextCursor != lastCursor {
                lastCursor = response.nextCursor
                await saveCursor(response.nextCursor)
            }

            if response.burned {
                peerBurned = true
                dependencies.hapticService.warning()
                return
            }

            var processedCount = 0
            for relayMessage in response.messages {
                if sentBlobIds.contains(relayMessage.id) { continue }
                if let seq = relayMessage.sequence, sentSequences.contains(seq) {
                    sentBlobIds.insert(relayMessage.id)
                    continue
                }
                if processedBlobIds.contains(relayMessage.id) { continue }

                await processReceivedMessage(relayMessage)
                processedBlobIds.insert(relayMessage.id)
                processedCount += 1
            }

            if processedCount > 0 {
                Log.info(.poll, "[\(logId)] Processed \(processedCount) new messages")
            }

            relayError = nil
        } catch let error as RelayError {
            switch error {
            case .conversationBurned:
                Log.warning(.poll, "[\(logId)] Conversation burned")
                peerBurned = true
                dependencies.hapticService.warning()
            case .noConnection:
                relayError = "No connection to relay"
            case .networkError(let underlying):
                Log.debug(.poll, "[\(logId)] Network error: \(underlying)")
                relayError = "No connection to relay"
            case .decodingError(let underlying):
                Log.debug(.poll, "[\(logId)] Decode error: \(underlying)")
                relayError = "Failed to decode response"
            default:
                Log.error(.poll, "[\(logId)] Relay error: \(error)")
                relayError = "Relay error"
            }
        } catch {
            Log.error(.poll, "[\(logId)] Poll failed: \(error)")
            relayError = "Connection error"
        }
    }

    private func saveCursor(_ cursor: String?) async {
        let updated = currentConversation.withCursor(cursor)
        do {
            try await dependencies.conversationRepository.save(updated)
            currentConversation = updated
        } catch {
            Log.error(.storage, "[\(logId)] Cursor save failed: \(error)")
        }
    }

    private func processReceivedMessage(_ relayMessage: RelayMessage) async {
        // Check if we already processed this sequence (stored in Keychain with conversation)
        if let sequence = relayMessage.sequence {
            // First, check if this is our OWN sent message (which the relay returns when polling)
            // We must skip these to avoid corrupting peerConsumed state
            let isOwnMessage: Bool
            switch currentConversation.role {
            case .initiator:
                // Initiator sends from [0, sendOffset) - messages in this range are ours
                isOwnMessage = sequence < currentConversation.sendOffset
            case .responder:
                // Responder sends from [totalBytes - sendOffset, totalBytes) - messages in this range are ours
                isOwnMessage = sequence >= currentConversation.totalBytes - currentConversation.sendOffset
            }

            if isOwnMessage {
                Log.debug(.message, "[\(logId)] Skipping own sent message seq=\(sequence)")
                return
            }

            if currentConversation.hasProcessedIncomingSequence(sequence) {
                Log.debug(.message, "[\(logId)] Skipping already-processed message seq=\(sequence) (conversation)")
                return
            }
            // Also check repository for persistent messages as fallback
            let alreadyExists = await actualMessageRepository.hasMessage(withSequence: sequence, in: conversation.id)
            if alreadyExists {
                Log.debug(.message, "[\(logId)] Skipping already-processed message seq=\(sequence) (repository)")
                return
            }
        }

        Log.debug(.message, "[\(logId)] Decrypting: \(relayMessage.ciphertext.count) bytes, seq=\(relayMessage.sequence ?? 0)")

        do {
            let result = try await Log.measureAsync(.crypto, "decrypt") {
                try await dependencies.receiveMessageUseCase.execute(
                    ciphertext: relayMessage.ciphertext,
                    sequence: relayMessage.sequence,
                    in: currentConversation
                )
            }

            let contentType: String
            switch result.message.content {
            case .text: contentType = "text"
            case .location: contentType = "location"
            }

            Log.info(.message, "[\(logId)] Decrypted \(contentType), pad remaining: \(result.updatedConversation.remainingBytes)")

            // Ephemeral-only: message lives in UI, relay keeps it until TTL
            insertMessageSorted(result.message)
            currentConversation = result.updatedConversation

            try? await dependencies.conversationRepository.save(currentConversation)
        } catch {
            Log.error(.message, "[\(logId)] Decrypt failed: \(error)")
        }

        dependencies.hapticService.light()
    }

    private func insertMessageSorted(_ message: Message) {
        // Check for duplicate by sequence to prevent duplicates in the UI
        if let seq = message.sequence, messages.contains(where: { $0.sequence == seq }) {
            Log.debug(.message, "[\(logId)] Skipping duplicate message insertion seq=\(seq)")
            return
        }
        let insertIndex = messages.firstIndex { $0 > message } ?? messages.endIndex
        messages.insert(message, at: insertIndex)
    }

    // MARK: - Expiry

    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneExpiredMessages() }
        }
    }

    private func stopExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    private func pruneExpiredMessages() {
        // Ephemeral-only: remove expired messages from UI
        // (We don't store in repository for ephemeral, so nothing to prune there)
        let now = Date()
        let expiredCount = messages.filter { $0.expiresAt.map { now >= $0 } ?? false }.count
        if expiredCount > 0 {
            Log.debug(.message, "[\(logId)] Pruning \(expiredCount) expired ephemeral messages from UI")
            messages.removeAll { message in
                guard let expiresAt = message.expiresAt else { return false }
                return now >= expiresAt
            }
        }
    }

    var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        currentConversation.canSendMessage(ofLength: messageText.utf8.count)
    }

    // MARK: - Push Notifications

    private func setupPushNotificationHandling() {
        // Capture conversation ID for use in closures (immutable, not actor-isolated)
        let conversationId = conversation.id
        let shortId = String(conversationId.prefix(8))

        // Listen for push notifications
        pushNotificationObserver = NotificationCenter.default.addObserver(
            forName: .pushNotificationReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Check if this notification is for our conversation
            if let targetId = notification.userInfo?["conversation_id"] as? String {
                if targetId == conversationId {
                    Log.info(.push, "[\(shortId)] Push received - refreshing")
                    Task { await self.pollForMessages() }
                }
            } else {
                // General push - refresh anyway
                Log.info(.push, "[\(shortId)] General push received - refreshing")
                Task { await self.pollForMessages() }
            }
        }

        // Listen for device token updates to re-register
        deviceTokenObserver = NotificationCenter.default.addObserver(
            forName: .deviceTokenUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Log.info(.push, "[\(shortId)] Device token updated - re-registering")
            Task { await self.registerForPushNotifications() }
        }
    }

    private func cleanupPushNotificationHandling() {
        pushRegistrationTask?.cancel()
        pushRegistrationTask = nil

        if let observer = pushNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            pushNotificationObserver = nil
        }
        if let observer = deviceTokenObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceTokenObserver = nil
        }
    }

    private func registerForPushNotifications() async {
        guard let relay = conversationRelay else {
            Log.debug(.push, "[\(logId)] No relay configured - skipping push registration")
            return
        }

        // Cancel any pending registration
        pushRegistrationTask?.cancel()

        pushRegistrationTask = Task {
            do {
                try await dependencies.pushNotificationService.registerWithRelay(
                    conversationId: conversation.id,
                    authToken: conversation.authToken,
                    relayService: relay
                )
            } catch PushNotificationError.noDeviceToken {
                // No token yet - will retry when token is received
                Log.debug(.push, "[\(logId)] No device token yet - will register when available")
            } catch {
                Log.error(.push, "[\(logId)] Push registration failed: \(error)")
            }
        }

        await pushRegistrationTask?.value
    }
}
