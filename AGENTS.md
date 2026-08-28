# Spoke — Project Instructions

Spoke is a premium cycling app. It should feel Apple-designed: polished, minimal, native, restrained, and highly refined.

* Use a pure black background; use white text/icons; and use white buttons with black content. Use system blue only for native accent states, toggles, system components. Always design in dark mode.
* Prefer SwiftUI, SF Symbols, system typography (SF Pro), native controls, and standard iOS patterns. Add only explicitly requested UI or behavior.
* Inputs: show a visible text label above and outside every field's editable row or container. Use the regular native text/number field style beneath it, keep entered text left-aligned, and do not put labels or placeholder copy inside the field.
* Use the correct keyboard for each input. The keyboard's own `Done` key and an outside tap should dismiss it; never add a `Done` button or any other button in a toolbar/accessory above the keyboard.
* A trailing `xmark.circle.fill` clears input, and only appears while its field is active.
* Use local SwiftData persistence. Follow existing architecture; add no unnecessary dependencies.
* Do not launch the app or simulator. Build checks and git inspection are allowed. Make only requested changes; do not commit.
* Finish with exactly one single-line suggested commit message.
