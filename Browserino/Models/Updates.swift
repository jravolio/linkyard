//
//  Updates.swift
//  Browserino
//

import Combine
import Sparkle

/// Sparkle reads the update feed from the latest GitHub release (`SUFeedURL`) and only installs downloads
/// signed with the key in `SUPublicEDKey`, since releases have no Apple Developer ID signature to check.
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private(set) lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)

    /// The version of an update a scheduled check found and nobody has looked at yet, or nil.
    var onUnseenUpdate: (String?) -> Void = { _ in }

    var updater: SPUUpdater { controller.updater }

    func start() {
        controller.startUpdater()
    }

    var settings: UpdateSettings {
        UpdateSettings(
            checksAutomatically: { [weak self] in self?.updater.automaticallyChecksForUpdates ?? false },
            setChecksAutomatically: { [weak self] in self?.updater.automaticallyChecksForUpdates = $0 },
            canCheck: updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).eraseToAnyPublisher(),
            checkNow: { [weak self] in self?.controller.checkForUpdates(nil) }
        )
    }

    // A menu bar app is rarely active, so a scheduled update window opens behind other apps; the menu points to it.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated {
            onUnseenUpdate(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onUnseenUpdate(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onUnseenUpdate(nil)
    }
}
