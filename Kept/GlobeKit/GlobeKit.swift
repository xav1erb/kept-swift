import Observation
import SwiftUI

// GlobeKit — the walled 2.5D orbit engine (C9, M3-CONTRACTS §2). Blind to the app's data layer
// BY CONSTRUCTION: a source-scan never-test forbids store imports and store symbols anywhere in
// this directory (§8 A3), so keep even these comments free of them. Inputs are GlobeKit's own
// value types; colors arrive pre-resolved from the host so the engine never reaches into app
// state. The math is pure and deterministic (LOOP.md: no Date.now, no randomness) —
// golden-value tested.

/// One pin as the host hands it over. `id` is opaque to GlobeKit (used only for tap-out);
/// every field is display-ready — the engine places, the host draws.
nonisolated struct GlobePin: Identifiable, Equatable, Sendable {
    let id: UUID
    let iconRef: String
    /// 0–100, already computed & stored by the host's engines (C6) — GlobeKit never recomputes.
    let awarenessPct: Int
    /// Grade→color already resolved by the host; the engine just draws it.
    let ringColor: Color
    /// "fully aware · 100%" — host-built copy; the engine lays it out.
    let sublineText: String
    /// Live chapter status ("talk tonight"); nil = none.
    let statusLine: String?
    /// Stable longitude on the sphere (host-assigned, deterministic).
    let lon: Double
}

nonisolated struct GlobeConfig: Equatable, Sendable {
    var radius: CGFloat = 140
    /// Whitepaper §5: back-of-globe pins shrink to 0.62×.
    var scaleRange: ClosedRange<CGFloat> = 0.62...1.0
    /// Slow idle auto-rotation (§8 ruling 4: on by default; the host gates on Reduce Motion).
    var idleRadiansPerSecond: Double = 0.06
    var behindBlurMax: CGFloat = 3
    /// Momentum decay: fraction of velocity surviving each second after `settle()`.
    var momentumDecayPerSecond: Double = 0.05
}

/// Pure output of the orbit math for one pin at the current rotation. The layout IS the
/// contract — golden-value tested.
nonisolated struct PinLayout: Identifiable, Equatable, Sendable {
    let id: UUID
    /// sin(lon + rotation) × radius
    let xOffset: CGFloat
    /// lerp over scaleRange by depth = (cos(lon+rotation)+1)/2
    let scale: CGFloat
    /// Depth-driven fade: 0.35 + 0.65 × depth
    let opacity: Double
    /// cos(lon+rotation) — behind-globe pins sink under the sphere.
    let zIndex: Double
    /// Behind pins blur up to behindBlurMax, proportional to how far behind.
    let blur: CGFloat
    let isBehind: Bool
}

@Observable
final class GlobeEngine {

    private(set) var rotation: Double = 0
    /// Radians/second imparted by the last drag, decaying after `settle()`.
    private var momentum: Double = 0
    /// The most recent per-event drag delta (radians) — becomes momentum at `settle()`.
    private var lastDragDelta: Double = 0

    /// Pure function of `rotation` — same pins + same rotation → identical layouts, always.
    func layout(pins: [GlobePin], config: GlobeConfig) -> [PinLayout] {
        pins.map { pin in
            let angle = pin.lon + rotation
            let cosA = cos(angle)
            let depth = (cosA + 1) / 2  // 0 = fully behind … 1 = front center
            let span = config.scaleRange.upperBound - config.scaleRange.lowerBound
            return PinLayout(
                id: pin.id,
                xOffset: CGFloat(sin(angle)) * config.radius,
                scale: config.scaleRange.lowerBound + span * CGFloat(depth),
                opacity: 0.35 + 0.65 * depth,
                zIndex: cosA,
                blur: cosA < 0 ? config.behindBlurMax * CGFloat(-cosA) : 0,
                isBehind: cosA < 0
            )
        }
    }

    /// One pan event: horizontal points → rotation radians (a full radius of drag ≈ 1 rad).
    func drag(deltaX: CGFloat, config: GlobeConfig) {
        let delta = Double(deltaX / config.radius)
        rotation += delta
        lastDragDelta = delta
    }

    /// Drag ended: the last per-event delta becomes momentum (assumes ~60Hz drag events),
    /// decayed by `tick`.
    func settle() {
        momentum = lastDragDelta * 60
        lastDragDelta = 0
    }

    /// Advance time: idle auto-rotation (host gates on Reduce Motion) + momentum decay.
    /// Deterministic for a given dt sequence.
    func tick(dt: TimeInterval, config: GlobeConfig, idle: Bool = true) {
        guard dt > 0 else { return }
        if idle {
            rotation += config.idleRadiansPerSecond * dt
        }
        if abs(momentum) > 0.001 {
            rotation += momentum * dt
            momentum *= pow(config.momentumDecayPerSecond, dt)
        } else {
            momentum = 0
        }
    }

    /// Front-most pin whose x-band contains the point (globe-center coordinates). Behind-globe
    /// pins are under the sphere and never tappable.
    func pinHitTest(at point: CGPoint, layouts: [PinLayout], pinRadius: CGFloat = 30) -> UUID? {
        layouts
            .filter { !$0.isBehind && abs(point.x - $0.xOffset) <= pinRadius * $0.scale }
            .max { $0.zIndex < $1.zIndex }?
            .id
    }
}
