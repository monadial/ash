//
//  LockScreen.swift
//  Ash
//
//  Biometric lock screen
//

import SwiftUI

struct LockScreen: View {
    @Bindable var viewModel: AppLockViewModel
    @State private var showContent = false
    @State private var hasAttemptedAutoAuth = false

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App logo
                AppLogo(size: .large, showTitle: true)
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.9)

                Spacer()
                    .frame(height: Spacing.xxl)

                // Lock status
                VStack(spacing: Spacing.lg) {
                    // Status text
                    Text("App Locked")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    // Biometric unlock button
                    unlockButton
                        .padding(.horizontal, Spacing.lg)

                    // Error message
                    if let error = viewModel.authenticationError {
                        errorMessage(error)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 16)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.authenticationError)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }

            // Auto-authenticate on first appear only if biometrics available
            if !hasAttemptedAutoAuth && viewModel.canUseBiometrics {
                hasAttemptedAutoAuth = true
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await viewModel.unlock()
                }
            }
        }
    }

    private var unlockButton: some View {
        Button {
            Task {
                await viewModel.unlock()
            }
        } label: {
            HStack(spacing: Spacing.md) {
                // Biometric icon
                ZStack {
                    Circle()
                        .fill(Color.ashSecure.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(systemName: viewModel.biometricType.iconName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.ashSecure)
                        .symbolEffect(.pulse, isActive: viewModel.isAuthenticating)
                }

                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isAuthenticating ? "Authenticating..." : "Unlock with \(viewModel.biometricType.displayName)")
                        .font(.headline)
                        .foregroundStyle(Color.primary)

                    Text("Tap to authenticate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.md)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAuthenticating)
    }

    private func errorMessage(_ error: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.ashDanger)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(Color.ashDanger)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.ashDanger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .padding(.horizontal, Spacing.lg)
    }
}

#Preview {
    LockScreen(viewModel: AppLockViewModel())
}
