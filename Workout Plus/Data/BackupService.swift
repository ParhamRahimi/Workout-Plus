// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  BackupService.swift
//  Workout Plus
//
//

import Foundation
import os
import SwiftData

// DTOs — @Model types aren't Codable, so we mirror them.
// New fields are Optional so a version-2 backup file still decodes: synthesized
// Decodable does NOT fall back to default values for missing keys.
struct SetDTO: Codable {
    var exerciseName: String
    var category: String
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var isTimed: Bool
    var substitutedFor: String?
    var orderIndex: Int?
    var id: UUID?
    var isAssisted: Bool?
    var isBodyweight: Bool?
    var exerciseID: String?
    var isWarmup: Bool?
    var rir: Int?
    var targetLow: Int?
    var targetHigh: Int?
    var note: String?
    var performedAt: Date?
}

struct SessionDTO: Codable {
    var id: UUID
    var date: Date
    var endDate: Date?
    var workoutID: String
    var workoutName: String
    var bodyweightKgAtTime: Double?
    var healthKitUUID: String?
    var planID: String?
    var notes: String?
    var sets: [SetDTO]
}

struct BodyStatDTO: Codable {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var note: String
    var syncedToHealth: Bool?
    var healthKitUUID: String?
}

struct BackupFile: Codable {
    var version = 4
    var exportedAt = Date()
    var plans: [Plan]
    var sessions: [SessionDTO]
    var bodyStats: [BodyStatDTO]
}

enum BackupService {

    static func makeBackup(plans: [Plan],
                           sessions: [WorkoutSession],
                           stats: [BodyStat]) -> BackupFile {
        let s = sessions.map { session in
            SessionDTO(
                id: session.id, date: session.date, endDate: session.endDate,
                workoutID: session.workoutID, workoutName: session.workoutName,
                bodyweightKgAtTime: session.bodyweightKgAtTime,
                healthKitUUID: session.healthKitUUID,
                planID: session.planID,
                notes: session.notes,
                sets: session.sets
                    .sorted { ($0.orderIndex, $0.exerciseName, $0.setNumber)
                                < ($1.orderIndex, $1.exerciseName, $1.setNumber) }
                    .map {
                        SetDTO(exerciseName: $0.exerciseName, category: $0.category,
                               setNumber: $0.setNumber, weightKg: $0.weightKg,
                               reps: $0.reps, seconds: $0.seconds,
                               isTimed: $0.isTimed, substitutedFor: $0.substitutedFor,
                               orderIndex: $0.orderIndex, id: $0.id, isAssisted: $0.isAssisted, isBodyweight: $0.isBodyweight, exerciseID: $0.exerciseID, isWarmup: $0.isWarmup,
                               rir: $0.rir, targetLow: $0.targetLow,
                               targetHigh: $0.targetHigh, note: $0.note,
                               performedAt: $0.performedAt)
                    }
            )
        }
        let b = stats.map {
            BodyStatDTO(id: $0.id, date: $0.date, weightKg: $0.weightKg,
                        waistCm: $0.waistCm, note: $0.note, syncedToHealth: $0.syncedToHealth, healthKitUUID: $0.healthKitUUID)
        }
        return BackupFile(plans: plans, sessions: s, bodyStats: b)
    }

    static func encode(_ backup: BackupFile) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601
        do {
            return try enc.encode(backup)
        } catch {
            Log.data.error("Encoding the backup failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Restores anything not already present (dedupes by id). Non-destructive.
    @discardableResult
    static func restore(from data: Data,
                        context: ModelContext,
                        existingSessionIDs: Set<UUID>,
                        existingStatIDs: Set<UUID>,
                        planStore: PlanStore) throws -> (sessions: Int, stats: Int, plans: Int) {
        try ImportLimits.check(data, maximum: ImportLimits.backupBytes)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let backup = try dec.decode(BackupFile.self, from: data)
        try validate(backup)
        // Flush unrelated pending edits before starting an isolated restore.
        try context.save()
        let restoreContext = ModelContext(context.container)
        restoreContext.autosaveEnabled = false
        let currentSessions = Set(try restoreContext.fetch(FetchDescriptor<WorkoutSession>()).map(\.id))
        let currentStats = Set(try restoreContext.fetch(FetchDescriptor<BodyStat>()).map(\.id))
        let cleanPlans = try backup.plans.map(PlanValidator.validated)
        let newPlans = cleanPlans.filter { p in !planStore.plans.contains { $0.id == p.id } }
        // Plans persist as one atomic file before the database transaction. A crash
        // between stores is recoverable: retry skips plans/records already present.
        if !newPlans.isEmpty { try planStore.replacePlans(planStore.plans + newPlans) }
        do {
            for s in backup.sessions where !currentSessions.contains(s.id) {
                let session = WorkoutSession(date: s.date, workoutID: s.workoutID, workoutName: s.workoutName, planID: s.planID ?? "")
                session.id = s.id
                session.endDate = s.endDate
                session.bodyweightKgAtTime = s.bodyweightKgAtTime
                session.healthKitUUID = s.healthKitUUID
                session.notes = s.notes ?? ""
                restoreContext.insert(session)
                for (index, d) in s.sets.enumerated() {
                    let e = SetEntry(exerciseName: d.exerciseName, category: d.category, setNumber: d.setNumber, weightKg: d.weightKg, reps: d.reps, seconds: d.seconds, isTimed: d.isTimed, orderIndex: d.orderIndex ?? index, isWarmup: d.isWarmup ?? false, isAssisted: d.isAssisted ?? ExerciseTemplate.nameImpliesAssistance(d.exerciseName), rir: d.rir, targetLow: d.targetLow ?? 0, targetHigh: d.targetHigh ?? 0)
                    if let id = d.id { e.id = id }
                    e.isBodyweight = d.isBodyweight
                    e.exerciseID = d.exerciseID ?? ""
                    e.substitutedFor = d.substitutedFor
                    e.note = d.note ?? ""
                    e.performedAt = d.performedAt
                    e.session = session
                    restoreContext.insert(e)
                }
            }
            for b in backup.bodyStats where !currentStats.contains(b.id) {
                let stat = BodyStat(date: b.date, weightKg: b.weightKg, waistCm: b.waistCm, photoFilename: nil, note: b.note)
                stat.id = b.id
                stat.syncedToHealth = b.syncedToHealth ?? false
                stat.healthKitUUID = b.healthKitUUID
                restoreContext.insert(stat)
            }
            try restoreContext.save()
        } catch {
            restoreContext.rollback()
            throw PlanValidationError(problems: ["Workout/body records were not restored. Any imported plans are preserved. Retry the same backup after resolving storage problems; existing IDs are skipped."])
        }
        return (backup.sessions.filter { !currentSessions.contains($0.id) }.count,
                backup.bodyStats.filter { !currentStats.contains($0.id) }.count, newPlans.count)
    }

    static func validate(_ backup: BackupFile) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw PlanValidationError(problems: [message]) }
        }
        try require((2...4).contains(backup.version), "Unsupported backup version. Use a version 2–4 backup.")
        try require(backup.plans.count <= 100 && backup.sessions.count <= 20000 && backup.bodyStats.count <= 20000, "Backup has too many records.")
        try require(Set(backup.sessions.map(\.id)).count == backup.sessions.count && Set(backup.bodyStats.map(\.id)).count == backup.bodyStats.count && Set(backup.plans.map(\.id)).count == backup.plans.count, "Backup contains duplicate record IDs.")
        for p in backup.plans { _ = try PlanValidator.validated(p) }
        var setIDs = Set<UUID>()
        for s in backup.sessions {
            try require(s.workoutName.count <= 200 && s.workoutID.count <= 100 && (s.notes?.count ?? 0) <= 8000 && s.sets.count <= 1000, "Invalid session text or set count.")
            try require(s.endDate == nil || (s.endDate! >= s.date && s.endDate!.timeIntervalSince(s.date) <= 7 * 86400), "Invalid session duration.")
            if let kg = s.bodyweightKgAtTime { try require(kg.isFinite && (1...1000).contains(kg), "Invalid session bodyweight.") }
            for e in s.sets {
                if let id = e.id { try require(setIDs.insert(id).inserted, "Backup contains duplicate set IDs.") }
                try require(e.weightKg.isFinite && (0...5000).contains(e.weightKg) && (0...1000).contains(e.reps) && (0...86400).contains(e.seconds) && (1...1000).contains(e.setNumber) && (0...1000).contains(e.orderIndex ?? 0), "Invalid set values.")
                try require((e.rir == nil || (0...10).contains(e.rir!)) && (0...86400).contains(e.targetLow ?? 0) && (0...86400).contains(e.targetHigh ?? 0), "Invalid set effort or targets.")
                try require(!e.exerciseName.isEmpty && e.exerciseName.count <= 200 && e.category.count <= 100 && (e.note?.count ?? 0) <= 8000 && (e.exerciseID?.count ?? 0) <= 200 && (e.substitutedFor?.count ?? 0) <= 200, "Invalid set text.")
            }
        }
        for b in backup.bodyStats {
            try require(b.note.count <= 8000, "Body note is too long.")
            if let kg = b.weightKg { try require(kg.isFinite && (1...1000).contains(kg), "Invalid bodyweight.") }
            if let cm = b.waistCm { try require(cm.isFinite && (1...500).contains(cm), "Invalid waist measurement.") }
        }
    }
}
