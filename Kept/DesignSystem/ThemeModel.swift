import SwiftUI
import Observation

/// The live theming engine (M0 acceptance: switching `theme` re-skins every token consumer
/// without rebuild). Injected via `.environment(_:)`; views read tokens through it only —
/// no ad-hoc colors outside the token table.
@Observable
final class ThemeModel {
    var theme: Theme

    var tokens: ThemeTokens { theme.tokens }

    init(theme: Theme = .cloudCream) {
        self.theme = theme
    }
}
