import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. Registration only works when
/// Lodestar runs from a real .app bundle (see scripts/bundle.sh); a bare
/// `swift run` binary has no bundle for launchd to start.
enum LaunchAtLogin {
    enum State: Equatable {
        case unavailable   // not running from an .app bundle
        case disabled
        case enabled
        case requiresApproval  // registered, but the user must allow it in Login Items
    }

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var state: State {
        guard isBundledApp else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isBundledApp else { throw LaunchAtLoginError.notBundled }
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            try service.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notBundled

    var errorDescription: String? {
        "Launch at login only works from the bundled Lodestar.app (build it with ./scripts/bundle.sh)."
    }
}
