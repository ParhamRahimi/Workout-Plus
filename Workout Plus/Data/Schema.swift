// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  Schema.swift
//  Workout Plus
//
//  Versioned schema + migration plan.
//
//  Frozen legacy shapes support upgrades without replacing the user store.
//

import Foundation
import os
import SwiftData

// Legacy schemas are frozen: never change their persisted model definitions.
// Frozen pre-assisted-loading model. Some older builds used this shape while
// still reporting schema 1.0.0; migration recognizes its persisted model checksum.
enum WorkoutPlusSchemaV0: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(0, 9, 0) }
    static var models: [any PersistentModel.Type] { [WorkoutSession.self, SetEntry.self, BodyStat.self] }

/// One logged training session: "on this date I did Workout B."
@Model
final class WorkoutSession {
    var id: UUID
    var date: Date              // start time
    var endDate: Date?          // finish time (nil while in progress)
    var workoutID: String       // "A" / "B" / "C" — only unique WITHIN a plan
    var workoutName: String
    /// Which plan this session came from. Without it, history can't be
    /// attributed and "what's next in the rotation" reads sessions from plans
    /// you aren't running any more.
    var planID: String = ""
    var healthKitUUID: String?   // nil = not yet synced
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    var sets: [SetEntry]

    init(date: Date = .now, workoutID: String, workoutName: String, planID: String = "") {
        self.id = UUID()
        self.date = date
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.planID = planID
        self.sets = []
    }

    var durationText: String? {
        guard let endDate else { return nil }
        let secs = Int(endDate.timeIntervalSince(date))
        guard secs > 0 else { return nil }
        return Duration.seconds(secs)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Sets that count towards PRs, volume and stall detection.
    var workingSets: [SetEntry] { sets.filter { !$0.isWarmup } }

    /// Bodyweight to use for this session's bodyweight-relative sets: the
    /// value stamped at Finish, or — for history logged before that existed —
    /// the nearest `BodyStat` by date. nil only when neither exists.
    func resolvedBodyweightKg(bodyStats: [BodyStat]) -> Double? {
        return bodyStats
            .filter { $0.weightKg != nil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .weightKg
    }
}

/// One logged set within a session.
@Model
final class SetEntry {
    var id: UUID
    var exerciseName: String
    var category: String
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int             // used when isTimed == true (e.g. plank)
    var isTimed: Bool
    var substitutedFor: String?      // set when this lift stood in for a planned one

    /// Position of this exercise within the workout. `SetEntry` had no ordering
    /// field, so a finished session could only ever be redisplayed
    /// alphabetically — the order you actually trained in was unrecoverable.
    var orderIndex: Int = 0
    /// Warm-ups were being logged as working sets, inflating weekly volume and
    /// occasionally registering a heavy single as a PR.
    var isWarmup: Bool = false
    /// True when `weightKg` is help subtracted from bodyweight (an assist
    /// machine or band) rather than load added to it. Per-SET, not per
    /// exercise — a pull-up moves from assisted to plain bodyweight to
    /// weighted over a training life, and this is what lets one exercise
    /// track that whole arc instead of needing three. Only meaningful when
    /// the exercise is bodyweight-relative (`ExerciseTemplate.loadIsBodyweight`).
    /// Reps in reserve, 0 = went to failure. Optional because it is always the
    /// user's choice to record it. The progression rule is "top of the range
    /// with clean form" and this is the only thing that carries "clean form".
    var rir: Int?
    /// The prescription this set was performed against, captured at the time.
    /// Edit the plan later and history can still be read against what was
    /// actually asked for.
    var targetLow: Int = 0
    var targetHigh: Int = 0
    var note: String = ""
    /// When this set was finished. Optional because sets logged before the app
    /// recorded timings — and sets restored from an older backup — don't have it.
    var performedAt: Date?

    var session: WorkoutSession?

    init(exerciseName: String, category: String, setNumber: Int,
         weightKg: Double, reps: Int, seconds: Int, isTimed: Bool,
         orderIndex: Int = 0, isWarmup: Bool = false,
         rir: Int? = nil, targetLow: Int = 0, targetHigh: Int = 0) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.category = category
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.isTimed = isTimed
        self.orderIndex = orderIndex
        self.isWarmup = isWarmup
        self.rir = rir
        self.targetLow = targetLow
        self.targetHigh = targetHigh
    }

    /// "40 × 12" or "45 sec" for display.
    var summary: String {
        if isTimed { return "\(seconds) sec" }
        let w = weightKg.formatted(.number.precision(.fractionLength(0...1)))
        return "\(w) × \(reps)"
    }

    /// "easy" / "hard" / "to failure", or nil when not recorded.
    var effortText: String? {
        guard let rir else { return nil }
        switch rir {
        case ...0:  return "to failure"
        case 1:     return "hard"
        default:    return "easy"
        }
    }

    /// Corrects for history logged before the per-set `isAssisted` flag
    /// existed. Lightweight migration defaults every pre-existing row to
    /// `false`, which is silently wrong for anything actually logged under
    /// an assist-machine name (e.g. the old "Assisted Pull-up") — those were
    /// always assistance under the app's old, exercise-wide model, and the
    /// raw name it was logged under is the only ground truth that survives.
    /// A genuinely new entry is unaffected: `isAssisted` alone already
    /// carries its truth. Every place that computes effective load from
    /// STORED history should read this instead of `isAssisted` directly —
    /// a live `DraftSet`'s toggle never needs the correction.
    var resolvedIsAssisted: Bool {
        ExerciseTemplate.nameImpliesAssistance(exerciseName)
    }
}

@Model
final class BodyStat {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var photoFilename: String?
    var note: String
    var syncedToHealth: Bool = false

    init(date: Date = .now,
         weightKg: Double? = nil,
         waistCm: Double? = nil,
         photoFilename: String? = nil,
         note: String = "") {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.photoFilename = photoFilename
        self.note = note
    }

    var weightText: String? {
        guard let weightKg else { return nil }
        return weightKg.formatted(.number.precision(.fractionLength(0...1))) + " kg"
    }

    var waistText: String? {
        guard let waistCm else { return nil }
        return waistCm.formatted(.number.precision(.fractionLength(0...1))) + " cm"
    }
}
}

enum WorkoutPlusSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [WorkoutSession.self, SetEntry.self, BodyStat.self] }

/// One logged training session: "on this date I did Workout B."
@Model
final class WorkoutSession {
    var id: UUID
    var date: Date              // start time
    var endDate: Date?          // finish time (nil while in progress)
    var workoutID: String       // "A" / "B" / "C" — only unique WITHIN a plan
    var workoutName: String
    /// Which plan this session came from. Without it, history can't be
    /// attributed and "what's next in the rotation" reads sessions from plans
    /// you aren't running any more.
    var planID: String = ""
    var healthKitUUID: String?   // nil = not yet synced
    var notes: String = ""
    /// Your bodyweight when this session was performed, resolved once at
    /// Finish and reused for every bodyweight-relative set it contains (it
    /// doesn't change mid-workout). nil for sessions with no bodyweight
    /// exercise, and for history logged before this field existed — those
    /// fall back to the nearest `BodyStat` by date.
    var bodyweightKgAtTime: Double?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    var sets: [SetEntry]

    init(date: Date = .now, workoutID: String, workoutName: String, planID: String = "") {
        self.id = UUID()
        self.date = date
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.planID = planID
        self.sets = []
    }

    var durationText: String? {
        guard let endDate else { return nil }
        let secs = Int(endDate.timeIntervalSince(date))
        guard secs > 0 else { return nil }
        return Duration.seconds(secs)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Sets that count towards PRs, volume and stall detection.
    var workingSets: [SetEntry] { sets.filter { !$0.isWarmup } }

    /// Bodyweight to use for this session's bodyweight-relative sets: the
    /// value stamped at Finish, or — for history logged before that existed —
    /// the nearest `BodyStat` by date. nil only when neither exists.
    func resolvedBodyweightKg(bodyStats: [BodyStat]) -> Double? {
        if let bodyweightKgAtTime { return bodyweightKgAtTime }
        return bodyStats
            .filter { $0.weightKg != nil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .weightKg
    }
}

/// One logged set within a session.
@Model
final class SetEntry {
    var id: UUID
    var exerciseName: String
    var category: String
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int             // used when isTimed == true (e.g. plank)
    var isTimed: Bool
    var substitutedFor: String?      // set when this lift stood in for a planned one

    /// Position of this exercise within the workout. `SetEntry` had no ordering
    /// field, so a finished session could only ever be redisplayed
    /// alphabetically — the order you actually trained in was unrecoverable.
    var orderIndex: Int = 0
    /// Warm-ups were being logged as working sets, inflating weekly volume and
    /// occasionally registering a heavy single as a PR.
    var isWarmup: Bool = false
    /// True when `weightKg` is help subtracted from bodyweight (an assist
    /// machine or band) rather than load added to it. Per-SET, not per
    /// exercise — a pull-up moves from assisted to plain bodyweight to
    /// weighted over a training life, and this is what lets one exercise
    /// track that whole arc instead of needing three. Only meaningful when
    /// the exercise is bodyweight-relative (`ExerciseTemplate.loadIsBodyweight`).
    var isAssisted: Bool = false
    /// Reps in reserve, 0 = went to failure. Optional because it is always the
    /// user's choice to record it. The progression rule is "top of the range
    /// with clean form" and this is the only thing that carries "clean form".
    var rir: Int?
    /// The prescription this set was performed against, captured at the time.
    /// Edit the plan later and history can still be read against what was
    /// actually asked for.
    var targetLow: Int = 0
    var targetHigh: Int = 0
    var note: String = ""
    /// When this set was finished. Optional because sets logged before the app
    /// recorded timings — and sets restored from an older backup — don't have it.
    var performedAt: Date?

    var session: WorkoutSession?

    init(exerciseName: String, category: String, setNumber: Int,
         weightKg: Double, reps: Int, seconds: Int, isTimed: Bool,
         orderIndex: Int = 0, isWarmup: Bool = false, isAssisted: Bool = false,
         rir: Int? = nil, targetLow: Int = 0, targetHigh: Int = 0) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.category = category
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.isTimed = isTimed
        self.orderIndex = orderIndex
        self.isWarmup = isWarmup
        self.isAssisted = isAssisted
        self.rir = rir
        self.targetLow = targetLow
        self.targetHigh = targetHigh
    }

    /// "40 × 12" or "45 sec" for display.
    var summary: String {
        if isTimed { return "\(seconds) sec" }
        let w = weightKg.formatted(.number.precision(.fractionLength(0...1)))
        return "\(w) × \(reps)"
    }

    /// "easy" / "hard" / "to failure", or nil when not recorded.
    var effortText: String? {
        guard let rir else { return nil }
        switch rir {
        case ...0:  return "to failure"
        case 1:     return "hard"
        default:    return "easy"
        }
    }

    /// Corrects for history logged before the per-set `isAssisted` flag
    /// existed. Lightweight migration defaults every pre-existing row to
    /// `false`, which is silently wrong for anything actually logged under
    /// an assist-machine name (e.g. the old "Assisted Pull-up") — those were
    /// always assistance under the app's old, exercise-wide model, and the
    /// raw name it was logged under is the only ground truth that survives.
    /// A genuinely new entry is unaffected: `isAssisted` alone already
    /// carries its truth. Every place that computes effective load from
    /// STORED history should read this instead of `isAssisted` directly —
    /// a live `DraftSet`'s toggle never needs the correction.
    var resolvedIsAssisted: Bool {
        isAssisted || ExerciseTemplate.nameImpliesAssistance(exerciseName)
    }
}

@Model
final class BodyStat {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var photoFilename: String?
    var note: String
    var syncedToHealth: Bool = false

    init(date: Date = .now,
         weightKg: Double? = nil,
         waistCm: Double? = nil,
         photoFilename: String? = nil,
         note: String = "") {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.photoFilename = photoFilename
        self.note = note
    }

    var weightText: String? {
        guard let weightKg else { return nil }
        return weightKg.formatted(.number.precision(.fractionLength(0...1))) + " kg"
    }

    var waistText: String? {
        guard let waistCm else { return nil }
        return waistCm.formatted(.number.precision(.fractionLength(0...1))) + " cm"
    }
}
}

enum WorkoutPlusSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [WorkoutSession.self, SetEntry.self, BodyStat.self] }
}

enum WorkoutPlusMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [WorkoutPlusSchemaV0.self, WorkoutPlusSchemaV1.self, WorkoutPlusSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: WorkoutPlusSchemaV0.self, toVersion: WorkoutPlusSchemaV1.self), .lightweight(fromVersion: WorkoutPlusSchemaV1.self, toVersion: WorkoutPlusSchemaV2.self)] }
}

/// Opening failure never creates a writable substitute for the user's store.
enum PersistenceSetup {
    nonisolated(unsafe) static private(set) var failureMessage: String?
    static func makeContainer() -> ModelContainer? {
        failureMessage = nil
        let schema = Schema(versionedSchema: WorkoutPlusSchemaV2.self)
        do {
            return try ModelContainer(for: schema, migrationPlan: WorkoutPlusMigrationPlan.self,
                                      configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
        } catch {
            Log.data.error("Persistent store failed: \(error.localizedDescription, privacy: .private)")
            failureMessage = "Your saved data could not be opened. Logging is disabled to protect it. Quit and reopen the app. If this continues, contact support; do not uninstall the app or delete its data."
            return nil
        }
    }
}
