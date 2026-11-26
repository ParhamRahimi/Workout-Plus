// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  SetPrefill.swift
//  Workout Plus
//
//  Everything the log sheet needs to open pre-filled, in one place — so the
//  same numbers can also be committed WITHOUT opening the sheet ("log as
//  suggested" from the exercise list), which is the difference between six taps
//  per exercise and one.
//
//  It also fixes the fetch: this used to pull EVERY session and walk every set
//  in your history, synchronously, while the sheet was animating in. The
//  predicate pushes the filtering into the store, so it only ever touches
//  sessions that actually contain this exercise.
//

import Foundation
import os
import SwiftData

struct SetPrefill {
    var sets: [DraftSet]
    var lastSummary: String?
    var suggestion: ProgressionService.Suggestion?
    var bests: (weight: Double, reps: Int, volume: Double, seconds: Int)
    var hasHistory: Bool
    /// How last session's working sets were tagged, and at what load. Shown as
    /// a fact about the past — never written into this session's effort tag.
    var lastEffortLabel: String?
    var lastWorkingWeight: Double?
}

enum SetPrefillService {

    /// Wheel grids, shared with the log sheet so a pre-filled value is always
    /// selectable.
    static let weightStep = 0.5
    static let maxWeight = 300.0
    static let maxReps = 60
    static let secondsStep = 5
    static let maxSeconds = 300

    static func snapWeight(_ w: Double) -> Double {
        w
    }
    static func snapReps(_ r: Int) -> Int { r }
    static func snapSeconds(_ s: Int) -> Int {
        s
    }

    static func make(for effective: ExerciseTemplate, context: ModelContext, bodyStats: [BodyStat] = []) -> SetPrefill {
        let name = effective.name
        let stableID = effective.id
        // Includes any older name this exercise used to be logged under (e.g.
        // "Assisted Pull-up" before it became "Pull-up"), so history from
        // before a rename still counts as "last time" and feeds the prefill.
        let names = ExerciseTemplate.namesForHistory(name)
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.sets.contains(where: { names.contains($0.exerciseName) || $0.exerciseID == stableID })
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.sets]

        let sessions: [WorkoutSession]
        do {
            sessions = try context.fetch(descriptor)
        } catch {
            Log.data.error("Prefill fetch failed: \(error.localizedDescription, privacy: .private)")
            // Bounded fallback: if the predicate can't be translated we still
            // shouldn't pull every session ever logged onto the main thread
            // while a sheet is animating in.
            var fallback = FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            fallback.fetchLimit = 200
            fallback.relationshipKeyPathsForPrefetching = [\.sets]
            sessions = (try? context.fetch(fallback)) ?? []
        }

        let usesBodyweight = effective.loadIsBodyweight && !effective.isTimed
        let bests = PRService.bests(exerciseName: name, exerciseID: stableID, usesBodyweight: usesBodyweight, in: sessions, bodyStats: bodyStats)

        // Most recent session containing this exercise.
        var last: [SetEntry] = []
        for session in sessions {
            let matching = session.sets
                .filter { names.contains($0.exerciseName) || $0.exerciseID == stableID }
                .sorted { $0.setNumber < $1.setNumber }
            if !matching.isEmpty { last = matching; break }
        }

        let suggestion = ProgressionService.suggest(template: effective, lastSets: last, bodyStats: bodyStats)

        var sets: [DraftSet]
        var lastSummary: String?

        if last.isEmpty {
            sets = (0..<max(effective.sets, 1)).map { _ in DraftSet() }
        } else {
            sets = last.map {
                DraftSet(weightKg: snapWeight($0.weightKg),
                         reps: snapReps($0.reps),
                         seconds: snapSeconds($0.seconds),
                         isWarmup: $0.isWarmup,
                         isAssisted: $0.resolvedIsAssisted)
            }
            lastSummary = last.filter { !$0.isWarmup }.map(\.summary).joined(separator: ",  ")

            // Pre-set the wheels when it's time to progress. The default is a
            // top-set probe — hold the working weight, test the jump on the
            // last set — because a jump that turns out to be too big then costs
            // you one set instead of the whole exercise. One tap in the sheet
            // takes it across every set instead.
            if !effective.isTimed, let s = suggestion, s.isReady,
               let base = s.baseWeight, let probe = s.probeWeight {
                let working = sets.indices.filter { !sets[$0].isWarmup }
                for i in working { sets[i].weightKg = snapWeight(base) }
                if let last = working.last { sets[last].weightKg = snapWeight(probe) }
            } else if let s = suggestion, let w = s.suggestedWeight, !effective.isTimed {
                let snapped = snapWeight(w)
                for i in sets.indices where !sets[i].isWarmup {
                    sets[i].weightKg = snapped
                    sets[i].isAssisted = s.suggestedIsAssisted
                }
            }
        }

        let lastWorking = last.filter { !$0.isWarmup }
        let lastEffort = ProgressionService.Effort(sets: lastWorking)
        // Per-set truth, not a fixed exercise-wide flag: whatever regime the
        // last session was actually logged in.
        let lastRegimeAssisted = lastWorking.first?.resolvedIsAssisted ?? false

        return SetPrefill(sets: sets,
                          lastSummary: lastSummary,
                          suggestion: suggestion,
                          bests: bests,
                          hasHistory: !last.isEmpty,
                          lastEffortLabel: lastEffort.label,
                          lastWorkingWeight: lastRegimeAssisted
                            ? lastWorking.map(\.weightKg).min()
                            : lastWorking.map(\.weightKg).max())
    }
}
