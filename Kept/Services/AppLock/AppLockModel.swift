import Foundation
import Observation
import SwiftUI
import Dependencies
import LocalAuthentication

/// The biometric seam, faked in tests (C9 spirit — you cannot unit-test Face ID).
/// nonisolated: dependency plumbing must stay off the main actor for Sendable key paths.
nonisolated protocol AuthenticationContext: Sendable {
    func biometricsAvailable() -> Bool
    func authenticate(reason: String) async throws -> Bool
}

nonisolated struct LiveAuthenticationContext: AuthenticationContext {
    func biometricsAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticate(reason: String) async throws -> Bool {
        try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

private nonisolated enum AuthenticationContextKey: DependencyKey {
    static let liveValue: any AuthenticationContext = LiveAuthenticationContext()
}

extension DependencyValues {
    nonisolated var authenticationContext: any AuthenticationContext {
        get { self[AuthenticationContextKey.self] }
        set { self[AuthenticationContextKey.self] = newValue }
    }
}

/// App-lock scaffold (M0). Locks on cold start and on background return when enabled; the real
/// Face ID onboarding screen and device-verify belong to M2 (onboarding 4.10).
@Observable
final class AppLockModel {
    enum LockState: Equatable {
        case disabled, locked, unlocked
    }

    private(set) var isEnabled: Bool
    private(set) var state: LockState

    @ObservationIgnored
    @Dependency(\.authenticationContext) private var auth

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
        self.state = isEnabled ? .locked : .disabled   // cold start: enabled means locked
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        state = enabled ? .unlocked : .disabled   // toggled from inside an unlocked session
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled, phase == .background else { return }
        state = .locked
    }

    func unlock() async {
        guard state == .locked else { return }
        let success = (try? await auth.authenticate(reason: "Only your face opens your world.")) ?? false
        if success {
            state = .unlocked
        }
    }
}
