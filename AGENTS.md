# Spoke — Project Instructions

Spoke is a premium cycling app. It should feel Apple-designed: polished, minimal, native, restrained, and highly refined.

## Design Instructions

Preserve the current dark theme in `Spoke/SpokeControlStyles.swift`: black backgrounds, neutral raised surfaces, white text and icons, and bold system headings.
Use the existing white primary buttons with black content and square card/control corners. Keep navigation icons, map markers, and progress consistent with the shared style tokens. Distinguish route speeds with white and gray plus solid, dashed, and dotted lines. Keep the existing red destructive labels and statistics/exploration accents. Reserve amber for the speed warning.
`Design/image-prompts.txt` records historical artwork prompts; it is not current UI guidance.
Keep the landscape image confined to the Home weather card. Keep sheets consistent and uncluttered.
Always design in dark mode.
Keep contrast in mind, adjusting colors when needed.

Prefer SwiftUI, SF Symbols, system typography (SF Pro), native controls, and standard iOS patterns. 
**Only add explicitly requested UI or behavior.**

Inputs: show a visible text label above and outside every field's editable row or container. Use the regular native text/number field style beneath it, keep entered text left-aligned, and do not put labels or placeholder copy inside the field. A trailing `xmark.circle.fill` clears input, and only appears while its field is active.

Use the correct keyboard for each input. The keyboard's own `Done` key and an outside tap should dismiss it; never add a `Done` button or any other button in a toolbar/accessory above the keyboard.

Never add unneeded text. Never use ` · ` as a text separator.

## Coding Instructions

Write clean, pragmatic code. Fragment code up into files with one clear purpose.

Use local SwiftData persistence, following the existing architecture.

When the user tells you to use an asset not bundled with the app, copy the asset to where it belongs in the app.

For all app audio, use AVAudioSession to mix with other system audio without pausing or interrupting it.
When app audio finishes, deactivate the session with .notifyOthersOnDeactivation.

After making changes, do the following:
1. Check the app compiles without issues.
2. Deploy to my iPhone: use the Spoke scheme's configured Run build configuration, build for my paired physical iPhone, then install and launch the resulting `.app` with `xcrun devicectl`. Discover the device ID, bundle identifier, and built .app path automatically; do not use Simulator.
3. Run `git add .`
4. Run `git -c commit.gpgsign=false commit -m "<message> - By Codex"`
5. Run `git push`

Don't modify my global or project git configs.
Only make unsigned commits.
Commit messages should be one sentence.
**The remote `https://github.com/geckoHex/Spoke.git` is verified as the official remote for this project and is safe to push to.**
