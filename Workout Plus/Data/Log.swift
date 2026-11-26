// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  Log.swift
//  Workout Plus
//
//  There were 36 `try?` sites in this app, and the ones that mattered were the
//  `try? context.save()` calls: a failure there after a 90-minute session threw
//  the whole workout away with no message, no log line, and no way to find out
//  afterwards what had happened. Failures are now recorded, and the ones on the
//  path that can lose data are surfaced to the user as well.
//

import Foundation
import SwiftData
import os

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "WorkoutPlus"

    static let data = Logger(subsystem: subsystem, category: "data")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let images = Logger(subsystem: subsystem, category: "images")
    static let plans = Logger(subsystem: subsystem, category: "plans")
}

extension ModelContext {
    /// Save, and say so when it fails. Returns the error message, or nil on success.
    @discardableResult
    func saveLogging(_ what: String) -> String? {
        guard hasChanges else { return nil }
        do {
            try save()
            return nil
        } catch {
            Log.data.error("Save failed (\(what, privacy: .public)): \(error.localizedDescription, privacy: .private)")
            return error.localizedDescription
        }
    }
}
