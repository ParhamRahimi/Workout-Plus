// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation

enum SeedData {
    static let plan: Plan = {
        guard let url = Bundle.main.url(forResource: "starter-plan", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(Plan.self, from: data),
              let valid = try? PlanValidator.validated(plan) else {
            return Plan(id: "starter", name: "Starter Plan", summary: "Import or create a plan to begin.", daysPerWeek: 1, rotation: ["A"], workouts: [workoutA])
        }
        return valid
    }()
    static var workoutA: Workout {
        Workout(id: "A", name: "Workout A", focus: "Editable sample", exercises: [
            ExerciseTemplate(name: "Squat", category: "Legs", sets: 2, repRangeLow: 8, repRangeHigh: 12, isTimed: false, imageURLs: [], feel: "Legs", steps: ["Use a comfortable, controlled range."], tip: "Start with a manageable load and stop for pain.")
        ])
    }
}
