import AppKit
import SwiftUI

struct SettingsRootView: View {
    let environment: AppEnvironment
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            Divider()
            Group {
                switch section {
                case .general: GeneralSettingsView(environment: environment)
                case .shortcuts: ShortcutSettingsView(environment: environment)
                case .layout: LayoutSettingsView(environment: environment)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 520)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, layout
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .layout: "square.grid.3x3"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .layout: "Layout"
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.title.bold())
            content
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var loginItems: LoginItemManager

    init(environment: AppEnvironment) {
        settings = environment.settings
        loginItems = environment.loginItems
    }

    var body: some View {
        SettingsPage(title: "General") {
            Form {
                Toggle("Launch at login", isOn: Binding(get: { loginItems.isEnabled }, set: { loginItems.setEnabled($0) }))
                if loginItems.needsApproval {
                    LabeledContent("Login item") {
                        Button("Open System Settings") { loginItems.openSystemSettings() }
                    }
                }
                Toggle("Focus search when opened", isOn: $settings.focusSearchOnShow)
                Toggle("Reverse page direction", isOn: $settings.reversePageDirection)
            }
            .formStyle(.grouped)
        }
    }
}

private struct ShortcutSettingsView: View {
    let environment: AppEnvironment
    @Bindable var settings: SettingsStore
    @State private var errorMessage: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        settings = environment.settings
    }

    var body: some View {
        SettingsPage(title: "Shortcuts") {
            Form {
                LabeledContent("Open LaunchpadX") {
                    HotKeyRecorder(hotKey: $settings.hotKey, requiresModifier: true) { hotKey in
                        let previous = settings.hotKey
                        settings.hotKey = hotKey
                        do { try environment.reregisterHotKey() }
                        catch {
                            settings.hotKey = previous
                            try? environment.reregisterHotKey()
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                LabeledContent("Previous page") {
                    HotKeyRecorder(hotKey: $settings.previousPageHotKey, requiresModifier: false) {
                        settings.previousPageHotKey = $0
                    }
                }
                LabeledContent("Next page") {
                    HotKeyRecorder(hotKey: $settings.nextPageHotKey, requiresModifier: false) {
                        settings.nextPageHotKey = $0
                    }
                }
            }
            .formStyle(.grouped)
            Button("Restore Default Shortcuts") {
                let previous = settings.hotKey
                settings.hotKey = .defaultLauncher
                do { try environment.reregisterHotKey() }
                catch {
                    settings.hotKey = previous
                    try? environment.reregisterHotKey()
                    errorMessage = error.localizedDescription
                }
                settings.previousPageHotKey = .defaultPreviousPage
                settings.nextPageHotKey = .defaultNextPage
            }
        }
        .alert(String(localized: "Shortcut Error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

private struct LayoutSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        SettingsPage(title: "Layout") {
            Text("Rebuild the app grid in name order. This keeps scanned apps and clears only your manual arrangement.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440, alignment: .leading)
            Button("Restore App Arrangement") {
                environment.launcherViewModel.resetLayout()
            }
            Divider()
            Button("Rescan Applications") {
                Task { await environment.launcherViewModel.rescan() }
            }
        }
    }
}
