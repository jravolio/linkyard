# Working on Linkyard

Linkyard is a macOS menu bar app (SwiftUI + AppKit) that receives every link as the default browser and opens it in the right browser and profile. It continues [Browserino](https://github.com/AlexStrNik/Browserino); see [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit.

## Build and test

```sh
xcodebuild -project Browserino.xcodeproj -scheme Browserino -configuration Release build
xcodebuild -project Browserino.xcodeproj -scheme Browserino -destination 'platform=macOS' test
scripts/build-release.sh          # universal, ad-hoc signed zip in dist/
```

The Xcode project, target, scheme and Swift module paths keep Browserino's names on purpose: it keeps the history easy to compare with the original. Only the product (Linkyard.app, bundle ID `io.github.jravolio.Linkyard`) is renamed.

## Rules

- **Credit and license.** Linkyard is GPL-3.0 like Browserino. Every change from Browserino goes in [CHANGELOG.md](CHANGELOG.md) (GPL section 5a), and Aleksandr Strizhnev stays credited in the README and the About pane.
- **No real names.** Screenshots, sample text and fixtures use generic identities (Personal, Work, Northwind, Side Project, Acme). Regenerate README art with `scripts/readme-art/render-ui.sh`, which renders the real views from demo data in a throwaway home folder. `scripts/readme-art/render-animations.sh` records the picker effects GIF the same way.
- **Profiles are keyed by `selectionID`** (the Arc space ID, otherwise the profile directory or name). Picker items, shortcuts and Settings rows use `"<bundle id>::<selectionID>"`; changing that format breaks saved shortcuts.
- **Adding a browser.** Add a `ChromiumProfileSource` with its `ProfileSourceKind`, its `<name>Profiles` / `<name>ProfilesEnabled` storage keys in the picker, rule form, Profiles and Rules panes and Settings search, and how it opens a link in `BrowserUtil.openURL`.
- **Keep the link path fast.** Work done between a click and the picker (rule matching, profile refresh) runs on the main thread; cache file reads and only make Accessibility calls when a rule needs them.
- **AI disclosure.** Linkyard's additions are written with AI; keep the README's disclosure accurate when that changes.
