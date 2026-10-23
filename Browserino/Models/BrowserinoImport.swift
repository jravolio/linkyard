//
//  BrowserinoImport.swift
//  Browserino
//

import Foundation

/// Coming from Browserino, Linkyard starts with its settings. A new bundle ID starts with empty settings, and the
/// Accessibility prompt flag isn't copied since Linkyard needs its own grant.
enum BrowserinoImport {
    /// Kept through "Reset all settings", so a reset doesn't bring Browserino's settings back on the next launch.
    static let doneKey = "browserinoSettingsImported"

    static func importIfNeeded(into defaults: UserDefaults = .standard, from domain: String = "xyz.alexstrnik.Browserino") {
        guard defaults.object(forKey: "browsers") == nil, !defaults.bool(forKey: doneKey) else {
            return
        }

        defaults.set(true, forKey: doneKey)
        guard let browserino = defaults.persistentDomain(forName: domain) else {
            return
        }

        for (key, value) in browserino where !key.hasPrefix("NS") && key != "sourceDetectionAccessibilityPrompted" {
            defaults.set(value, forKey: key)
        }
    }
}
