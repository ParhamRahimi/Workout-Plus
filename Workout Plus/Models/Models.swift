// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

// MARK: - Content models (static template data)

/// One exercise as defined by the plan (the "how to do it" info).
/// This is template data — it never changes when you work out.
nonisolated struct ExerciseTemplate: Identifiable, Codable, Hashable {
    /// Stable slot identity, stored so it survives a save/reload round trip.
    /// Almost no plan JSON carries an "id", in which case the name is used —
    /// which keeps plans.json and crash snapshots written before this existed
    /// (they were keyed by name) working unchanged. `Workout` fills this in
    /// when one workout repeats a name, which LLM-written plans do constantly.
    var explicitID: String? = nil
    var name: String
    var category: String           // kept as String (not enum) so LLM imports can't crash on a new tag
    var sets: Int
    var repRangeLow: Int           // for timed moves, these are SECONDS
    var repRangeHigh: Int
    var isTimed: Bool              // true for Plank etc.
    var imageURLs: [String]        // used starting Milestone 2
    var feel: String               // "Where you feel it"
    var steps: [String]
    var tip: String
    var supersetGroup: String? = nil     // e.g. "Wrists" — consecutive same-group = superset
    /// Explicit override for assist-style loading. Absent from almost every
    /// plan, in which case the name decides.
    var isAssisted: Bool? = nil
    /// Explicit override for "the load is your own body". Absent from almost
    /// every plan, in which case the rep range and name decide.
    var isBodyweight: Bool? = nil
    var weightIncrementKg: Double? = nil
    /// Rest between sets. Absent from almost every plan, in which case it is
    /// derived from the rep range — a 5–8 compound needs minutes, a 20-rep
    /// wrist curl needs seconds, and guessing that from the prescription is
    /// better than pretending rest doesn't exist.
    var restSeconds: Int? = nil

    enum CodingKeys: String, CodingKey {
        case explicitID = "id"
        case name, category, sets, repRangeLow, repRangeHigh
        case isTimed, imageURLs, feel, steps, tip, supersetGroup
        case isAssisted, isBodyweight, restSeconds, weightIncrementKg
    }

    var id: String { explicitID ?? name }

    /// True when a BIGGER number means an EASIER set — assist machines,
    /// counterweights. Progress on these means the load goes DOWN, not up.
    var loadIsAssistance: Bool { isAssisted ?? Self.nameImpliesAssistance(name) }

    /// True when there is no external load to add, so "add 1 kg" is the wrong
    /// advice and "add reps or pick a harder variation" is the right one.
    var loadIsBodyweight: Bool { isBodyweight ?? Self.nameImpliesBodyweight(name) }

    /// Logged history keeps only the exercise name, so the name heuristics have
    /// to be reachable without a template. An explicit flag in the plan always
    /// wins over these.
    static func nameImpliesAssistance(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("assisted")
    }

    /// Deliberately conservative: a false positive here would tell you to stop
    /// adding weight to something you can load. Anything this misses is still
    /// caught at runtime, because a lift logged at 0 kg is treated as
    /// bodyweight regardless of its name.
    static func nameImpliesBodyweight(_ name: String) -> Bool {
        let hints = ["plank", "dead hang", "hanging knee", "hanging leg",
                     "push-up", "push up", "hollow", "bird dog",
                     "pull-up", "pull up", "chin-up", "chin up", "dip"]
        let n = canonicalName(name).lowercased()
        return hints.contains { n.contains($0) }
    }

    /// The load logged against your own bodyweight: negative (assisted, help
    /// subtracted) through zero (plain bodyweight) to positive (added load,
    /// a belt or vest). This is what turns "12 kg assist" and "12 kg added"
    /// into one number that simply gets bigger as you improve, across the
    /// whole assisted → bodyweight → weighted arc of the same exercise.
    static func effectiveLoad(weightKg: Double, isAssisted: Bool, bodyweightKg: Double) -> Double {
        isAssisted ? bodyweightKg - weightKg : bodyweightKg + weightKg
    }

    /// A set's truth (`SetEntry.isAssisted`) now carries whether it was
    /// assisted, so the exercise no longer has to be permanently classified.
    /// The one thing a rename still breaks is history lookup by name — these
    /// two lifts used to be spelled "Assisted Pull-up" / "Assisted Chin-up"
    /// before the per-set flag existed. Every place that aggregates history
    /// by `exerciseName` should go through `canonicalName` so old and new
    /// rows land in the same series, the same way `CategoryMap.canonical`
    /// folds category-name drift between plan versions.
    static let historicalNameAliases: [String: String] = [
        "Assisted Pull-up": "Pull-up",
        "Assisted Chin-up": "Chin-up",
    ]
    static func canonicalName(_ name: String) -> String {
        historicalNameAliases[name] ?? name
    }

    /// Every spelling this exercise has ever been logged under — the current
    /// name plus any older alias(es) that map to the same canonical name.
    /// Feed this to a history fetch/filter instead of a single name so a
    /// rename doesn't sever "last time" or PR continuity.
    static func namesForHistory(_ name: String) -> Set<String> {
        let canonical = canonicalName(name)
        var names: Set<String> = [name, canonical]
        for (old, new) in historicalNameAliases where new == canonical {
            names.insert(old)
        }
        return names
    }

    /// Seconds to rest after a set of this exercise.
    var prescribedRest: Int {
        if let restSeconds, restSeconds > 0 { return restSeconds }
        if isTimed { return 60 }
        if repRangeHigh <= 8 { return 180 }      // heavy compound work
        if repRangeHigh <= 12 { return 120 }
        if repRangeHigh <= 15 { return 90 }
        return 60                                 // high-rep isolation
    }

    /// Human-readable "3 × 12–15" or "3 × 30–45 sec".
    var prescription: String {
        let unit = isTimed ? " sec" : ""
        let range = repRangeLow == repRangeHigh
            ? "\(repRangeLow)\(unit)"
            : "\(repRangeLow)–\(repRangeHigh)\(unit)"
        return "\(sets) × \(range)"
    }

    /// "2 min" / "90 sec" for display.
    var restText: String {
        let s = prescribedRest
        if s % 60 == 0 && s >= 60 { return "\(s / 60) min" }
        return "\(s) sec"
    }
}

/// One of the three workouts (A / B / C).
nonisolated struct Workout: Identifiable, Codable, Hashable {
    var id: String                 // "A", "B", "C"
    var name: String               // "Workout A"
    var focus: String
    var exercises: [ExerciseTemplate]

    init(id: String, name: String, focus: String, exercises: [ExerciseTemplate]) {
        self.id = id
        self.name = name
        self.focus = focus
        self.exercises = Self.disambiguated(exercises)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        focus = try c.decode(String.self, forKey: .focus)
        exercises = Self.disambiguated(try c.decode([ExerciseTemplate].self, forKey: .exercises))
    }

    /// The engine keys drafts, substitutions and the logged-set marker by slot
    /// id, so ids have to be unique *within a workout* — otherwise two slots
    /// called "Machine Lateral Raise" share one set of numbers. The first
    /// occurrence keeps the bare name, so anything already keyed by name (saved
    /// plans, an interrupted workout's snapshot) still lines up.
    private static func disambiguated(_ exercises: [ExerciseTemplate]) -> [ExerciseTemplate] {
        var seen = Set<String>()
        return exercises.enumerated().map { index, exercise in
            var e = exercise
            if !seen.insert(e.id).inserted {
                e.explicitID = "\(e.name)#\(index)"
                // Pathological: the plan also contains a literal "Name#3".
                var salt = 1
                while !seen.insert(e.id).inserted {
                    e.explicitID = "\(e.name)#\(index)-\(salt)"
                    salt += 1
                }
            }
            return e
        }
    }
}

/// The whole training plan.
nonisolated struct Plan: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var summary: String
    var daysPerWeek: Int
    var rotation: [String]         // ["A", "B", "C"]
    var workouts: [Workout]

    func workout(id: String) -> Workout? {
        workouts.first { $0.id == id }
    }

    /// Plan-scoped workout identity. `Workout.id` is just "A"/"B"/"C", so two
    /// installed plans both have a Workout A — the engine has to be able to
    /// tell them apart or it will show a live workout's controls on the wrong
    /// screen and commit the wrong exercises.
    static func slug(planID: String, workoutID: String) -> String {
        "\(planID)/\(workoutID)"
    }
}

// MARK: - Category → colour mapping (robust to unknown tags)

extension String {
    /// A stable colour per muscle-group tag. Synonyms are folded first, so a
    /// plan that says "Posture" and a plan that says "Upper Back" get the same
    /// colour instead of two unrelated ones.
    var categoryColor: Color {
        switch CategoryMap.canonical(self).lowercased() {
        case "legs":             return .indigo
        case "back":             return .blue
        case "chest":            return .red
        case "shoulders":        return .orange
        case "arms":             return .purple
        case "core":             return .teal
        case "posture":          return .green      // keep — old logged data uses it
        case "upper back":       return .green
        case "forearms":         return .brown
        case "calves":           return .mint
        case "grip":             return .cyan
        case "mobility":         return .yellow
        case "posterior chain":  return .pink
        default:                 return .gray
        }
    }
}
