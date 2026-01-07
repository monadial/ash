//
//  LoadingScreen.swift
//  Ash
//
//  Loading screen shown during app initialization
//

import SwiftUI

struct LoadingScreen: View {
    @State private var showContent = false

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                AppLogo(size: .large, animated: true)
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.9)

                Spacer()

                // Loading indicator
                ProgressView()
                    .controlSize(.regular)
                    .tint(.secondary)
                    .opacity(showContent ? 1 : 0)
                    .padding(.bottom, Spacing.xxl)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
        }
    }
}

// MARK: - App Logo Component

struct AppLogo: View {
    enum Size {
        case small, medium, large

        var iconSize: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 64
            }
        }

        var ringSize: CGFloat {
            switch self {
            case .small: return 56
            case .medium: return 80
            case .large: return 100
            }
        }

        var titleFont: Font {
            switch self {
            case .small: return .title3.bold()
            case .medium: return .title.bold()
            case .large: return .system(size: 36, weight: .bold, design: .rounded)
            }
        }

        var spacing: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            }
        }
    }

    let size: Size
    var animated: Bool = false
    var showTitle: Bool = true

    @State private var ringProgress: CGFloat = 0
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: size.spacing) {
            // Icon with ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.ashSecure.opacity(0.15), lineWidth: 2)
                    .frame(width: size.ringSize, height: size.ringSize)

                // Animated progress ring
                Circle()
                    .trim(from: 0, to: animated ? ringProgress : 1)
                    .stroke(
                        Color.ashSecure.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: size.ringSize, height: size.ringSize)
                    .rotationEffect(.degrees(-90))

                // Shield icon
                Image(systemName: "shield.fill")
                    .font(.system(size: size.iconSize, weight: .medium))
                    .foregroundStyle(Color.ashSecure)
                    .scaleEffect(animated ? iconScale : 1)
                    .opacity(animated ? iconOpacity : 1)
            }

            if showTitle {
                // App name
                Text("ASH")
                    .font(size.titleFont)
                    .foregroundStyle(Color.primary)
                    .tracking(4)
            }
        }
        .onAppear {
            guard animated else { return }

            withAnimation(.easeOut(duration: 0.5)) {
                iconOpacity = 1
                iconScale = 1
            }

            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                ringProgress = 1
            }
        }
    }
}

#Preview {
    LoadingScreen()
}

#Preview("Dark") {
    LoadingScreen()
        .preferredColorScheme(.dark)
}

