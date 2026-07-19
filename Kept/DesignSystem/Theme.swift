import SwiftUI

/// The six user-selectable themes (whitepaper §2.2). Cloud Cream is the only fully specified
/// palette; the other five are STUB placeholders behind the same semantic tokens until the
/// designer's file lands (F7) — no "1:1" claims until then.
nonisolated enum Theme: String, Codable, CaseIterable, Identifiable, Sendable {
    case duskLilac
    case warmCoquette
    case goldenHour
    case darkAcademia
    case cloudCream
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duskLilac: "Dusk Lilac"
        case .warmCoquette: "Warm Coquette"
        case .goldenHour: "Golden Hour"
        case .darkAcademia: "Dark Academia"
        case .cloudCream: "Cloud Cream"
        case .midnight: "Midnight"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .cloudCream:
            // Whitepaper §2.2 exact values. Background gradient endpoints are derived from
            // "light lavender → cream" (no hex given) — swap when F7 specifies them.
            ThemePalette(
                backgroundTop: "E9E4F5", backgroundBottom: "FBF6EC",
                card: "FFFFFF", cardOpacity: 0.85,
                ink: "4A3F6B", inkSoft: "8D81AD",
                rose: "E88BA0", peach: "F2B184", mint: "8FCFAE",
                gold: "E9C268", lilac: "A893DD", blue: "8EA3D8",
                isStub: false
            )
        case .duskLilac:
            ThemePalette(
                backgroundTop: "CFC3E8", backgroundBottom: "EFE9FA",
                card: "FFFFFF", cardOpacity: 0.85,
                ink: "3A2F5C", inkSoft: "7D6FA5",
                rose: "E88BA0", peach: "F2B184", mint: "8FCFAE",
                gold: "E9C268", lilac: "A893DD", blue: "8EA3D8",
                isStub: true
            )
        case .warmCoquette:
            ThemePalette(
                backgroundTop: "F8D7E0", backgroundBottom: "FDF1E8",
                card: "FFFFFF", cardOpacity: 0.85,
                ink: "5C3444", inkSoft: "A5788A",
                rose: "E8809C", peach: "F2B184", mint: "8FCFAE",
                gold: "E9C268", lilac: "A893DD", blue: "8EA3D8",
                isStub: true
            )
        case .goldenHour:
            ThemePalette(
                backgroundTop: "F7DFB8", backgroundBottom: "FDF3E0",
                card: "FFFFFF", cardOpacity: 0.85,
                ink: "5C4425", inkSoft: "A58A64",
                rose: "E88BA0", peach: "F0A868", mint: "8FCFAE",
                gold: "E3B84F", lilac: "A893DD", blue: "8EA3D8",
                isStub: true
            )
        case .darkAcademia:
            ThemePalette(
                backgroundTop: "3B3226", backgroundBottom: "57493A",
                card: "2E2820", cardOpacity: 0.85,
                ink: "EFE6D8", inkSoft: "B8A88F",
                rose: "D98A9C", peach: "E0A878", mint: "8FBFA0",
                gold: "D4AF63", lilac: "A895C8", blue: "8898C0",
                isStub: true
            )
        case .midnight:
            ThemePalette(
                backgroundTop: "1C2237", backgroundBottom: "2C3352",
                card: "252C45", cardOpacity: 0.85,
                ink: "E6E9F5", inkSoft: "9AA3C4",
                rose: "E88BA0", peach: "F2B184", mint: "8FCFAE",
                gold: "E9C268", lilac: "A893DD", blue: "8EA3D8",
                isStub: true
            )
        }
    }

    var tokens: ThemeTokens { ThemeTokens(palette: palette) }
}

/// Raw palette as hex strings — the testable source of truth for token values.
nonisolated struct ThemePalette: Equatable, Sendable {
    let backgroundTop: String
    let backgroundBottom: String
    let card: String
    let cardOpacity: Double
    let ink: String
    let inkSoft: String
    let rose: String
    let peach: String
    let mint: String
    let gold: String
    let lilac: String
    let blue: String
    let isStub: Bool

    var allHex: [String] {
        [backgroundTop, backgroundBottom, card, ink, inkSoft, rose, peach, mint, gold, lilac, blue]
    }
}

/// Semantic color/shape tokens consumed by views. Radius band 18–26pt (whitepaper §2.2);
/// dashed borders = "ongoing / optional / unbuilt".
nonisolated struct ThemeTokens: Equatable {
    let backgroundTop: Color
    let backgroundBottom: Color
    let card: Color
    let cardOpacity: Double
    let ink: Color
    let inkSoft: Color
    let rose: Color
    let peach: Color
    let mint: Color
    let gold: Color
    let lilac: Color
    let blue: Color

    static let radiusSmall: CGFloat = 18
    static let radiusCard: CGFloat = 22
    static let radiusLarge: CGFloat = 26

    init(palette: ThemePalette) {
        backgroundTop = Color(hex: palette.backgroundTop)
        backgroundBottom = Color(hex: palette.backgroundBottom)
        card = Color(hex: palette.card)
        cardOpacity = palette.cardOpacity
        ink = Color(hex: palette.ink)
        inkSoft = Color(hex: palette.inkSoft)
        rose = Color(hex: palette.rose)
        peach = Color(hex: palette.peach)
        mint = Color(hex: palette.mint)
        gold = Color(hex: palette.gold)
        lilac = Color(hex: palette.lilac)
        blue = Color(hex: palette.blue)
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// The weather metaphor (§2.2): every state renders through the soft vocabulary, never numbers.
    func color(for state: ChapterState) -> Color {
        switch state {
        case .warm: mint
        case .fine: gold
        case .quiet: blue
        case .tense: rose
        case .complicated: lilac
        }
    }
}

extension Color {
    /// Hex without leading '#', RRGGBB.
    nonisolated init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
