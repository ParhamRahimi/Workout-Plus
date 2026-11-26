// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  StallService.swift
//  Workout Plus
//
//

import Foundation

struct Stall: Identifiable {
    var id: String { exercise }
    let exercise: String
    /// How many consecutive sessions the working set has actually been flat —
    /// the real streak, not the detection threshold.
    let sessionCount: Int
    let weight: Double
    let isTimed: Bool
    /// `weight` is kilos of assistance, not load — a flat line still means
    /// stalled, but it has to be labelled as help.
    let isAssisted: Bool

    /// Detection on its own is just an orange triangle with no way out of it.
    /// Every stall now comes with the next thing to try.
    var suggestedAction: String {
        if isTimed {
            return "Add 5 seconds to one set, or move to a harder variation for a few weeks."
        }
        if isAssisted {
            return "Drop the assist by the smallest notch on the FIRST set only and keep the rest where they are. If that doesn't move, finish each session with 3 slow negatives."
        }
        if weight == 0 {
            return "Bodyweight has nowhere to go but reps and leverage. Slow the lowering to 3 seconds, or move to a harder variation."
        }
        if sessionCount >= 5 {
            return "Five-plus sessions is not a bad week, it's the wrong stimulus. Swap this for a different variation of the same movement for 4–6 weeks, then come back."
        }
        let deload = (weight * 0.9 / 2.5).rounded() * 2.5
        return "Take one lighter week: drop to about \(deload.formatted(.number.precision(.fractionLength(0...1)))) kg, keep the reps easy, then rebuild. Stalls are usually fatigue, not a lack of effort."
    }
}

enum StallService {

    /// Exercises whose working set hasn't moved for `minRepeats` consecutive
    /// sessions. Warm-ups are excluded — a light warm-up single repeated every
    /// week is not a stall, it's a warm-up. Grouped by canonical name, so a
    /// rename (e.g. "Assisted Pull-up" → "Pull-up") doesn't reset the streak.
    static func stalls(in sessions: [WorkoutSession], bodyStats: [BodyStat] = [], minRepeats: Int = 3) -> [Stall] {
        // exercise -> [(date, raw working value, isTimed, isAssisted)] oldest first
        var latestNames: [String: String] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            for e in session.sets where !e.exerciseID.isEmpty { latestNames[e.exerciseID] = ExerciseTemplate.canonicalName(e.exerciseName) }
        }
        var byExercise: [String: [(Date, Double, Bool, Bool)]] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let grouped = Dictionary(grouping: session.workingSets) { latestNames[$0.exerciseID] ?? ExerciseTemplate.canonicalName($0.exerciseName) }
            for (name, entries) in grouped {
                let timed = entries.first?.isTimed ?? false
                let usesBodyweight = !timed && (entries.first?.isBodyweight ?? ExerciseTemplate.nameImpliesBodyweight(name))
                var top: Double
                var isAssistedTop = false

                if timed {
                    top = Double(entries.map(\.seconds).max() ?? 0)
                } else if usesBodyweight, let bw = session.resolvedBodyweightKg(bodyStats: bodyStats) {
                    // The working set is the one with the best EFFECTIVE
                    // load — bigger is always better, in every regime —
                    // reported back in the raw terms you'd actually dial in.
                    let best = entries.max {
                        ExerciseTemplate.effectiveLoad(weightKg: $0.weightKg, isAssisted: $0.resolvedIsAssisted, bodyweightKg: bw)
                        < ExerciseTemplate.effectiveLoad(weightKg: $1.weightKg, isAssisted: $1.resolvedIsAssisted, bodyweightKg: bw)
                    }
                    top = best?.weightKg ?? 0
                    isAssistedTop = best?.resolvedIsAssisted ?? false
                } else {
                    // Legacy fallback: not bodyweight-relative, or no
                    // bodyweight data resolvable yet. Assisted still needs
                    // the least help — read per entry (`resolvedIsAssisted`),
                    // not by name: `name` here is already canonicalized, so
                    // a renamed exercise's old name-based signal would
                    // otherwise be lost.
                    let assisted = entries.first?.resolvedIsAssisted ?? false
                    top = assisted ? (entries.map(\.weightKg).min() ?? 0) : (entries.map(\.weightKg).max() ?? 0)
                    isAssistedTop = assisted
                }
                byExercise[name, default: []].append((session.date, top, timed, isAssistedTop))
            }
        }

        var result: [Stall] = []
        for (name, points) in byExercise where points.count >= minRepeats {
            guard let latest = points.last, latest.1 > 0 else { continue }

            // How far back does the flat run actually go? Same raw number
            // AND same regime — "5 kg assist" and "5 kg added" are not the
            // same set even though the number matches.
            var streak = 0
            for point in points.reversed() {
                if point.1 == latest.1 && point.3 == latest.3 { streak += 1 } else { break }
            }
            guard streak >= minRepeats else { continue }

            result.append(Stall(exercise: name,
                                sessionCount: streak,
                                weight: latest.1,
                                isTimed: latest.2,
                                isAssisted: latest.3))
        }
        return result.sorted { $0.exercise < $1.exercise }
    }
}
