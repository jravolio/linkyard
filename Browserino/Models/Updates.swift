//
//  Updates.swift
//  Browserino
//

import AppKit
import Combine
import Sparkle

/// Sparkle reads the update feed from the latest GitHub release (`SUFeedURL`) and only installs downloads
/// signed with the key in `SUPublicEDKey`, since releases have no Apple Developer ID signature to check.
/// Sparkle schedules the checks itself, once a day. Reminders follow Sparkle's setup for apps without a Dock icon,
/// without the notification: https://sparkle-project.org/documentation/gentle-reminders/
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private(set) lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    private(set) var isShowingUpdate = false

    var settings: UpdateSettings {
        let controller = self.controller
        let updater = controller.updater
        return UpdateSettings(
            checksAutomatically: { updater.automaticallyChecksForUpdates },
            setChecksAutomatically: { updater.automaticallyChecksForUpdates = $0 },
            canCheck: updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher(),
            checkNow: { controller.checkForUpdates(nil) }
        )
    }

    // An update found after launch opens behind other apps.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        isShowingUpdate = true
        // A Dock icon, so the update window can be found again.
        NSApp.setActivationPolicy(.regular)
        if !state.userInitiated {
            NSApp.dockTile.badgeLabel = "1"
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = ""
    }

    func standardUserDriverWillFinishUpdateSession() {
        isShowingUpdate = false
        NSApp.setActivationPolicy(.accessory)
    }
}
