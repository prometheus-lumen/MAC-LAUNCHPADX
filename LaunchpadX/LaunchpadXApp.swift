//
//  LaunchpadXApp.swift
//  LaunchpadX
//
//  Created by 张航 on 2026/7/29.
//

import SwiftUI

@main
struct LaunchpadXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(environment: appDelegate.environment)
                .frame(minWidth: 1_200, minHeight: 800)
        }
    }
}
