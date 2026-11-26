// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  LiveWorkoutActivity.swift
//  Workout Plus
//
//  Drives the Lock Screen / Dynamic Island activity for a live workout and the
//  rest countdown.
//
//  This compiles and runs safely with no widget extension present: without one,
//  `Activity.request` simply throws and is logged. Add the Widget Extension
//  target (see /WorkoutPlusWidget/README.md at the repo root) and it lights up
//  with no changes here.
//

import Foundation
import os
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
enum LiveWorkoutActivity {

    #if canImport(ActivityKit)
    private static var current: Activity<WorkoutActivityAttributes>?

    private static func state(from engine: WorkoutEngine) -> WorkoutActivityAttributes.ContentState? {
        guard UserDefaults.standard.bool(forKey: "showWorkoutDetails"),
              let workout = engine.workout, let start = engine.startDate else { return nil }
        return .init(workoutName: workout.name,
                     progress: engine.progressText,
                     startDate: start,
                     restEndsAt: engine.restEndsAt,
                     restingFor: engine.restingFor,
                     upNext: engine.upNext,
                     upNextIsSuperset: engine.upNextIsSuperset)
    }
    #endif

    static func start(engine: WorkoutEngine) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let state = state(from: engine) else { return }
        // `current` is a static var, scoped to this process — but the Activity
        // itself is owned by the OS and outlives the process. If the app was
        // killed and relaunched mid-workout (e.g. resuming a snapshot after
        // being backgrounded for the length of the workout), `current` comes
        // back nil even though the original activity is still live. Adopting
        // it here avoids requesting a duplicate that nothing will ever end.
        adoptOrEndOrphans(activeWorkout: engine)
        guard current == nil else { update(engine: engine); return }
        do {
            current = try Activity.request(
                attributes: WorkoutActivityAttributes(planName: "Workout Plus"),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            // Expected until the Widget Extension target exists.
            Log.data.info("Live Activity unavailable: \(error.localizedDescription, privacy: .private)")
        }
        #endif
    }

    /// Reconciles `current` with whatever ActivityKit actually has running for
    /// this app. Pass the live engine to adopt (and refresh) an existing
    /// activity instead of leaving it orphaned; pass nil to end every activity
    /// this app has open, e.g. when a resume prompt is discarded.
    static func adoptOrEndOrphans(activeWorkout engine: WorkoutEngine?) {
        #if canImport(ActivityKit)
        guard current == nil else { return }
        let existing = Array(Activity<WorkoutActivityAttributes>.activities)
        guard let first = existing.first else { return }
        if let engine, let state = state(from: engine) {
            current = first
            Task { await first.update(ActivityContent(state: state, staleDate: nil)) }
            for stray in existing.dropFirst() {
                Task { await stray.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            for stray in existing {
                Task { await stray.end(nil, dismissalPolicy: .immediate) }
            }
        }
        #endif
    }

    static func update(engine: WorkoutEngine) {
        #if canImport(ActivityKit)
        guard let activity = current, let state = state(from: engine) else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        #endif
    }

    static func end() {
        #if canImport(ActivityKit)
        current = nil
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
