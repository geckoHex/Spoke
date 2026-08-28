# Spoke — Project Instructions

Spoke is a premium cycling app. It should feel Apple-designed: polished, minimal, native, restrained, and highly refined.

## Design Instructions

Use a pure black background with white text and icons. For buttons, use white buttons with black content. 
Use system blue only for native accent states, toggles, system components. 
Always design in dark mode.

Prefer SwiftUI, SF Symbols, system typography (SF Pro), native controls, and standard iOS patterns. 
**Only add explicitly requested UI or behavior.**

Inputs: show a visible text label above and outside every field's editable row or container. Use the regular native text/number field style beneath it, keep entered text left-aligned, and do not put labels or placeholder copy inside the field. A trailing `xmark.circle.fill` clears input, and only appears while its field is active.

Use the correct keyboard for each input. The keyboard's own `Done` key and an outside tap should dismiss it; never add a `Done` button or any other button in a toolbar/accessory above the keyboard.

## Coding Instructions

Use local SwiftData persistence, following the existing architecture.

When the user tells you to use an asset not bundled with the app, copy the asset to where it belongs in the app.

For all app audio, use AVAudioSession to interrupt other system audio while playback is active.
When app audio finishes, deactivate the session with .notifyOthersOnDeactivation so interrupted audio can resume.

Do not launch the app or simulator. Build checks and git inspection are allowed. Make only requested changes; do not commit it.

Finish with exactly one single-line suggested commit message.
