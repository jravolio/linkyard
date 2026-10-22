# Architecture

## A link's path

1. **macOS hands the link to Linkyard** (it's the default browser): `AppDelegate.application(_:open:)` in `Browserino/BrowserinoApp.swift`. `linkyard://open?url=<base64>` links are unwrapped first.
2. **Rules** (`Rule`, `ruleMatches`) are checked in order unless ⌘ is held. A rule matches the URL by regex, optionally the app the link came from (the last active app, tracked from workspace notifications), and optionally that app's window title. The title is read through Accessibility, lazily, only when a rule checks it (`SourceRuleContext`).
3. **A matching rule opens the link directly** through `BrowserUtil.openURL`. Otherwise the picker opens.
4. **The picker** (`BrowserinoWindow`, `PromptView`) shows one row per identity and one column per browser. Rows come from profiles grouped by display name (`pickerGroups` / `pickerGroupOrder` can override); columns follow the browser order from Settings. The window sizes itself to the view and opens at the cursor or the screen center (`prompt_centerOnScreen`).

## Opening a link in a profile

`BrowserUtil.openURL` switches on the browser's `ProfileSourceKind`:

| Kind | Browser | How |
|---|---|---|
| `chromium` | Chrome | `--profile-directory=<dir>` on a new app instance |
| `arc` | Arc | AppleScript: focus the space by ID, make a tab |
| `dia` | Dia | AppleScript: focus the profile by name, make a tab (Dia refuses the command-line flag) |
| `zenContainers` | Zen | `ext+container:name=…&url=…`, handled by the "Open external links in a container" add-on; Zen's `force-container-workspace` pref moves the tab to its workspace |

Any other browser opens the link with `NSWorkspace`, optionally with its private-window argument.

## Profiles

`ChromiumProfileUtil` (`Models/ChromeProfile.swift`) detects each source's profiles: Chrome from `Local State`, Arc spaces from `StorableSidebar.json` (cached by modification date), Dia by asking Dia over AppleScript when it's running (falling back to `Local State`), and Zen containers from the default Zen profile's `containers.json`. Detected profiles are merged with the stored ones so names, visibility and logos survive.

## Settings

Everything lives in `UserDefaults` through `@AppStorage`; arrays and dictionaries are stored as JSON strings (`Extensions/Array+RawRepresentable.swift`). Profile logos are copied as 256px PNGs to `~/Library/Application Support/Linkyard/ProfileIcons` and cached in memory (`ProfileImageCache`). On first launch Linkyard copies an existing Browserino setup from the `xyz.alexstrnik.Browserino` defaults domain.
