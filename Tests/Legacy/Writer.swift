// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import SwiftData


@Model
final class WorkoutSession {
    var id: UUID
    var date: Date              // start time
    var endDate: Date?          // finish time (nil while in progress)
    var workoutID: String       // "A" / "B" / "C" — only unique WITHIN a plan
    var workoutName: String
    var planID: String = ""
    var healthKitUUID: String?   // nil = not yet synced
    var notes: String = ""
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

    var workingSets: [SetEntry] { sets.filter { !$0.isWarmup } }

    func resolvedBodyweightKg(bodyStats: [BodyStat]) -> Double? {
        if let bodyweightKgAtTime { return bodyweightKgAtTime }
        return bodyStats
            .filter { $0.weightKg != nil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .weightKg
    }
}

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

    var orderIndex: Int = 0
    var isWarmup: Bool = false
    var isAssisted: Bool = false
    var rir: Int?
    var targetLow: Int = 0
    var targetHigh: Int = 0
    var note: String = ""
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

    var summary: String {
        if isTimed { return "\(seconds) sec" }
        let w = weightKg.formatted(.number.precision(.fractionLength(0...1)))
        return "\(w) × \(reps)"
    }

    var effortText: String? {
        guard let rir else { return nil }
        switch rir {
        case ...0:  return "to failure"
        case 1:     return "hard"
        default:    return "easy"
        }
    }

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
enum WorkoutPlusSchemaV1: VersionedSchema {
 static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
 static var models: [any PersistentModel.Type] { [WorkoutSession.self, SetEntry.self, BodyStat.self] }
}
@main struct LegacyWriter {
 @MainActor static func main() throws {
  let schema = Schema(versionedSchema: WorkoutPlusSchemaV1.self)
  let config = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]))
  let container = try ModelContainer(for: schema, configurations: [config])
  let context = ModelContext(container)
  let session = WorkoutSession(workoutID: "A", workoutName: "Synthetic legacy session")
  session.bodyweightKgAtTime = 80
  let entry = SetEntry(exerciseName: "Pull-up", category: "Back", setNumber: 1, weightKg: 10, reps: 8, seconds: 0, isTimed: false, isAssisted: true)
  entry.session = session; context.insert(session); context.insert(entry); try context.save()
 }
}
