# Changelog

Linkyard is a modified version of [Browserino](https://github.com/AlexStrNik/Browserino) by Aleksandr Strizhnev, released under the same GPL-3.0 license. This file lists what Linkyard changed.

## Unreleased

### Added
- Linkyard updates itself from GitHub releases with [Sparkle](https://sparkle-project.org): it checks once a day (Settings → General → Updates, or **Check for Updates…** in the menu bar), shows the release notes and installs when you agree. An update found while Linkyard runs in the background waits behind your windows, with a badge on Linkyard's Dock icon. Each download is checked against an EdDSA signature before it's installed. Copies from 1.2.1 and earlier don't have the updater, so the first version with it is installed by hand.

### Changed
- The app's build number now matches its version (it was always 1), which update checks compare.

## 1.2.1

### Added
- Settings → Permissions lists what Linkyard needs macOS to allow, why, and whether it's allowed, with a button to allow it: Accessibility for window-title rules, and control of Dia and Arc for opening links in a profile or space.

### Fixed
- Rules that match a window title, like ones that tell Slack workspaces apart, stopped matching after an update: macOS turns Accessibility off for each new build, and Linkyard only ever asked once. It now asks again once per version when a rule needs it, and Settings → Rules says when those rules are skipped.

## 1.2.0

### Added
- Seven picker effects in Settings → Picker, listed under Effects: Restore (a burn in reverse that heals the picker from the bottom), Ink, Thaw, Crystallize, Ripple, Hologram and Materialize. They're drawn with Metal over a snapshot of the picker, which fades into the live picker as the effect ends; pressing a key or clicking ends it early. Reduce Motion turns them into a fade.
- An animation of the effects in the README.

## 1.1.0

### Added
- A choice of picker animations in Settings → Picker: none (the default), Fade, Rise, Zoom and Glow, with a Preview button. Zoom scales the whole window through the private AppKit method Arc and Dia use, and falls back to the system's window animation if that method is gone. Reduce Motion turns every animation into a fade.
- Search in Settings, covering every setting plus your browsers, profiles, rules and apps.
- Rules can be reordered by dragging one onto another; the first rule that matches still wins.

### Changed
- Settings is redesigned: a sidebar of panes with grouped sections and help text, a Picker pane for how the picker opens, and the browser search folders moved into Browsers. Resetting all settings now asks first, exported settings are saved as `linkyard-settings.json`, and the menu bar item reads Settings… instead of Preferences.
- The picker opens faster: it no longer fades in unless you choose an animation, its view is built once at launch and reused, and browser icons are rendered once instead of on every draw.
- Links open in Dia faster, and opening them no longer loads the AppleScript runtime (about 13 MB of memory): Linkyard sends Dia fewer Apple Events, built directly instead of through AppleScript. Arc still uses AppleScript.
- Closing Settings releases its views and memory.
- The picker closes as soon as you choose a browser instead of staying up until the browser responds.

### Fixed
- After "Reset all settings", Linkyard no longer copies your old Browserino settings back in on the next launch.
- Browser icons in the picker update after a browser updates, instead of keeping the old icon until Linkyard restarts.
- Pressing Esc while recording a shortcut cancels instead of saving Esc as the shortcut, and Delete removes the shortcut.
- Linkyard no longer crashes when a link arrives while the pointer is outside every screen, as can happen while displays are being connected or disconnected.

## 1.0.0

First Linkyard release, based on Browserino 1.1.16 plus the open [Chrome profile pull request #48](https://github.com/AlexStrNik/Browserino/pull/48) by Moti Levy.

### Added
- Arc spaces as picker items and rule targets, opened in the right space with AppleScript.
- Rules can match the app a link was clicked in and that app's window title, which tells Slack workspaces apart. The title is read through Accessibility, which Linkyard asks for on first launch.
- Hold ⌘ while clicking a link to skip your rules and get the picker.
- Dia profiles as picker items and rule targets, opened by profile name with AppleScript.
- Zen containers as picker items and rule targets, through the "Open external links in a container" Firefox add-on.
- A logo per profile, shown with a small badge of the browser it opens in, chosen from Settings → Profiles.
- A picker grouped by identity: one row per identity, one column per browser, keys 1–9 to open an identity, ←→ to switch browser.
- An option to open the picker in the center of the screen instead of at the cursor.
- A one-time import of Browserino settings on first launch.
- A new name, app icon and menu bar icon, and downloadable release builds.

### Changed
- The picker window now sizes itself to its content and is no longer resizable.
- The custom URL scheme is `linkyard://` instead of `browserino://`.

### Fixed
- Settings → Profiles mixed up rows when two browsers had a profile with the same name.
