//
//  LoginItemManager.swift
//  QuickShot
//

import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func ensureEnabled() throws {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound:
            try SMAppService.mainApp.register()
        @unknown default:
            try SMAppService.mainApp.register()
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch SMAppService.mainApp.status {
            case .enabled:
                return
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
