# Changelog

Linkyard is a modified version of [Browserino](https://github.com/AlexStrNik/Browserino) by Aleksandr Strizhnev, released under the same GPL-3.0 license. This file lists what Linkyard changed.

## 1.0.0

First Linkyard release, based on Browserino 1.1.16 plus the open [Chrome profile pull request #48](https://github.com/AlexStrNik/Browserino/pull/48) by Moti Levy.

### Added
- Arc spaces as picker items and rule targets, opened in the right space with AppleScript.
- Rules can match the app a link was clicked in and, for Slack, its window title, which tells workspaces apart. The title is read through Accessibility, which Linkyard asks for on first launch.
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
