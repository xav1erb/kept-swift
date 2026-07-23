# GlobeKit — walled module (C9)

The 2.5D orbit engine: pin math (sin/cos orbit), drag, idle spin, depth scale/opacity/z-order.
Typed input only (chapters + states + awareness) and **store-blind** — nothing in here may import
`Services/Store`. The whitepaper's "SceneKit later, only if needed" swap happens behind this wall
or not at all.

Built at **M3** (`GlobeKit.swift`). Orbit math is verified against golden values (loop-safe per
LOOP.md: no `Date.now`, no randomness — `layout()` is a pure function of `rotation`). The wall is
enforced by a source-scan never-test (M3-CONTRACTS §8 A3), not convention: no file here may
import SwiftData or reference `Services/Store`/`KeptStore` symbols. The World feature owns the
`ChapterSummary → GlobePin` mapping — never the other way around. If GlobeKit ever graduates to
its own module target, the scan upgrades to a real target-boundary assertion.
