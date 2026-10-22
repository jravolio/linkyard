//
//  Rule.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import Foundation

struct Rule: Hashable, Codable {
    var regex: String
    var app: URL
    var profileDirectory: String? = nil
    var sourceApp: URL? = nil
    var sourceWindowTitleRegex: String? = nil
}

extension Rule {
    /// `windowTitle` is only called when the rule has a title pattern, since reading it is slow.
    func matches(_ urlString: String, sourceBundleID: String?, windowTitle: () -> String?) -> Bool {
        guard let urlRegex = try? Regex(regex).ignoresCase(),
              urlString.firstMatch(of: urlRegex) != nil
        else {
            return false
        }

        if let sourceApp {
            guard let ruleSourceBundleID = Bundle(url: sourceApp)?.bundleIdentifier,
                  sourceBundleID == ruleSourceBundleID
            else {
                return false
            }
        }

        let titlePattern = sourceWindowTitleRegex?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let titlePattern, !titlePattern.isEmpty {
            guard let title = windowTitle(),
                  let titleRegex = try? Regex(titlePattern).ignoresCase(),
                  title.firstMatch(of: titleRegex) != nil
            else {
                return false
            }
        }

        return true
    }
}
