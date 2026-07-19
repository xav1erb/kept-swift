# GlobeKit — walled module (C9)

The 2.5D orbit engine: pin math (sin/cos orbit), drag, idle spin, depth scale/opacity/z-order.
Typed input only (chapters + states + awareness) and **store-blind** — nothing in here may import
`Services/Store`. The whitepaper's "SceneKit later, only if needed" swap happens behind this wall
or not at all.

Builds at **M3**. Orbit math is verified against golden values (loop-safe per LOOP.md).
