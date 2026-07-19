# VoiceCapture — walled module (C9)

Hold-to-talk on-device `SFSpeechRecognizer` behind a protocol, **faked in tests** (you cannot
unit-test a live mic). Locale/device availability is runtime-checked; where on-device STT is
unsupported the mic is hidden and the composer is type-only (F9) — **never network STT**, so
"voice never leaves your phone" stays unconditional.

Builds at **M5**. Anything touching the real mic is device-verified on a confirmed build number.
