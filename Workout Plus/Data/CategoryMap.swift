// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  CategoryMap.swift
//  Workout Plus
//
//  Muscle-group tags are free text so an imported plan can't crash on an
//  unknown one — but that means every plan invents its own vocabulary. The seed
//  plan tags face pulls "Posture"; the v2 plan tags them "Upper Back". Both are
//  in your history, so the weekly-volume chart draws them as two unrelated bars
//  in two unrelated colours and becomes unreadable the moment you switch plans.
//
//  Two fixes, and they work together:
//
//  1. `canonical(_:)` folds synonyms at DISPLAY time. Nothing is rewritten, and
//     a plan you import next year that says "Rear Delts" lines up immediately.
//  2. `retag(...)` rewrites history to match the plan you're actually running,
//     for the cases a synonym table can't know about. That one is destructive,
//     so it's an explicit button with a preview.
//

import Foundation

enum CategoryMap {

    /// Fixed order, so the chart's colour scale is stable no matter which
    /// groups happen to be present in the visible weeks.
    static let canonicalOrder = [
        "Legs", "Posterior Chain", "Calves",
        "Chest", "Back", "Upper Back", "Shoulders",
        "Arms", "Forearms", "Grip",
        "Core", "Mobility", "Cardio"
    ]

    private static let synonyms: [String: String] = [
        // Legs / hinge
        "legs": "Legs", "leg": "Legs", "quads": "Legs", "quadriceps": "Legs",
        "lower body": "Legs",
        "posterior chain": "Posterior Chain", "hamstrings": "Posterior Chain",
        "hamstring": "Posterior Chain", "glutes": "Posterior Chain",
        "glute": "Posterior Chain", "hinge": "Posterior Chain",
        "lower back": "Posterior Chain", "erectors": "Posterior Chain",
        "calves": "Calves", "calf": "Calves",

        // Torso
        "chest": "Chest", "pecs": "Chest", "pectorals": "Chest",
        "back": "Back", "lats": "Back", "lat": "Back",
        "upper back": "Upper Back", "posture": "Upper Back",
        "rear delts": "Upper Back", "rear delt": "Upper Back", "traps": "Upper Back",
        "shoulders": "Shoulders", "shoulder": "Shoulders", "delts": "Shoulders",
        "deltoids": "Shoulders", "side delts": "Shoulders", "side delt": "Shoulders",

        // Arms
        "arms": "Arms", "arm": "Arms", "biceps": "Arms", "bicep": "Arms",
        "triceps": "Arms", "tricep": "Arms",
        "forearms": "Forearms", "forearm": "Forearms", "wrists": "Forearms",
        "wrist": "Forearms",
        "grip": "Grip",

        // Everything else
        "core": "Core", "abs": "Core", "abdominals": "Core", "obliques": "Core",
        "mobility": "Mobility", "stretching": "Mobility", "flexibility": "Mobility",
        "cardio": "Cardio", "conditioning": "Cardio", "zone 2": "Cardio"
    ]

    /// Folds a tag onto the canonical vocabulary. An unrecognised tag is kept
    /// (tidied, not discarded) — inventing a new group is better than silently
    /// dumping it into "Other" where you'd never find it again.
    static func canonical(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return "Other" }
        if let hit = synonyms[key] { return hit }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every group that could appear, in a stable order — canonical groups
    /// first, then whatever unrecognised tags actually turned up.
    static func chartDomain(including present: [String]) -> [String] {
        var domain = canonicalOrder
        for tag in present.sorted() where !domain.contains(tag) {
            domain.append(tag)
        }
        return domain
    }

    // MARK: - Rewriting history

    struct RetagPreview {
        /// Sets whose category would change because the exercise appears in the
        /// active plan under a different tag.
        var matchedByExercise: Int = 0
        /// Sets whose category would change purely by synonym folding.
        var normalisedOnly: Int = 0
        /// Distinct "Old → New" lines, for showing the user what will happen.
        var changes: [String] = []

        var total: Int { matchedByExercise + normalisedOnly }
    }

    /// Works out (and optionally applies) what re-tagging history to the active
    /// plan would do. Matching is by exercise NAME, because that is the only
    /// thing a logged set and a plan slot reliably share.
    @discardableResult
    static func retag(sessions: [WorkoutSession],
                      to plan: Plan,
                      apply: Bool) -> RetagPreview {

        var planCategory: [String: String] = [:]      // lowercased name -> tag
        for workout in plan.workouts {
            for exercise in workout.exercises {
                planCategory[exercise.name.lowercased()] = canonical(exercise.category)
            }
        }

        var preview = RetagPreview()
        var seenChanges = Set<String>()

        for session in sessions {
            for entry in session.sets {
                let current = entry.category
                let target: String
                let fromPlan: Bool

                if let planTag = planCategory[entry.exerciseName.lowercased()] {
                    target = planTag
                    fromPlan = true
                } else {
                    target = canonical(current)
                    fromPlan = false
                }

                guard target != current else { continue }

                if fromPlan { preview.matchedByExercise += 1 } else { preview.normalisedOnly += 1 }
                let line = "\(current) → \(target)"
                if seenChanges.insert(line).inserted { preview.changes.append(line) }

                if apply { entry.category = target }
            }
        }

        preview.changes.sort()
        return preview
    }
}
