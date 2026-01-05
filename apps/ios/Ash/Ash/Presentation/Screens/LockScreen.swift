//
//  LockScreen.swift
//  Ash
//
//  Biometric lock screen
//

import SwiftUI
// Liquid Glass redesign applied

struct LockScreen: View {
    @Bindable var viewModel: AppLockViewModel
    @State private var showContent = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            Color.clear
                .glassEffect(.regular)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App logo
                AppLogo(size: .medium, showTitle: true)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                Spacer()

                // Biometric unlock button
                unlockButton
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Error message
                if let error = viewModel.authenticationError {
                    ZStack {
                        Color.clear
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))

                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.ashDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.bottom, Spacing.lg)
                    }
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }

            // Auto-authenticate after brief delay
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await viewModel.unlock()
            }
        }
    }

    private var unlockButton: some View {
        Button {
            Task {
                await viewModel.unlock()
            }
        } label: {
            VStack(spacing: Spacing.md) {
                // Biometric icon
                ZStack {
                    Circle()
                        .fill(Color.ashSecure.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: viewModel.biometricType.iconName)
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.ashSecure)
                        .symbolEffect(.pulse, isActive: viewModel.isAuthenticating)
                }

                // Label
                VStack(spacing: 4) {
                    Text(viewModel.isAuthenticating ? "Authenticating..." : "Tap to Unlock")
                        .font(.headline)
                        .foregroundStyle(Color.primary)

                    Text(viewModel.biometricType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .background(
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: 32))
                }
            )
        }
        .buttonStyle(.glassProminent)
        .disabled(viewModel.isAuthenticating)
    }
}

#Preview {
    LockScreen(viewModel: AppLockViewModel())
}
