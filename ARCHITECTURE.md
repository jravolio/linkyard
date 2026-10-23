# Architecture

## A link's path

1. **macOS hands the link to Linkyard** (it's the default browser): `AppDelegate.application(_:open:)` in `Browserino/BrowserinoApp.swift`. `linkyard://open?url=<base64>` links are unwrapped first.
2. **Rules** (`Rule`, `ruleMatches`) are checked in order unless ⌘ is held. A rule matches the URL by regex, optionally the app the link came from (the last active app, tracked from workspace notifications), and optionally that app's window title. The title is read through Accessibility, lazily, only when a rule checks it (`SourceRuleContext`). Releases are ad-hoc signed, so macOS drops that permission on every update; `AccessibilityPermission` asks again once per version when a rule needs it, and Settings → Permissions (`Models/Permissions.swift`) shows Accessibility and Dia/Arc Automation status. `AEDeterminePermissionToAutomateTarget` is only called for running apps and off the main thread, since for some apps that aren't running (Arc) it never returns.
3. **A matching rule opens the link directly** through `BrowserUtil.openURL`. Otherwise the picker opens.
4. **The picker** (`BrowserinoWindow`, `PromptView`) shows one row per identity and one column per browser. Rows come from profiles grouped by display name (`pickerGroups` / `pickerGroupOrder` can override); columns follow the browser order from Settings. The window sizes itself to the view and opens at the cursor or the screen center (`prompt_centerOnScreen`). Its view is built at launch and reused for every link (`openID` resets the selection), and it closes before the chosen browser is opened. The entrance animation (`PickerAnimation`, `prompt_animation`) is none by default; the others animate the window itself in `BrowserinoWindow.orderFront(animation:)` so the system shadow moves with it, and Glow adds a SwiftUI overlay. Zoom scales the whole window through AppKit's private `_setTransformForAnimation:anchorPoint:` (the method Arc and Dia use); it's looked up at runtime and checked against its type encoding, and without it Zoom falls back to the system's document-window animation. The effects (`PickerAnimation.effects`) are drawn by `PickerEffects.metal` in `PickerEffectView`, which sits above the hidden picker in the window's container view: it snapshots the picker's content without its blurred background, and each frame draws that content with the effect applied plus a mask that reveals its own copy of the blur. Every effect starts with nothing drawn and ends on the snapshot exactly (a unit test renders both ends at the picker's real sizes). The snapshot draws images slightly differently from the live picker, so for the last 120 ms the live picker is shown underneath and the effect fades out over it. The window's shadow and background stay off until the effect is removed, so the shadow appears in one step. A key press or click ends the effect early.

## Opening a link in a profile

`BrowserUtil.openURL` switches on the browser's `ProfileSourceKind`:

| Kind | Browser | How |
|---|---|---|
| `chromium` | Chrome | `--profile-directory=<dir>` on a new app instance |
| `arc` | Arc | AppleScript: focus the space by ID, make a tab |
| `dia` | Dia | Apple Events built by hand (`AppleEvents`): make a tab in the profile found by name, which also switches to it (Dia refuses the command-line flag) |
| `zenContainers` | Zen | `ext+container:name=…&url=…`, handled by the "Open external links in a container" add-on; Zen's `force-container-workspace` pref moves the tab to its workspace |

Any other browser opens the link with `NSWorkspace`, optionally with its private-window argument.

## Profiles

`ChromiumProfileUtil` (`Models/ChromeProfile.swift`) detects each source's profiles: Chrome from `Local State`, Arc spaces from `StorableSidebar.json` (cached by modification date), Dia by asking Dia over Apple Events when it's running (falling back to `Local State`), and Zen containers from the default Zen profile's `containers.json`. Detected profiles are merged with the stored ones so names, visibility and logos survive.

## Settings

The Settings window (`PreferencesView`) is a sidebar of panes (`SettingsPane`) with grouped forms. Search covers both the settings and what the user set up (`SettingsSearch`); opening a result switches pane and scrolls to the row marked with the same `settingsItem` ID.

Everything lives in `UserDefaults` through `@AppStorage`; arrays and dictionaries are stored as JSON strings (`Extensions/Array+RawRepresentable.swift`). Profile logos are copied as 256px PNGs to `~/Library/Application Support/Linkyard/ProfileIcons` and cached in memory (`ProfileImageCache`). Browser icons in the picker are rendered once per size, screen scale and appearance (`AppIconCache`), since Icon Services renders them over XPC on every draw. On first launch Linkyard copies an existing Browserino setup from the `xyz.alexstrnik.Browserino` defaults domain.

## Updates

Linkyard uses Sparkle (`Models/Updates.swift`). `SUFeedURL` points at `appcast.xml` on the latest GitHub release, and Sparkle only installs a download whose EdDSA signature matches `SUPublicEDKey`, since ad-hoc signed releases give it no Apple signature to compare. `release.yml` builds the feed with Sparkle's `generate_appcast`, signs it with the `SPARKLE_ED_PRIVATE_KEY` secret and attaches it to the release; the release fails without the secret, or without a CHANGELOG section for the version, rather than publishing a latest release that has no feed. Release notes in the feed come from the version's section of CHANGELOG.md. Sparkle compares `CFBundleVersion`, so `CURRENT_PROJECT_VERSION` follows `MARKETING_VERSION`. Settings reach the updater through the `updateSettings` environment value, so the Settings views build without Sparkle (the README art scripts leave `Updates.swift` out). `build-release.sh` removes Sparkle's XPC services, which only sandboxed apps need, and signs the nested code inside out instead of with `--deep`.
