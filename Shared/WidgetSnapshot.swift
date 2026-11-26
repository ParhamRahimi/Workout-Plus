// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WidgetSnapshot.swift
//  Shared between the app and the widget extension.
//
//  A widget extension is a separate process with its own container, so it
//  cannot open the app's SwiftData store. The usual fix is to move the whole
//  database into an App Group container — which means migrating an existing
//  store, and risking every session you've logged for the sake of a Home Screen
//  tile.
//
//  This does the cheap thing instead: the app writes a few hundred bytes of
//  JSON into the shared container whenever something the widget cares about
//  changes, and the widget reads it. No migration, nothing to lose, and the
//  widget stays readable even if the database is mid-write.
//

import Foundation

struct WidgetSnapshot: Codable, Hashable {
    // Plan
    var planName: String = ""
    var nextWorkoutID: String = ""
    var nextWorkoutName: String = ""
    var nextWorkoutFocus: String = ""
    var exerciseCount: Int = 0

    // This week
    var setsThisWeek: Int = 0
    var sessionsThisWeek: Int = 0
    var lastSessionDate: Date?

    // Live workout, when there is one
    var liveWorkoutName: String?
    var liveProgress: String?          // "4/10"
    var restEndsAt: Date?
    var upNext: String?

    var updatedAt: Date = .now

    var isLive: Bool { liveWorkoutName != nil }

    /// True only while the countdown is genuinely still running. The widget's
    /// timeline may be several minutes stale, so this has to be re-checked at
    /// render time rather than trusted from when it was written.
    var isResting: Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > .now
    }

    var fractionLogged: Double {
        guard let liveProgress else { return 0 }
        let parts = liveProgress.split(separator: "/")
        guard parts.count == 2, let done = Double(parts[0]), let total = Double(parts[1]), total > 0
        else { return 0 }
        return min(max(done / total, 0), 1)
    }

    // MARK: Shared container

    static var appGroupID: String { Bundle.main.object(forInfoDictionaryKey: "WorkoutPlusAppGroup") as? String ?? "group.org.workoutplus.app" }
    private static let filename = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the file actually changed, so the caller can skip
    /// asking WidgetKit to reload for no reason.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL else { return false }

        // Ignore `updatedAt` when comparing: otherwise every publish looks like
        // a change and the widget reloads on a timer it doesn't need.
        if var existing = Self.load() {
            existing.updatedAt = updatedAt
            if existing == self { return false }
        }

        guard let data = try? JSONEncoder().encode(self) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Shown in the widget gallery and while the real one loads.
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(planName: "Your 3-Day Full-Body Plan",
                       nextWorkoutID: "B",
                       nextWorkoutName: "Workout B",
                       nextWorkoutFocus: "Shoulders, hinge, chest, arms",
                       exerciseCount: 9,
                       setsThisWeek: 54,
                       sessionsThisWeek: 2,
                       lastSessionDate: nil)
    }
}
