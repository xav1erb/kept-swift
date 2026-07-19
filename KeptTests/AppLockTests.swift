import SwiftUI
import Testing
import Dependencies
@testable import Kept

/// M0 acceptance §7.5 — the lock state machine, against a faked biometric context.
struct AppLockTests {

    nonisolated struct FakeAuth: AuthenticationContext {
        let succeeds: Bool
        func biometricsAvailable() -> Bool { true }
        func authenticate(reason: String) async throws -> Bool { succeeds }
    }

    @Test func disabledByDefault() {
        let model = AppLockModel()
        #expect(model.state == .disabled)
    }

    @Test func enabledLocksOnColdStart() {
        let model = AppLockModel(isEnabled: true)
        #expect(model.state == .locked)
    }

    @Test func successfulAuthenticationUnlocks() async {
        let model = withDependencies {
            $0.authenticationContext = FakeAuth(succeeds: true)
        } operation: {
            AppLockModel(isEnabled: true)
        }
        await model.unlock()
        #expect(model.state == .unlocked)
    }

    @Test func failedAuthenticationStaysLocked() async {
        let model = withDependencies {
            $0.authenticationContext = FakeAuth(succeeds: false)
        } operation: {
            AppLockModel(isEnabled: true)
        }
        await model.unlock()
        #expect(model.state == .locked)
    }

    @Test func backgroundReturnRelocksWhenEnabled() async {
        let model = withDependencies {
            $0.authenticationContext = FakeAuth(succeeds: true)
        } operation: {
            AppLockModel(isEnabled: true)
        }
        await model.unlock()
        #expect(model.state == .unlocked)
        model.handleScenePhase(.background)
        #expect(model.state == .locked)
    }

    @Test func backgroundDoesNothingWhenDisabled() {
        let model = AppLockModel()
        model.handleScenePhase(.background)
        #expect(model.state == .disabled)
    }

    @Test func togglingOnMidSessionLeavesUnlocked() {
        let model = AppLockModel()
        model.setEnabled(true)
        #expect(model.state == .unlocked)
        model.setEnabled(false)
        #expect(model.state == .disabled)
    }
}
