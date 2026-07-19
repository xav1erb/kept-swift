import SwiftUI

/// Fraunces (display, soft serif) + Quicksand (UI) — bundled variable fonts (OFL, licenses in
/// Resources/Fonts). The only place font names appear; no ad-hoc `Font.custom` at call sites.
enum KeptFont {
    static func display(_ size: CGFloat) -> Font {
        .custom("Fraunces", size: size)
    }

    static func ui(_ size: CGFloat) -> Font {
        .custom("Quicksand", size: size)
    }
}
