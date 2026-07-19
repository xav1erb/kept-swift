import Testing
@testable import Kept

/// M0 acceptance §7.3 — token engine correctness.
struct ThemeTests {
    @Test func cloudCreamMatchesWhitepaperValues() {
        let palette = Theme.cloudCream.palette
        #expect(palette.ink == "4A3F6B")
        #expect(palette.inkSoft == "8D81AD")
        #expect(palette.rose == "E88BA0")
        #expect(palette.peach == "F2B184")
        #expect(palette.mint == "8FCFAE")
        #expect(palette.gold == "E9C268")
        #expect(palette.lilac == "A893DD")
        #expect(palette.blue == "8EA3D8")
        #expect(palette.cardOpacity == 0.85)
        #expect(!palette.isStub)
    }

    @Test func sixDistinctPalettes() {
        let backgrounds = Set(Theme.allCases.map(\.palette.backgroundTop))
        #expect(backgrounds.count == Theme.allCases.count)
    }

    @Test func onlyCloudCreamIsFinal() {
        for theme in Theme.allCases {
            #expect(theme.palette.isStub == (theme != .cloudCream))
        }
    }

    @Test func allPaletteValuesAreValidHex() {
        let hexChars = Set("0123456789ABCDEF")
        for theme in Theme.allCases {
            for hex in theme.palette.allHex {
                #expect(hex.count == 6, "\(theme): \(hex)")
                #expect(hex.allSatisfy { hexChars.contains($0) }, "\(theme): \(hex)")
            }
        }
    }

    @Test func switchingThemeRepublishesTokens() {
        let model = ThemeModel(theme: .cloudCream)
        let before = model.tokens
        model.theme = .midnight
        #expect(model.tokens != before)
        #expect(model.tokens == Theme.midnight.tokens)
    }
}
