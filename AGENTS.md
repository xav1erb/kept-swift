<!-- BEGIN:swift-agent-rules -->
# This is NOT the Swift/iOS you know

Your priors on Swift, SwiftUI, and the iOS SDK are likely stale. Read the shipped headers / current
docs for any API you touch before writing code. Heed deprecations. One ≤6-line tripwire per fast-moving
area below — this file is a tripwire, not a manual.
<!-- END:swift-agent-rules -->

## Swift 6 / strict concurrency
Data-race safety is enforced. `Sendable`, actor isolation, and `@MainActor` placement differ from older
Swift; Swift 6.2 / Xcode 26 changed default actor isolation ("approachable concurrency"). Don't assume
the old free-threaded model. Annotate models for isolation deliberately; read current concurrency docs.

## SwiftUI Observation
`@Observable` (Observation framework) replaced `ObservableObject` / `@Published` / `@StateObject`.
Write the new pattern: `@Observable final class Model`, `@State private var model = Model()`,
`@Bindable` for two-way bindings. Do not reach for the old `ObservableObject` stack.

## SwiftData
`@Model`, `ModelContainer`, `ModelContext` — young framework, sharp edges: migration paths, predicate
limits (`#Predicate` cannot express everything), CloudKit-sync constraints (no unique constraints, all
relationships optional), and file-protection interaction. Verify each capability against current docs
before relying on it; the store design is a human-owned seam here.

## Speech / on-device STT (the vent composer)
On-device `SFSpeechRecognizer` requires `requiresOnDeviceRecognition = true` and runtime checks for
locale + `supportsOnDeviceRecognition`; availability is locale- and device-gated. AVAudioSession
config and mic permission flows have moved. Read current headers — never assume an API from memory.

## LocalAuthentication / alternate icons / file protection
Face ID via `LAContext` (app-lock on cold start + background return); disguise icons via
`setAlternateIconName` (must be declared in the target; async, can fail); encrypted-at-rest via
`NSFileProtectionComplete` + Keychain/Secure Enclave keys. Each has entitlement/plist requirements —
verify against current docs, don't guess.

## StoreKit 2 / UserNotifications
StoreKit 2 only (`Product`, `Transaction.currentEntitlements`); live prices from the store, never
hardcoded. Notifications: pre-permission pattern (our screen first, system prompt on yes);
provisional/quiet-hours logic is ours, not the OS's. APIs move — check current signatures.

## Build discipline
One toolchain (Xcode/xcodebuild). The archive builds the **working tree**, not committed HEAD.
**Bump the build number every archive**, and verify the binary under test actually contains your change
before claiming a device feature works.
