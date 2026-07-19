import SwiftUI
import Testing
import SnapshotTesting
@testable import Kept

/// Snapshot tests (M0-CONTRACTS §8 ruling #2 — landed at M0, pinned to the greenlight
/// simulator). Stub-palette snapshots will be re-recorded when F7's real palettes arrive.
struct ThemeLabSnapshotTests {

    @MainActor
    private func themeLab(_ theme: Theme) throws -> some View {
        ThemeLabView()
            .environment(ThemeModel(theme: theme))
            .environment(try KeptStore(configuration: .inMemory))
            .background(theme.tokens.backgroundGradient)
            .frame(width: 393, height: 852)
    }

    @Test func themeLabCloudCream() throws {
        assertSnapshot(
            of: try themeLab(.cloudCream),
            as: .image(layout: .fixed(width: 393, height: 852))
        )
    }

    @Test func themeLabMidnight() throws {
        assertSnapshot(
            of: try themeLab(.midnight),
            as: .image(layout: .fixed(width: 393, height: 852))
        )
    }

    @Test func surfacePlaceholderStates() {
        let states: [(String, SurfaceState)] = [
            ("loading", .loading),
            ("empty", .empty(message: "Your world is on its way.")),
            ("error", .error(message: "Something drifted — try again in a moment.")),
        ]
        for (name, state) in states {
            let view = SurfacePlaceholder(title: "your world ✨", state: state)
                .environment(ThemeModel(theme: .cloudCream))
                .background(Theme.cloudCream.tokens.backgroundGradient)
                .frame(width: 393, height: 852)
            assertSnapshot(
                of: view,
                as: .image(layout: .fixed(width: 393, height: 852)),
                named: name
            )
        }
    }
}
