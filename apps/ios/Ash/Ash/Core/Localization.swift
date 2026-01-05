//
//  Localization.swift
//  Ash
//
//  Core Layer - Localization helpers
//

import Foundation
import SwiftUI

// MARK: - String Extension

extension String {
    /// Returns a localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns a localized version with format arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: localized, arguments: args)
    }
}

// MARK: - Localized String Keys

/// Centralized localization keys for type-safe access
enum L10n {
    // MARK: - Common
    enum Common {
        static let cancel = "common.cancel".localized
        static let save = "common.save".localized
        static let done = "common.done".localized
        static let `continue` = "common.continue".localized
        static let back = "common.back".localized
        static let delete = "common.delete".localized
        static let settings = "common.settings".localized
        static let rename = "common.rename".localized
        static let error = "common.error".localized
        static let ok = "common.ok".localized
    }

    // MARK: - Conversations
    enum Conversations {
        static let title = "conversations.title".localized
        static let emptyTitle = "conversations.empty.title".localized
        static let emptyMessage = "conversations.empty.message".localized
        static let emptyAction = "conversations.empty.action".localized
        static let new = "conversations.new".localized
        static let burn = "conversations.burn".localized
        static let burnTitle = "conversations.burn.title".localized
        static let burnMessage = "conversations.burn.message".localized
        static func remaining(_ amount: String) -> String {
            "conversations.remaining".localized(amount)
        }
    }

    // MARK: - Messaging
    enum Messaging {
        static let emptyTitle = "messaging.empty.title".localized
        static let emptyMessage = "messaging.empty.message".localized
        static let inputPlaceholder = "messaging.input.placeholder".localized
        static let send = "messaging.send".localized
        static let peerBurned = "messaging.peer.burned".localized
        static let location = "messaging.location".localized
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.conversation.title".localized
        static let relay = "settings.relay".localized
        static let relayUrl = "settings.relay.url".localized
        static let relayTest = "settings.relay.test".localized
        static func relayConnected(_ version: String) -> String {
            "settings.relay.connected".localized(version)
        }
        static let persistence = "settings.persistence".localized
        static let delayedReading = "settings.persistence.delayed".localized
        static let delayedDescription = "settings.persistence.delayed.description".localized
        static let delayedFooterOn = "settings.persistence.delayed.footer.on".localized
        static let delayedFooterOff = "settings.persistence.delayed.footer.off".localized
    }

    // MARK: - Rename
    enum Rename {
        static let title = "rename.title".localized
        static let placeholder = "rename.placeholder".localized
        static let message = "rename.message".localized
    }

    // MARK: - Ceremony
    enum Ceremony {
        static let title = "ceremony.title".localized

        enum Role {
            static let title = "ceremony.role.title".localized
            static let subtitle = "ceremony.role.subtitle".localized
            static let initiate = "ceremony.role.initiate".localized
            static let initiateDescription = "ceremony.role.initiate.description".localized
            static let receive = "ceremony.role.receive".localized
            static let receiveDescription = "ceremony.role.receive.description".localized
        }

        enum PadSize {
            static let title = "ceremony.padsize.title".localized
            static let subtitle = "ceremony.padsize.subtitle".localized
        }

        enum Passphrase {
            static let title = "ceremony.passphrase.title".localized
            static let toggle = "ceremony.passphrase.toggle".localized
            static let toggleDescription = "ceremony.passphrase.toggle.description".localized
            static let placeholder = "ceremony.passphrase.placeholder".localized
            static let valid = "ceremony.passphrase.valid".localized
            static let invalid = "ceremony.passphrase.invalid".localized
            static let hint = "ceremony.passphrase.hint".localized
            static let receiverToggle = "ceremony.passphrase.receiver.toggle".localized
            static let receiverHint = "ceremony.passphrase.receiver.hint".localized
        }

        enum Consent {
            static let title = "ceremony.consent.title".localized
            static let subtitle = "ceremony.consent.subtitle".localized
            static let environment = "ceremony.consent.environment".localized
            static let environmentDetail = "ceremony.consent.environment.detail".localized
            static let surveillance = "ceremony.consent.surveillance".localized
            static let surveillanceDetail = "ceremony.consent.surveillance.detail".localized
            static let ethics = "ceremony.consent.ethics".localized
            static let ethicsDetail = "ceremony.consent.ethics.detail".localized
            static let understand = "ceremony.consent.understand".localized
            static let understandDetail = "ceremony.consent.understand.detail".localized
            static let relayWarning = "ceremony.consent.relay_warning".localized
            static let relayWarningDetail = "ceremony.consent.relay_warning.detail".localized
            static let proceed = "ceremony.consent.proceed".localized
            static let ethicsLink = "ceremony.consent.ethics.link".localized
        }

        enum Entropy {
            static let title = "ceremony.entropy.title".localized
            static let subtitle = "ceremony.entropy.subtitle".localized
            static let hint = "ceremony.entropy.hint".localized
            static let progress = "ceremony.entropy.progress".localized
            static let progressHint = "ceremony.entropy.progress.hint".localized
            static let complete = "ceremony.entropy.complete".localized
            static let completeHint = "ceremony.entropy.complete.hint".localized
        }

        enum Generating {
            static let pad = "ceremony.generating.pad".localized
            static let qr = "ceremony.generating.qr".localized
            static func qrSubtitle(_ frames: Int) -> String {
                "ceremony.generating.qr.subtitle".localized(frames)
            }
        }

        enum Transfer {
            enum Sender {
                static let title = "ceremony.transfer.sender.title".localized
                static let subtitle = "ceremony.transfer.sender.subtitle".localized
                static func frame(_ current: Int, _ total: Int) -> String {
                    "ceremony.transfer.sender.frame".localized(current, total)
                }
                static func fps(_ rate: Int) -> String {
                    "ceremony.transfer.sender.fps".localized(rate)
                }
                static let ready = "ceremony.transfer.sender.ready".localized
            }

            enum Receiver {
                static let title = "ceremony.transfer.receiver.title".localized
                static let subtitle = "ceremony.transfer.receiver.subtitle".localized
                static let waiting = "ceremony.transfer.receiver.waiting".localized
                static let scanning = "ceremony.transfer.receiver.scanning".localized
                static let complete = "ceremony.transfer.receiver.complete".localized
            }
        }

        enum Verify {
            static let title = "ceremony.verify.title".localized
            static let subtitle = "ceremony.verify.subtitle".localized
            static let nameTitle = "ceremony.verify.name.title".localized
            static let namePlaceholder = "ceremony.verify.name.placeholder".localized
            static let nameHint = "ceremony.verify.name.hint".localized
            static let match = "ceremony.verify.match".localized
            static let noMatch = "ceremony.verify.nomatch".localized
        }

        enum Complete {
            static let title = "ceremony.complete.title".localized
            static let subtitle = "ceremony.complete.subtitle".localized
            static let action = "ceremony.complete.action".localized
        }

        enum Failed {
            static let title = "ceremony.failed.title".localized
            static let retry = "ceremony.failed.retry".localized
        }
    }

    // MARK: - Ethics
    enum Ethics {
        static let title = "ethics.title".localized
        static let intro = "ethics.intro".localized
        static let footer = "ethics.footer".localized

        enum Principle1 {
            static let title = "ethics.principle.1.title".localized
            static let detail = "ethics.principle.1.detail".localized
        }
        enum Principle2 {
            static let title = "ethics.principle.2.title".localized
            static let detail = "ethics.principle.2.detail".localized
        }
        enum Principle3 {
            static let title = "ethics.principle.3.title".localized
            static let detail = "ethics.principle.3.detail".localized
        }
        enum Principle4 {
            static let title = "ethics.principle.4.title".localized
            static let detail = "ethics.principle.4.detail".localized
        }
        enum Principle5 {
            static let title = "ethics.principle.5.title".localized
            static let detail = "ethics.principle.5.detail".localized
        }
    }

    // MARK: - Errors
    enum Error {
        static let insufficientPad = "error.insufficient_pad".localized
        static let decryptionFailed = "error.decryption_failed".localized
        static let invalidUrl = "error.invalid_url".localized
        static let connectionFailed = "error.connection_failed".localized
        static let serverError = "error.server_error".localized
        static let noConnection = "error.no_connection".localized
        static let relayError = "error.relay_error".localized
        static let messageTooLarge = "error.message_too_large".localized
        static func messageTooLargeDetail(_ maxKB: Int, _ currentKB: Int) -> String {
            "error.message_too_large.detail".localized(maxKB, currentKB)
        }
    }

    // MARK: - Delivery Status
    enum Delivery {
        static let sending = "delivery.sending".localized
        static let sent = "delivery.sent".localized
        static let failed = "delivery.failed".localized
        static let tapToRetry = "delivery.tap_to_retry".localized
    }
}
