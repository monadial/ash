//
//  CeremonyScreen.swift
//  Ash
//
//  Create new conversation ceremony flow
//  Supports automatic dark/light mode
//

import SwiftUI

struct CeremonyScreen: View {
    @Bindable var viewModel: CeremonyViewModel
    let onComplete: (Conversation) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .selectingRole:
                    RoleSelectionView(viewModel: viewModel)

                case .selectingPadSize:
                    if let initiator = viewModel.initiatorViewModel {
                        PadSizeView(viewModel: initiator)
                    }

                case .configuringOptions:
                    if let initiator = viewModel.initiatorViewModel {
                        OptionsView(viewModel: initiator)
                    }

                case .confirmingConsent:
                    if let initiator = viewModel.initiatorViewModel {
                        ConsentView(viewModel: initiator)
                    }

                case .collectingEntropy:
                    if let initiator = viewModel.initiatorViewModel {
                        EntropyView(viewModel: initiator)
                    }

                case .generatingPad:
                    GeneratingView(title: "Generating Pad", subtitle: "Creating secure encryption key...", current: 0, total: 0)

                case .generatingQRCodes(let progress, let total):
                    GeneratingView(title: "Generating QR Codes", subtitle: "Preparing \(total) frames for transfer...", current: Int(progress * Double(total)), total: total)

                case .configuringReceiver:
                    if let receiver = viewModel.receiverViewModel {
                        ReceiverSetupView(viewModel: receiver)
                    }

                case .transferring(let current, let total):
                    if let initiator = viewModel.initiatorViewModel {
                        QRDisplayView(viewModel: initiator, currentFrame: current, totalFrames: total)
                    } else if let receiver = viewModel.receiverViewModel {
                        QRScanView(viewModel: receiver)
                    }

                case .verifying(let mnemonic):
                    if let initiator = viewModel.initiatorViewModel {
                        VerificationView(
                            mnemonic: mnemonic,
                            conversationName: Binding(get: { initiator.conversationName }, set: { initiator.conversationName = $0 }),
                            onConfirm: { Task { if let c = await initiator.confirmVerification() { onComplete(c) } } },
                            onReject: { initiator.rejectVerification() }
                        )
                    } else if let receiver = viewModel.receiverViewModel {
                        VerificationView(
                            mnemonic: mnemonic,
                            conversationName: Binding(get: { receiver.conversationName }, set: { receiver.conversationName = $0 }),
                            onConfirm: { Task { if let c = await receiver.confirmVerification() { onComplete(c) } } },
                            onReject: { receiver.rejectVerification() }
                        )
                    }

                case .completed(let conversation):
                    CompletedView(conversation: conversation, onContinue: { onComplete(conversation) })

                case .failed(let error):
                    FailedView(error: error, onRetry: { viewModel.reset(); viewModel.start() }, onCancel: onCancel)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel(); onCancel() }
                }
            }
            .interactiveDismissDisabled(viewModel.isInProgress)
        }
        .onAppear { viewModel.start() }
    }
}

// MARK: - Role Selection

private struct RoleSelectionView: View {
    @Bindable var viewModel: CeremonyViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Choose Role")
                    .font(.title2.bold())
                Text("One device creates, the other joins")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { viewModel.selectRole(.sender) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "qrcode")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create").font(.headline)
                            Text("Generate and display QR codes").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button { viewModel.selectRole(.receiver) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join").font(.headline)
                            Text("Scan QR codes from other device").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Pad Size Selection

private struct PadSizeView: View {
    @Bindable var viewModel: InitiatorCeremonyViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with layers icon
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 56, height: 36)
                            .offset(y: 16)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 56, height: 36)
                            .offset(y: 8)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                            .frame(width: 56, height: 36)
                    }
                    .frame(height: 60)

                    Text("Pad Size")
                        .font(.title2.bold())

                    Text("Larger pads allow more messages but take longer to transfer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
                .padding(.horizontal, 20)

                // Pad Size Cards
                VStack(spacing: 12) {
                    ForEach(PadSize.allCases) { size in
                        PadSizeCard(
                            name: size.displayName,
                            description: "~\(size.estimatedMessages) messages, ~\(size.approximateFrames) QR frames",
                            isSelected: viewModel.selectedPadSize == size
                        ) {
                            viewModel.selectPadSize(size)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Continue Button
                Button {
                    viewModel.proceedToOptions()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct PadSizeCard: View {
    let name: String
    let description: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color(.systemGray3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Options

private struct OptionsView: View {
    @Bindable var viewModel: InitiatorCeremonyViewModel

    private var canProceed: Bool {
        let passphraseOK = !viewModel.isPassphraseEnabled || viewModel.isPassphraseValid
        return passphraseOK && viewModel.isRelayURLValid
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text("Settings")
                        .font(.title2.bold())

                    Text("Configure message handling")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unread Timeout")
                                .font(.subheadline)
                            Text("How long unread messages wait")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $viewModel.serverRetention) {
                            ForEach(MessageRetention.allCases, id: \.self) { Text($0.displayName) }
                        }
                        .labelsHidden()
                    }
                    .padding(16)

                    Divider().padding(.leading, 16)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Disappearing Messages")
                                .font(.subheadline)
                            Text("Messages disappear after viewing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $viewModel.disappearingMessages) {
                            ForEach(DisappearingMessages.allCases, id: \.self) { Text($0.displayName) }
                        }
                        .labelsHidden()
                    }
                    .padding(16)

                    Divider().padding(.leading, 16)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Passphrase Protection")
                                    .font(.subheadline)
                                Text("Encrypt QR codes with shared secret")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.isPassphraseEnabled)
                                .labelsHidden()
                        }

                        if viewModel.isPassphraseEnabled {
                            SecureField("Enter passphrase", text: $viewModel.passphrase)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(16)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                // Relay Server Section
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Relay Server")
                                    .font(.subheadline)
                                Text("Server for message delivery")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        TextField("Relay URL", text: $viewModel.selectedRelayURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .font(.footnote.monospaced())
                            .onChange(of: viewModel.selectedRelayURL) { _, _ in
                                viewModel.clearConnectionTest()
                            }

                        // Test Connection Button
                        Button {
                            Task { await viewModel.testRelayConnection() }
                        } label: {
                            HStack {
                                Text("Test Connection")
                                    .font(.subheadline)
                                Spacer()
                                if viewModel.isTestingConnection {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if let result = viewModel.connectionTestResult {
                                    switch result {
                                    case .success(let version):
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text(version)
                                        }
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    case .failure:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(viewModel.isTestingConnection || !viewModel.isRelayURLValid)
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Button {
                    viewModel.proceedToConsent()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canProceed)
                .opacity(canProceed ? 1 : 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Security Verification (Consent)

private struct ConsentView: View {
    @Bindable var viewModel: InitiatorCeremonyViewModel
    @State private var showEthicsGuidelines = false

    private var completedCount: Int {
        [viewModel.consent.environmentConfirmed, viewModel.consent.notUnderSurveillance,
         viewModel.consent.ethicsUnderstood, viewModel.consent.keyLossUnderstood,
         viewModel.consent.relayWarningUnderstood].filter { $0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Security Verification")
                        .font(.title2.bold())
                    Text("Confirm before proceeding")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < completedCount ? Color.accentColor : Color(.systemGray5))
                            .frame(height: 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    ConsentRow(isChecked: $viewModel.consent.environmentConfirmed,
                        title: "I confirm no one is watching my screen",
                        subtitle: "Ensure you have visual privacy - no cameras, mirrors, or people who can see your display")

                    Divider().padding(.leading, 56)

                    ConsentRow(isChecked: $viewModel.consent.notUnderSurveillance,
                        title: "I am not under surveillance or coercion",
                        subtitle: "Do not proceed if you are being forced or monitored by others")

                    Divider().padding(.leading, 56)

                    ConsentRow(isChecked: $viewModel.consent.ethicsUnderstood,
                        title: "I understand the ethical responsibilities",
                        subtitle: "This tool is for legitimate private communication only")

                    Divider().padding(.leading, 56)

                    ConsentRow(isChecked: $viewModel.consent.keyLossUnderstood,
                        title: "I understand this creates unrecoverable keys",
                        subtitle: "If you lose access, messages cannot be recovered - there is no backup")

                    Divider().padding(.leading, 56)

                    ConsentRow(isChecked: $viewModel.consent.relayWarningUnderstood,
                        title: "I understand relay limitations",
                        subtitle: "If the relay server is unavailable, you may not receive messages or notifications until connectivity is restored")
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                Button { showEthicsGuidelines = true } label: {
                    Label("Read Ethics Guidelines", systemImage: "doc.text")
                        .font(.subheadline)
                }
                .padding(.top, 20)

                Button {
                    viewModel.confirmConsent()
                } label: {
                    HStack {
                        if viewModel.isConsentComplete {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("I Understand & Proceed")
                    }
                    .font(.headline)
                    .foregroundStyle(viewModel.isConsentComplete ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(viewModel.isConsentComplete ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    )
                }
                .disabled(!viewModel.isConsentComplete)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showEthicsGuidelines) {
            EthicsGuidelinesSheet()
        }
    }
}

private struct ConsentRow: View {
    @Binding var isChecked: Bool
    let title: String
    let subtitle: String

    var body: some View {
        Button { isChecked.toggle() } label: {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 28, height: 28)
                    if isChecked {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ethics Guidelines Sheet

private struct EthicsGuidelinesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("ASH is designed for legitimate private communication.\nBy using this application, you agree to:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(spacing: 0) {
                        GuidelineRow(number: 1, title: "Respect Privacy", description: "Use this tool only for communications where both parties consent and have a legitimate need for privacy.")
                        Divider().padding(.leading, 56)
                        GuidelineRow(number: 2, title: "No Harmful Use", description: "Do not use ASH to plan, coordinate, or facilitate illegal activities, harassment, or harm to others.")
                        Divider().padding(.leading, 56)
                        GuidelineRow(number: 3, title: "Honest Communication", description: "Be truthful with your communication partners about the nature and purpose of your conversations.")
                        Divider().padding(.leading, 56)
                        GuidelineRow(number: 4, title: "Accept Responsibility", description: "You are solely responsible for the content of your messages and how you use this tool.")
                        Divider().padding(.leading, 56)
                        GuidelineRow(number: 5, title: "Understand Limitations", description: "ASH provides technical privacy but cannot protect against physical surveillance, compromised devices, or coerced disclosure.")
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    Text("ASH was created to protect legitimate privacy needs such as journalist-source communication, whistleblowing, personal privacy, and human rights work. Misuse undermines these important purposes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Ethics Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct GuidelineRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 28, height: 28)
                Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Entropy Collection

private struct EntropyView: View {
    @Bindable var viewModel: InitiatorCeremonyViewModel
    @State private var points: [CGPoint] = []
    @State private var segments: [[CGPoint]] = []

    private var progressPercent: Int {
        Int(viewModel.entropyProgress * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Generate Entropy")
                    .font(.title2.bold())
                Text("Draw random patterns anywhere on screen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)

            GeometryReader { _ in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))

                    Canvas { ctx, _ in
                        for seg in segments { drawPath(ctx: ctx, pts: seg) }
                        drawPath(ctx: ctx, pts: points)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            points.append(v.location)
                            if points.count > 300 { points.removeFirst(50) }
                            viewModel.addEntropy(from: v.location)
                        }
                        .onEnded { _ in
                            if points.count > 1 { segments.append(points); if segments.count > 10 { segments.removeFirst() } }
                            points = []
                        }
                )
            }
            .padding(.horizontal, 20)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 4)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: viewModel.entropyProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                    Text("\(progressPercent)")
                        .font(.subheadline.bold().monospacedDigit())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.entropyProgress >= 1.0 ? "Complete!" : "Keep drawing...")
                        .font(.subheadline.weight(.medium))
                    Text("Random patterns increase security")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    private func drawPath(ctx: GraphicsContext, pts: [CGPoint]) {
        guard pts.count > 1 else { return }
        var path = Path(); path.move(to: pts[0])
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i-1].x + pts[i].x) / 2, y: (pts[i-1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i-1])
        }
        if let last = pts.last { path.addLine(to: last) }
        ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

// MARK: - Generating

private struct GeneratingView: View {
    let title: String
    let subtitle: String
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 8)
                    .frame(width: 140, height: 140)

                if total > 0 {
                    Circle()
                        .trim(from: 0, to: Double(current) / Double(total))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(current)")
                            .font(.system(size: 36, weight: .bold).monospacedDigit())
                        Text("of \(total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Receiver Setup

private struct ReceiverSetupView: View {
    @Bindable var viewModel: ReceiverCeremonyViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Ready to Scan")
                        .font(.title2.bold())
                    Text("Configure settings before scanning")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Passphrase Protected")
                                .font(.subheadline.weight(.medium))
                            Text("Enable if sender used passphrase")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.isPassphraseEnabled)
                            .labelsHidden()
                    }
                    .padding(16)

                    if viewModel.isPassphraseEnabled {
                        Divider()
                        SecureField("Enter passphrase", text: $viewModel.passphrase)
                            .textContentType(.password)
                            .padding(16)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                Button { viewModel.startScanning() } label: {
                    Label("Start Scanning", systemImage: "camera.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(viewModel.isPassphraseEnabled && !viewModel.isPassphraseValid)
                .opacity(viewModel.isPassphraseEnabled && !viewModel.isPassphraseValid ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - QR Display (Streaming)

private struct QRDisplayView: View {
    @Bindable var viewModel: InitiatorCeremonyViewModel
    let currentFrame: Int
    let totalFrames: Int
    @State private var frame: Int = 0
    @State private var playing = true
    @State private var fps: Double = 4
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Streaming QR Codes")
                    .font(.title2.bold())
                Text("Let the other device scan continuously")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                if frame < viewModel.preGeneratedQRImages.count {
                    Image(uiImage: viewModel.preGeneratedQRImages[frame])
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }
            .frame(width: 380, height: 380)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
                Text("Frame \(frame + 1) of \(totalFrames)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(frame + 1), total: Double(totalFrames))
                .padding(.horizontal, 40)
                .padding(.top, 8)

            Spacer()

            HStack(spacing: 16) {
                Menu {
                    ForEach([2, 4, 6, 8], id: \.self) { r in
                        Button("\(r) fps") { fps = Double(r); if playing { restart() } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                        Text("\(Int(fps)) fps")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .foregroundStyle(.primary)

                Button { playing.toggle(); playing ? start() : stop() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    Button { if frame > 0 { frame -= 1 } } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    Button { if frame < totalFrames - 1 { frame += 1 } } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                }
                .foregroundStyle(.primary)
            }
            .padding(.bottom, 16)

            Button { viewModel.finishSending() } label: {
                Text("Receiver Ready")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        guard totalFrames > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in
            MainActor.assumeIsolated { frame = (frame + 1) % totalFrames }
        }
    }
    private func stop() { timer?.invalidate(); timer = nil }
    private func restart() { stop(); start() }
}

// MARK: - QR Scan

private struct QRScanView: View {
    @Bindable var viewModel: ReceiverCeremonyViewModel

    private var progressPercent: Int {
        Int(viewModel.progress * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Scanning")
                    .font(.title2.bold())
                Text("Point camera at the streaming QR codes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)

            ZStack {
                QRScannerView(onFrameScanned: { viewModel.processScannedFrame($0) }, onError: { _ in })
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: 240, height: 240)
            }
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                if viewModel.sourceBlockCount > 0 {
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 8)
                            .frame(width: 100, height: 100)

                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.2), value: viewModel.progress)

                        Text("\(progressPercent)%")
                            .font(.system(size: 24, weight: .bold).monospacedDigit())
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Waiting for first frame...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// MARK: - Verification

private struct VerificationView: View {
    let mnemonic: [String]
    @Binding var conversationName: String
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Verify Checksum")
                        .font(.title2.bold())
                    Text("Both devices must show the same words")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    ForEach(Array(mnemonic.enumerated()), id: \.offset) { i, word in
                        if i > 0 { Divider().padding(.leading, 48) }
                        HStack {
                            Text("\(i + 1).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            Text(word)
                                .font(.title3.weight(.medium))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversation Name (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Enter a name", text: $conversationName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                VStack(spacing: 12) {
                    Button { onConfirm() } label: {
                        Text("Words Match")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button(role: .destructive) { onReject() } label: {
                        Text("Words Don't Match")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Completed

private struct CompletedView: View {
    let conversation: Conversation
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("Conversation Created")
                        .font(.title2.bold())
                    Text(conversation.displayName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Pad Size").foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(conversation.totalBytes), countStyle: .binary)).fontWeight(.medium)
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("Role").foregroundStyle(.secondary)
                        Spacer()
                        Text(conversation.role == .initiator ? "Creator" : "Joiner").fontWeight(.medium)
                    }
                    .padding(16)
                    if conversation.disappearingMessages.isEnabled {
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Disappearing").foregroundStyle(.secondary)
                            Spacer()
                            Text(conversation.disappearingMessages.displayName).fontWeight(.medium)
                        }
                        .padding(16)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                Button { onContinue() } label: {
                    Text("Start Messaging")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Failed

private struct FailedView: View {
    let error: CeremonyError
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)
            VStack(spacing: 8) {
                Text("Setup Failed")
                    .font(.title2.bold())
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button { onRetry() } label: {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                Button("Cancel") { onCancel() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}
