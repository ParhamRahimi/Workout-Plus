// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  ExportService.swift
//  Workout Plus
//
//

import Foundation
import os

nonisolated enum ExportService {

    // MARK: CSV builders

    /// One row per logged set — the flat "fact table" shape.
    ///
    /// Rows come out in the order you trained, not alphabetically: sorting by
    /// exercise name threw away the sequence of the session, which is exactly
    /// the thing a training log is for.
    static func setsCSV(_ sessions: [WorkoutSession]) -> String {
        var lines = ["date,plan_id,workout_id,workout_name,duration_min,exercise_order,exercise,category,set_number,is_warmup,is_assisted,is_bodyweight,exercise_id,bodyweight_kg_at_time,weight_kg,reps,seconds,is_timed,rir,target_low,target_high,substituted_for,note"]

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let dateStr = isoDate(session.date)
            let duration = session.endDate.map {
                String(Int($0.timeIntervalSince(session.date) / 60))
            } ?? ""

            let ordered = session.sets.sorted {
                ($0.orderIndex, $0.exerciseName, $0.setNumber)
                    < ($1.orderIndex, $1.exerciseName, $1.setNumber)
            }
            for e in ordered {
                let row = [
                    dateStr,
                    field(session.planID),
                    field(session.workoutID),
                    field(session.workoutName),
                    duration,
                    String(e.orderIndex),
                    field(e.exerciseName),
                    field(e.category),
                    String(e.setNumber),
                    e.isWarmup ? "true" : "false",
                    e.resolvedIsAssisted ? "true" : "false",
                    e.isBodyweight.map { $0 ? "true" : "false" } ?? "",
                    field(e.exerciseID),
                    session.bodyweightKgAtTime.map(num) ?? "",
                    num(e.weightKg),
                    String(e.reps),
                    String(e.seconds),
                    e.isTimed ? "true" : "false",
                    e.rir.map(String.init) ?? "",
                    String(e.targetLow),
                    String(e.targetHigh),
                    field(e.substitutedFor ?? ""),
                    field(e.note)
                ].joined(separator: ",")
                lines.append(row)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One row per body entry.
    static func bodyCSV(_ stats: [BodyStat]) -> String {
        var lines = ["date,weight_kg,waist_cm,has_photo,note"]
        for s in stats.sorted(by: { $0.date < $1.date }) {
            var weightStr = ""
            if let w = s.weightKg { weightStr = num(w) }
            var waistStr = ""
            if let c = s.waistCm { waistStr = num(c) }

            let row = [
                isoDate(s.date),
                weightStr,
                waistStr,
                s.photoFilename == nil ? "false" : "true",
                field(s.note)
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: File writing (temp dir, for ShareLink)

    static func writeTempFile(named name: String, contents: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutPlusExports", isDirectory: true)
        let url = folder.appendingPathComponent(UUID().uuidString + "-" + name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: PrivateFiles.directoryAttributes)
            try Data(contents.utf8).write(to: url, options: PrivateFiles.writeOptions)
            return url
        } catch {
            Log.data.error("Writing \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    static func cleanup() { try? eraseFiles() }

    static func eraseFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutPlusExports")
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        for name in ["workout_sets.csv", "body_stats.csv", "workout-plus-backup.json"] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Helpers

    private static func isoDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }

    private static func num(_ d: Double) -> String {
        // Plain decimal, no locale commas — important for CSV parsing.
        String(format: "%.2f", d)
    }

    /// Quotes and escapes a CSV field.
    static func field(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + s : s
        let escaped = safe.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
