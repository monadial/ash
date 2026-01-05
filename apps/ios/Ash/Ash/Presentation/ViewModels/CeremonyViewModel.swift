//
//  CeremonyViewModel.swift
//  Ash
//
//  Presentation Layer - Ceremony coordinator (manages role selection and delegates to role-specific VMs)
//

import SwiftUI

@MainActor
@Observable
final class CeremonyViewModel {

    private let dependencies: Dependencies

    // MARK: - State

    private(set) var role: CeremonyRole?
    private(set) var initiatorViewModel: InitiatorCeremonyViewModel?
    private(set) var receiverViewModel: ReceiverCeremonyViewModel?

    // MARK: - Initialization

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        Log.debug(.ceremony, "Ceremony coordinator initialized")
    }

    // MARK: - Computed Properties

    /// Current phase based on role selection and sub-view model state
    var phase: CeremonyPhase {
        if role == nil {
            return .selectingRole
        }
        if let initiator = initiatorViewModel {
            return initiator.phase
        }
        if let receiver = receiverViewModel {
            return receiver.phase
        }
        return .selectingRole
    }

    /// Whether the ceremony is in progress (can't be dismissed)
    var isInProgress: Bool {
        switch phase {
        case .idle, .selectingRole, .completed, .failed:
            return false
        default:
            return true
        }
    }

    // MARK: - Role Selection

    func start() {
        Log.info(.ceremony, "Ceremony started - awaiting role selection")
        role = nil
        initiatorViewModel = nil
        receiverViewModel = nil
    }

    func selectRole(_ selectedRole: CeremonyRole) {
        dependencies.hapticService.medium()
        role = selectedRole
        Log.info(.ceremony, "Role selected: \(selectedRole.rawValue)")

        switch selectedRole {
        case .sender:
            initiatorViewModel = InitiatorCeremonyViewModel(dependencies: dependencies)
            receiverViewModel = nil
        case .receiver:
            receiverViewModel = ReceiverCeremonyViewModel(dependencies: dependencies)
            initiatorViewModel = nil
        }
    }

    // MARK: - Reset

    func reset() {
        Log.debug(.ceremony, "Resetting ceremony coordinator")
        role = nil
        initiatorViewModel = nil
        receiverViewModel = nil
    }

    func cancel() {
        Log.info(.ceremony, "Ceremony cancelled")
        initiatorViewModel?.cancel()
        receiverViewModel?.cancel()
    }
}
