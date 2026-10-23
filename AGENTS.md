# Working on Linkyard

Linkyard is a macOS menu bar app (SwiftUI + AppKit) that receives every link as the default browser and opens it in the right browser and profile. It continues [Browserino](https://github.com/AlexStrNik/Browserino); see [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit.

## Build and test

```sh
xcodebuild -project Browserino.xcodeproj -scheme Browserino -configuration Release -destination 'generic/platform=macOS' build
xcodebuild -project Browserino.xcodeproj -scheme Browserino -destination 'platform=macOS' test
scripts/build-release.sh          # universal, ad-hoc signed zip in dist/
```

The Xcode project, target, scheme and source folders keep Browserino's names on purpose: it keeps the history easy to compare with the original. The product, its Swift module (`@testable import Linkyard`) and the bundle ID `io.github.jravolio.Linkyard` are Linkyard.

CI builds with the Xcode on GitHub's `macos-15` image (16.4, macOS 15 SDK), which is older than a current local Xcode. Wrap APIs from newer SDKs in `#if compiler(>=6.2)` as well as `#available`, and check CI before calling a change done.

## Branches, commits and releases

- **Branches** are `<type>/<kebab-case-title>`: `feature/`, `fix/`, `refactor/`, `chore/`, `docs/`. **Commits** use the matching type: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (and `test:` for test-only changes), imperative, under 72 characters, with `!` after the type for a breaking change.
- **Changelog.** Every user-facing change goes under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md) (Added, Changed, Fixed), which also keeps GPL section 5a's record of changes from Browserino. A release turns it into `## <version> - <date>`.
- **Releasing.** Bump `MARKETING_VERSION` in all four build configurations, merge, tag the merge commit (`git tag -a v1.2.3 -m "Linkyard 1.2.3"`) and push only that tag (`git push origin v1.2.3`): this clone also has Browserino's `v1.x` tags, and every `v*` tag pushed runs `release.yml`. Never `git push --tags`. The release also needs the `SPARKLE_ED_PRIVATE_KEY` secret (it signs the update feed), a tag that matches `MARKETING_VERSION` and a `## <version>` section in the changelog, or `release.yml` stops before publishing.

## Rules

- **Credit and license.** Linkyard is GPL-3.0 like Browserino. Every change from Browserino goes in the changelog, and Aleksandr Strizhnev stays credited in the README and the About pane.
- **No real names.** Screenshots, sample text and fixtures use generic identities (Personal, Work, Northwind, Side Project, Acme). Regenerate README art with `scripts/readme-art/render-ui.sh`, which renders the real views from demo data in a throwaway home folder. `scripts/readme-art/render-animations.sh` records the picker effects GIF the same way.
- **Adding a file.** The project has no synchronized folders: a new file needs a `PBXFileReference`, a `PBXBuildFile`, an entry in its group and one in the target's Sources phase in `project.pbxproj`, or it isn't compiled. Use IDs that aren't in the file yet.
- **Profiles are keyed by `selectionID`** (the Arc space ID, otherwise the profile directory or name). Picker items, shortcuts and Settings rows use `"<bundle id>::<selectionID>"`; changing that format breaks saved shortcuts.
- **Adding a browser.** Add a `ChromiumProfileSource` with its `ProfileSourceKind` and its case in `ChromiumProfileUtil`'s detection, its `<name>Profiles` / `<name>ProfilesEnabled` storage keys in the picker, rule form and Profiles pane, `<name>Profiles` in the Rules pane and Settings search, and how it opens a link in `BrowserUtil.openURL`. A browser driven by Apple Events also needs a row in Settings → Permissions and a mention in `NSAppleEventsUsageDescription`.
- **Keep the link path fast.** Work between a click and the picker (rule matching, profile refresh, and launch work when a link launches the app) runs on the main thread; keep it well under 50 ms, measure it, and put the numbers in the PR. Apple Events, `AEDeterminePermissionToAutomateTarget`, `Process` and large file reads never run on the main thread, and Accessibility calls happen only when a rule needs them.
- **Idle costs nothing.** No repeating timers or polling outside a visible window or a running animation; invalidate timers when done and give long-lived ones tolerance.
- **Focus.** The picker takes focus with `activate(ignoringOtherApps:)`. It's deprecated in newer SDKs, but `NSApp.activate()` needs macOS 14 and is cooperative, so the picker may not get focus; test any change by clicking a link in another app, such as Slack.
- **Concurrency.** The code uses Swift 5 mode and GCD. Moving to Swift 6 or strict concurrency is its own `refactor/` branch.
- **Tests.** XCTest, one `final class` per area, test names that read as sentences. Use `UserDefaults(suiteName:)` and temporary folders, never `.standard` or real browser profiles. Tests run inside Linkyard.app, so launch side effects stay behind the XCTest check in `applicationDidFinishLaunching`. Permission prompts, Arc and Dia Apple Events, focus and animations are checked live, not in CI.
- **Permissions and test builds.** Releases are ad-hoc signed, so every build is a new app to macOS's privacy settings and loses Accessibility and Automation. Before testing window-title rules or Arc/Dia live, run `tccutil reset Accessibility <bundle id>` (and `AppleEvents`) and allow again. Every build also registers as an http/https handler; quit test copies and remove them with `lsregister -u <path>` when done.
- **Signing.** The hardened runtime isn't applied today (the script signs without `-o runtime`). If it ever is, add `com.apple.security.automation.apple-events`, or Arc and Dia stop working. Sign nested code (helpers, frameworks) one by one instead of with `--deep`, which is deprecated.
- **Updates.** Only `Models/Updates.swift` and `BrowserinoApp.swift` import Sparkle. Settings views reach the updater through the `updateSettings` environment value, because the README art scripts compile the views without the files that import Sparkle.
- **Stored settings.** Renaming an `@AppStorage` key or changing a stored JSON shape wipes people's setup: migrate on read and note it under Changed.
- **Motion, VoiceOver and text.** New motion goes through `PickerAnimation.resolved`, which honors Reduce Motion. Icon-only controls get an `.accessibilityLabel`. UI copy stays as literals in `Text` and `Button` so a String Catalog can pick it up later.
- **AI disclosure.** Linkyard's additions are written with AI; keep the README's disclosure accurate when that changes.
