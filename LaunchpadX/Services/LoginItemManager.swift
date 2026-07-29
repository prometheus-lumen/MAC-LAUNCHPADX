import Foundation
import ServiceManagement

@MainActor
@Observable
final class LoginItemManager {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
