// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation

struct PlanValidationError: LocalizedError {
    let problems: [String]
    var errorDescription: String? { problems.joined(separator: "\n") }
}

nonisolated enum ImportLimits {
    static let planBytes = 2 * 1024 * 1024
    static let backupBytes = 32 * 1024 * 1024

    static func read(_ url: URL, maximum: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Read one byte beyond the bound, never the entire untrusted file.
        let data = try file.read(upToCount: maximum + 1) ?? Data()
        try check(data, maximum: maximum)
        return data
    }

    static func check(_ data: Data, maximum: Int) throws {
        guard data.count <= maximum else {
            throw PlanValidationError(problems: ["This file is too large (limit: \(maximum / 1024) KB)."])
        }
    }
}

nonisolated enum PlanValidator {
    static let allowedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    static let maxImagesPerExercise = 8
    static let maxExercisesPerWorkout = 40
    static let maxWorkoutsPerPlan = 14

    static func validated(_ plan: Plan) throws -> Plan {
        var problems: [String] = []
        var clean = plan
        func text(_ value: String, _ label: String, maximum: Int = 200, required: Bool = true) {
            if value.count > maximum || (required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                problems.append("\(label) must contain \(required ? "1" : "0")–\(maximum) characters.")
            }
        }
        text(plan.id, "Plan ID", maximum: 100)
        text(plan.name, "Plan name")
        text(plan.summary, "Summary", maximum: 8000, required: false)
        guard (1...maxWorkoutsPerPlan).contains(plan.workouts.count), plan.rotation.count <= 100 else {
            throw PlanValidationError(problems: ["Use 1–14 workouts and at most 100 rotation entries."])
        }
        let ids = Set(plan.workouts.map(\.id))
        if ids.count != plan.workouts.count { problems.append("Workout IDs must be unique.") }
        if clean.rotation.isEmpty { clean.rotation = plan.workouts.map(\.id) }
        if clean.rotation.contains(where: { !ids.contains($0) }) { problems.append("Rotation references an unknown workout.") }
        if !(1...7).contains(plan.daysPerWeek) { problems.append("daysPerWeek must be 1–7.") }
        for workout in plan.workouts {
            text(workout.id, "Workout ID", maximum: 100)
            text(workout.name, "Workout name")
            text(workout.focus, "Focus", maximum: 2000, required: false)
            guard (1...maxExercisesPerWorkout).contains(workout.exercises.count) else {
                problems.append("Use 1–40 exercises per workout."); continue
            }
            for e in workout.exercises {
                text(e.id, "Exercise ID", maximum: 200)
                text(e.name, "Exercise name")
                text(e.category, "Category", maximum: 100)
                text(e.feel, "Muscle description", maximum: 2000, required: false)
                text(e.tip, "Tip", maximum: 4000, required: false)
                if let group = e.supersetGroup { text(group, "Superset group", maximum: 100) }
                if !(1...20).contains(e.sets) { problems.append("Sets must be 1–20.") }
                let maxTarget = e.isTimed ? 3600 : 1000
                if !(1...maxTarget).contains(e.repRangeLow) || !(1...maxTarget).contains(e.repRangeHigh) || e.repRangeLow > e.repRangeHigh {
                    problems.append("Repetition/time targets must be ordered and within 1–\(maxTarget).")
                }
                if let rest = e.restSeconds, !(0...1800).contains(rest) { problems.append("Rest must be 0–1800 seconds.") }
                if let step = e.weightIncrementKg, !step.isFinite || step <= 0 || step > 50 { problems.append("Weight increment must be greater than 0 and at most 50 kg.") }
                if e.steps.count > 20 { problems.append("Use at most 20 instruction steps.") }
                for step in e.steps.prefix(21) { text(step, "Instruction", maximum: 2000) }
                if e.imageURLs.count > maxImagesPerExercise || e.imageURLs.contains(where: { !isAllowedImageURL($0) }) {
                    problems.append("Use at most 8 image URLs from the supported exercise library, with no credentials or query strings.")
                }
            }
        }
        guard problems.isEmpty else { throw PlanValidationError(problems: Array(problems.prefix(30))) }
        return clean
    }

    static func filterImageURLs(_ raw: [String]) -> (kept: [String], rejected: [String]) {
        let kept = Array(raw.filter(isAllowedImageURL).prefix(maxImagesPerExercise))
        return (kept, raw.filter { !kept.contains($0) })
    }

    static func isAllowedImageURL(_ string: String) -> Bool {
        guard string.utf8.count <= 2048, let c = URLComponents(string: string),
              c.scheme == "https", c.host == "raw.githubusercontent.com", c.port == nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              let url = c.url,
              url.path.hasPrefix("/yuhonas/free-exercise-db/main/exercises/"),
              !url.pathComponents.contains(".."),
              allowedImageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return true
    }
}
