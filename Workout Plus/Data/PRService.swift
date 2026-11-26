// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  PRResult.swift
//  Workout Plus
//
//


import Foundation

struct PRResult: Identifiable {
    enum Kind: String {
        case weight = "Heaviest set"
        /// Bodyweight-relative exercises (assisted → bodyweight → weighted)
        /// track one number instead of splitting into "heaviest" and "least
        /// assistance" — see `ExerciseTemplate.effectiveLoad`.
        case effectiveLoad = "Best load"
        case reps = "Most reps"
        case volume = "Best set volume"
        case duration = "Longest hold"
    }
    var id: String { kind.rawValue }
    let kind: Kind
    let value: Double
    let previous: Double
}

enum PRService {

    /// Personal bests for an exercise across all history.
    /// Call this ONCE (e.g. when a sheet opens) — it walks every session.
    /// Matches history by `ExerciseTemplate.canonicalName` so a renamed
    /// exercise (e.g. "Assisted Pull-up" → "Pull-up") still sees its older
    /// rows. For a bodyweight-relative exercise, `weight` comes back as the
    /// best EFFECTIVE LOAD ever (bodyweight ∓ the logged number — see
    /// `ExerciseTemplate.effectiveLoad`), which simply gets bigger as you
    /// improve in every regime, so `volume` stays 0 the same as before.
    static func bests(exerciseName: String, exerciseID: String? = nil, usesBodyweight: Bool = false,
                      in sessions: [WorkoutSession], bodyStats: [BodyStat] = [])
    -> (weight: Double, reps: Int, volume: Double, seconds: Int) {
        var w = 0.0, v = 0.0
        var r = 0, s = 0
        let canonical = ExerciseTemplate.canonicalName(exerciseName)
        // Warm-ups excluded: a heavy warm-up single should never take a PR.
        for session in sessions {
            for e in session.workingSets where ExerciseTemplate.canonicalName(e.exerciseName) == canonical || (exerciseID != nil && e.exerciseID == exerciseID) {
                r = max(r, e.reps)
                s = max(s, e.seconds)
                if usesBodyweight {
                    guard let bw = session.resolvedBodyweightKg(bodyStats: bodyStats) else { continue }
                    let load = ExerciseTemplate.effectiveLoad(weightKg: e.weightKg, isAssisted: e.resolvedIsAssisted, bodyweightKg: bw)
                    w = max(w, load)
                } else {
                    w = max(w, e.weightKg)
                    v = max(v, e.weightKg * Double(e.reps))
                }
            }
        }
        return (w, r, v, s)
    }

    /// Cheap variant: compares a draft against pre-computed bests.
    /// No history scan, so it's safe to call on every wheel tick.
    static func check(bests old: (weight: Double, reps: Int, volume: Double, seconds: Int),
                      isTimed: Bool,
                      usesBodyweight: Bool = false,
                      bodyweightKg: Double? = nil,
                      draft: [DraftSet]) -> [PRResult] {
        var out: [PRResult] = []

        if isTimed {
            let best = draft.map(\.seconds).max() ?? 0
            if best > old.seconds && old.seconds > 0 {
                out.append(.init(kind: .duration, value: Double(best), previous: Double(old.seconds)))
            }
            return out
        }

        if usesBodyweight {
            // Nothing to compute an effective load against yet — no PR check
            // this time rather than a wrong one.
            guard let bodyweightKg else { return out }
            let loads = draft.map {
                ExerciseTemplate.effectiveLoad(weightKg: $0.weightKg, isAssisted: $0.isAssisted, bodyweightKg: bodyweightKg)
            }
            let newLoad = loads.max() ?? 0
            if newLoad > old.weight && old.weight > 0 {
                out.append(.init(kind: .effectiveLoad, value: newLoad, previous: old.weight))
            }
            let newReps = draft.map(\.reps).max() ?? 0
            if newReps > old.reps && old.reps > 0 && newLoad >= old.weight {
                out.append(.init(kind: .reps, value: Double(newReps), previous: Double(old.reps)))
            }
            return out
        }

        let newWeight = draft.map(\.weightKg).max() ?? 0
        if newWeight > old.weight && old.weight > 0 {
            out.append(.init(kind: .weight, value: newWeight, previous: old.weight))
        }
        let newVolume = draft.map { $0.weightKg * Double($0.reps) }.max() ?? 0
        if newVolume > old.volume && old.volume > 0 {
            out.append(.init(kind: .volume, value: newVolume, previous: old.volume))
        }
        let newReps = draft.map(\.reps).max() ?? 0
        if newReps > old.reps && old.reps > 0 && newWeight >= old.weight {
            out.append(.init(kind: .reps, value: Double(newReps), previous: Double(old.reps)))
        }
        return out
    }

    /// Convenience wrapper that fetches bests then compares. Expensive —
    /// prefer the cached variant above inside views that redraw often.
    static func check(exerciseName: String,
                      isTimed: Bool,
                      usesBodyweight: Bool? = nil,
                      bodyweightKg: Double? = nil,
                      draft: [DraftSet],
                      sessions: [WorkoutSession],
                      bodyStats: [BodyStat] = []) -> [PRResult] {
        let bodyweightBased = usesBodyweight ?? ExerciseTemplate.nameImpliesBodyweight(exerciseName)
        let old = bests(exerciseName: exerciseName, usesBodyweight: bodyweightBased, in: sessions, bodyStats: bodyStats)
        return check(bests: old, isTimed: isTimed, usesBodyweight: bodyweightBased, bodyweightKg: bodyweightKg, draft: draft)
    }
}
