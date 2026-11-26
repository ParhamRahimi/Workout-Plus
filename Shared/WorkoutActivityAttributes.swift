// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WorkoutActivityAttributes.swift
//  Workout Plus
//
//  Lives in /Shared and is a member of BOTH the app target and the widget
//  extension target. The two processes exchange this type verbatim, so it must
//  be the same declaration compiled into both — not a copy.
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

// ActivityKit uses this value across actor boundaries, independently of the UI.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "Workout B"
        var workoutName: String
        /// "4/10"
        var progress: String
        /// When the session started, so the widget can render a live elapsed timer.
        var startDate: Date
        /// When the current rest ends. nil = not resting.
        var restEndsAt: Date?
        /// What you're resting after.
        var restingFor: String?
        /// Where you're walking to next — set only once the exercise you just
        /// finished has no sets left, or when its superset partner is waiting.
        /// nil while you still have sets to do on the same machine.
        var upNext: String?
        /// True when `upNext` is the other half of a superset rather than the
        /// next exercise in the list.
        var upNextIsSuperset: Bool = false
    }

    /// Fixed for the life of the activity.
    var planName: String
}
#endif
