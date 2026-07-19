import Foundation
import Observation

/// Pushable destinations (C8). Cases grow per milestone; the mechanism is fixed at M0.
enum Route: Hashable, Sendable {
    case chapter(UUID)
    case streak
}

/// The five-slot bar's tabs. Tell Pom is not a tab — it is the center button (a sheet).
enum KeptTab: String, CaseIterable, Sendable {
    case world, river, wins, you
}

/// One router, one pattern (C8). Every notification deep-links through `open(deepLink:)` —
/// unknown links are refused loudly (return false), never half-routed.
@Observable
final class Router {
    var tab: KeptTab = .world
    var path: [Route] = []
    var isTellPomPresented = false

    /// Supported: kept://world|river|wins|you, kept://tellpom,
    /// kept://chapter/<uuid>, kept://streak
    @discardableResult
    func open(deepLink url: URL) -> Bool {
        guard url.scheme == "kept", let host = url.host() else { return false }
        switch host {
        case "world": select(.world)
        case "river": select(.river)
        case "wins": select(.wins)
        case "you": select(.you)
        case "tellpom":
            isTellPomPresented = true
        case "chapter":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return false }
            select(.world)
            path = [.chapter(id)]
        case "streak":
            select(.world)
            path = [.streak]
        default:
            return false
        }
        return true
    }

    private func select(_ newTab: KeptTab) {
        tab = newTab
        path = []
    }
}
