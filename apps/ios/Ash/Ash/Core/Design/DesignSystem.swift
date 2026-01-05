//
//  DesignSystem.swift
//  Ash
//
//  iOS 26 Design System following Apple Human Interface Guidelines
//

import SwiftUI

// MARK: - Message Limits

/// Message size limits (must match backend configuration)
enum MessageLimits {
    /// Maximum message size in bytes (8KB - matches backend MAX_CIPHERTEXT_SIZE)
    static let maxMessageBytes = 8 * 1024  // 8KB

    /// Maximum message size in kilobytes (for display)
    static let maxMessageKB = 8

    /// Warning threshold (show warning when approaching limit)
    static let warningThresholdBytes = 6 * 1024  // 6KB
}

// MARK: - Spacing (Apple's 8-point grid)

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius (Apple standard radiuses)

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    /// Continuous corner radius matching iOS app icons
    static let continuous: CGFloat = 22
}

// MARK: - Semantic Colors (HIG-compliant)
// Using system colors that automatically adapt to light/dark mode and accessibility settings

extension Color {
    /// Primary app accent color - muted orange (softer than system orange)
    static let ashAccent = Color(red: 0.90, green: 0.55, blue: 0.30)

    /// Destructive actions - uses system red for proper dark mode support
    static let ashDanger = Color(uiColor: .systemRed)

    /// Success states - uses system green for proper dark mode support
    static let ashSuccess = Color(uiColor: .systemGreen)

    /// Warning states - muted amber
    static let ashWarning = Color(red: 0.95, green: 0.65, blue: 0.25)

    /// Secure/encrypted indicator - uses accent color for consistency
    static let ashSecure = Color(red: 0.90, green: 0.55, blue: 0.30)
}

// MARK: - Conversation Colors

/// Preset colors for conversations (user selectable)
enum ConversationColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case orange     // Default - muted orange matching app accent
    case blue
    case purple
    case pink
    case green
    case teal       // Available for conversations only
    case indigo
    case mint
    case cyan
    case brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return Color(red: 0.90, green: 0.55, blue: 0.30)  // Muted orange
        case .blue: return Color(uiColor: .systemBlue)
        case .purple: return Color(uiColor: .systemPurple)
        case .pink: return Color(uiColor: .systemPink)
        case .green: return Color(uiColor: .systemGreen)
        case .teal: return Color(uiColor: .systemTeal)
        case .indigo: return Color(uiColor: .systemIndigo)
        case .mint: return Color(uiColor: .systemMint)
        case .cyan: return Color(uiColor: .systemCyan)
        case .brown: return Color(uiColor: .systemBrown)
        }
    }

    var name: String {
        switch self {
        case .orange: return "Orange"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .green: return "Green"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .mint: return "Mint"
        case .cyan: return "Cyan"
        case .brown: return "Brown"
        }
    }
}

// MARK: - Typography

extension Font {
    static let ashLargeTitle = Font.largeTitle.weight(.bold)
    static let ashTitle = Font.title.weight(.bold)
    static let ashTitle2 = Font.title2.weight(.semibold)
    static let ashTitle3 = Font.title3.weight(.semibold)
    static let ashHeadline = Font.headline
    static let ashBody = Font.body
    static let ashCallout = Font.callout
    static let ashSubheadline = Font.subheadline
    static let ashFootnote = Font.footnote
    static let ashCaption = Font.caption
    static let ashMono = Font.system(.body, design: .monospaced).weight(.medium)
}
