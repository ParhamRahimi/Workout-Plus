// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import SwiftData
import Darwin

@main
struct Checks {
    @MainActor
    static func main() throws {
        setbuf(stdout, nil)
        var count = 0
        func check(_ result: @autoclosure () -> Bool, _ name: String) throws {
            guard result() else { throw NSError(domain: "Checks", code: 1, userInfo: [NSLocalizedDescriptionKey: "FAILED: " + name]) }
            count += 1
            print("PASS: " + name)
        }
        func rejects(_ name: String, _ work: () throws -> Void) throws {
            do { try work() } catch { try check(true, name); return }
            try check(false, name)
        }
        let export = ExportService.writeTempFile(named: "synthetic.csv", contents: "synthetic only")
        try check(export != nil && FileManager.default.fileExists(atPath: export!.path), "temporary export is created")
        try ExportService.eraseFiles()
        try check(!FileManager.default.fileExists(atPath: export!.path), "temporary exports can be fully removed")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = try Data(contentsOf: root.appendingPathComponent("Examples/minimal-plan.json"))
        let minimal = try JSONDecoder().decode(Plan.self, from: fixture)
        _ = try PlanValidator.validated(minimal)
        try check(true, "minimal example is accepted")
        let full = try Data(contentsOf: root.appendingPathComponent("Examples/three-day-full-body.json"))
        _ = try PlanValidator.validated(JSONDecoder().decode(Plan.self, from: full))
        let bundled = try Data(contentsOf: root.appendingPathComponent("Workout Plus/starter-plan.json"))
        try check(full == bundled, "bundled starter equals published plan")
        var huge = minimal
        huge.workouts[0].exercises[0].sets = Int.max
        try rejects("unbounded sets rejected") { _ = try PlanValidator.validated(huge) }
        for bad in ["https://evil.example/a.jpg", "https://u:p@raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/X/0.jpg", "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/X/0.jpg?secret=x", "https://raw.githubusercontent.com.evil.example/a.jpg", "http://127.0.0.1/a.jpg"] {
            try check(!PlanValidator.isAllowedImageURL(bad), "unsafe image URL rejected")
        }
        try rejects("oversized import rejected") { try ImportLimits.check(Data(repeating: 0, count: ImportLimits.planBytes + 1), maximum: ImportLimits.planBytes) }
        try check(ExportService.field(" \t=1+1").hasPrefix("\"'"), "CSV formula injection neutralized")
        try check(ExportService.field("ordinary, text") == "\"ordinary, text\"", "ordinary CSV quoting preserved")
        let temporary = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WORKOUT_CHECK_DIR"] ?? "/private/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let plans = PlanStore(fileURL: temporary.appendingPathComponent("plans.json"))
        _ = try plans.importPlan(from: fixture)
        let schema = Schema(versionedSchema: WorkoutPlusSchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let session = WorkoutSession(workoutID: "A", workoutName: "Synthetic", planID: minimal.id)
        session.bodyweightKgAtTime = 80
        let entry = SetEntry(exerciseName: "Pull-up", category: "Back", setNumber: 1, weightKg: 10, reps: 8, seconds: 0, isTimed: false, isAssisted: true)
        entry.exerciseID = "stable-pull-up"
        entry.isBodyweight = true
        entry.session = session
        context.insert(session); context.insert(entry)
        let stat = BodyStat(weightKg: 80, note: "Synthetic fixture")
        stat.syncedToHealth = true
        stat.healthKitUUID = UUID().uuidString
        context.insert(stat)
        try context.save()
        let backup = BackupService.makeBackup(plans: [minimal], sessions: [session], stats: [stat])
        let encoded = BackupService.encode(backup)!
        let destination = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let target = ModelContext(destination)
        let result = try BackupService.restore(from: encoded, context: target, existingSessionIDs: [], existingStatIDs: [], planStore: plans)
        let restored = try target.fetch(FetchDescriptor<WorkoutSession>()).first!
        let restoredStat = try target.fetch(FetchDescriptor<BodyStat>()).first!
        try check(result.sessions == 1 && restored.bodyweightKgAtTime == 80 && restored.sets.first?.isAssisted == true && restored.sets.first?.isBodyweight == true && restored.sets.first?.exerciseID == "stable-pull-up", "backup preserves load interpretation and identity")
        let renamed = PRService.bests(exerciseName: "Renamed exercise", exerciseID: "stable-pull-up", usesBodyweight: true, in: [restored])
        try check(renamed.weight == 70 && renamed.reps == 8, "stable exercise identity preserves history after rename")
        try check(restoredStat.syncedToHealth && restoredStat.healthKitUUID == stat.healthKitUUID, "backup preserves linked Health state")
        let twice = try BackupService.restore(from: encoded, context: target, existingSessionIDs: [], existingStatIDs: [], planStore: plans)
        try check(twice.sessions == 0 && twice.stats == 0, "repeated restore deduplicates from actual store")
        var duplicate = backup; duplicate.sessions.append(duplicate.sessions[0])
        try rejects("duplicate IDs rejected before mutation") { try BackupService.validate(duplicate) }
        var future = backup; future.version = 999
        try rejects("future backup version rejected") { try BackupService.validate(future) }
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["version"] = 2
        var sessions = legacy["sessions"] as! [[String: Any]]
        sessions[0].removeValue(forKey: "bodyweightKgAtTime")
        var entries = sessions[0]["sets"] as! [[String: Any]]
        for key in ["id", "isAssisted", "isBodyweight", "exerciseID"] { entries[0].removeValue(forKey: key) }
        sessions[0]["sets"] = entries; legacy["sessions"] = sessions
        let legacyDecoder = JSONDecoder(); legacyDecoder.dateDecodingStrategy = .iso8601
        let old = try legacyDecoder.decode(BackupFile.self, from: JSONSerialization.data(withJSONObject: legacy))
        try BackupService.validate(old)
        try check(true, "version 2 backup remains readable")
        let blocked = PlanStore(fileURL: temporary) // an existing directory cannot be decoded/written as plans.json
        let before = blocked.plans
        try rejects("failed plan persistence throws") { _ = try blocked.importPlan(from: fixture) }
        try check(blocked.plans == before && blocked.loadFailed, "failed/corrupt plan file is preserved")
        if let previous = ProcessInfo.processInfo.environment["WORKOUT_LEGACY_STORE"] {
            let oldConfig = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: previous))
            let migrated = try ModelContainer(for: schema, migrationPlan: WorkoutPlusMigrationPlan.self, configurations: [oldConfig])
            let records = try ModelContext(migrated).fetch(FetchDescriptor<WorkoutSession>())
            try check(records.count == 1 && records[0].bodyweightKgAtTime == 80 && records[0].sets.first?.isAssisted == true, "actual previous global-model store upgrades without losing history")
        }
        if let oldest = ProcessInfo.processInfo.environment["WORKOUT_OLDEST_STORE"] {
            let config = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: oldest))
            let container = try ModelContainer(for: schema, migrationPlan: WorkoutPlusMigrationPlan.self, configurations: [config])
            let records = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
            try check(records.count == 1 && records[0].sets.count == 1 && records[0].sets[0].weightKg == 10 && records[0].sets[0].reps == 8 && records[0].bodyweightKgAtTime == nil, "oldest global-model store reporting 1.0 upgrades with records and relationships intact")
        }
        // A read-only persistent store forces an actual restore-save failure.
        let readOnlyURL = temporary.appendingPathComponent("readonly.store")
        do {
            let writable = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: readOnlyURL)])
            try ModelContext(writable).save()
        }
        let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: readOnlyURL, allowsSave: false)])
        let readOnlyContext = ModelContext(readOnly)
        try rejects("database save failure is reported by restore") {
            _ = try BackupService.restore(from: encoded, context: readOnlyContext, existingSessionIDs: [], existingStatIDs: [], planStore: plans)
        }
        let remaining = try readOnlyContext.fetchCount(FetchDescriptor<WorkoutSession>())
        try check(remaining == 0, "failed restore rolls back its database inserts")
        let switched = SetEntry(exerciseName: "Assisted Pull-up", category: "Back", setNumber: 1, weightKg: 0, reps: 8, seconds: 0, isTimed: false)
        switched.exerciseID = "stable-pull-up"
        try check(!switched.resolvedIsAssisted, "recorded assistance choice overrides legacy name heuristics")
        // Create a real on-disk legacy store, then open it using the current migration plan.
        let storeURL = temporary.appendingPathComponent("legacy.store")
        do {
            let oldSchema = Schema(versionedSchema: WorkoutPlusSchemaV1.self)
            let oldStore = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: storeURL)])
            let c = ModelContext(oldStore)
            let s = WorkoutPlusSchemaV1.WorkoutSession(workoutID: "A", workoutName: "Legacy synthetic")
            let e = WorkoutPlusSchemaV1.SetEntry(exerciseName: "Pull-up", category: "Back", setNumber: 1, weightKg: 10, reps: 8, seconds: 0, isTimed: false, isAssisted: true)
            e.session = s; c.insert(s); c.insert(e); try c.save()
        }
        let upgraded = try ModelContainer(for: schema, migrationPlan: WorkoutPlusMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        let migrated = try ModelContext(upgraded).fetch(FetchDescriptor<WorkoutSession>())
        try check(migrated.count == 1 && migrated[0].sets.count == 1 && migrated[0].sets[0].isAssisted, "V1 → V2 preserves sessions and relationships")
        print("\(count) checks passed")
    }
}
