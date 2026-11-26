// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

@main
struct Workout_PlusApp: App {
    private let container: ModelContainer?
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotDemo.enabled {
            // Fail closed: fixture failure must never fall through to real persistence.
            container = try? ScreenshotDemo.makeContainer()
        } else { container = PersistenceSetup.makeContainer() }
        #else
        container = PersistenceSetup.makeContainer()
        #endif
    }
    var body: some Scene {
        WindowGroup {
            if let container { RootView().modelContainer(container) }
            else {
                ContentUnavailableView("Training data unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(PersistenceSetup.failureMessage ?? "Reopen the app or contact support. Do not uninstall it."))
            }
        }
    }
}
