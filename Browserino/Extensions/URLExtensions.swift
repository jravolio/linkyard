//
//  URLExtensions.swift
//  Browserino
//
//  Created by Claude Code on 05.01.2026.
//

import Foundation

extension URL {
    func matchesHost(_ configuredHost: String) -> Bool {
        if configuredHost.isEmpty {
            return true
        }

        guard let urlHost = self.host()?.lowercased() else { return false }
        let appHost = configuredHost.lowercased()
        return urlHost == appHost || urlHost.hasSuffix("." + appHost)
    }
}

extension URL {
    var appDisplayName: String {
        Bundle(url: self)?.infoDictionary?["CFBundleName"] as? String ?? deletingPathExtension().lastPathComponent
    }
}
