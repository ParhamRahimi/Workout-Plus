// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  EnergyService.swift
//  Workout Plus
//
//  A better-founded estimate of the energy cost of a strength session — and an
//  honest account of what it can and cannot know.
//
//  WHAT ACTUALLY IMPROVES THE NUMBER
//
//  1. Real active time. The old model charged you for wall-clock from the first
//     set to the last. Twenty minutes on your phone between exercises counted
//     exactly the same as twenty minutes of training. Now that every set is
//     timestamped, a gap longer than `idleGapCutoff` is treated as what it is —
//     not training — and dropped.
//
//  2. Resting metabolic rate instead of raw bodyweight. One MET is defined as
//     3.5 ml O₂/kg/min, which is a population average that is wrong for any
//     particular person. Mifflin-St Jeor from height, age and sex is the
//     best-validated cheap estimate of YOUR resting rate, and everything scales
//     off it.
//
//  3. Set density. Twenty-eight sets in an hour is genuinely harder work per
//     minute than twenty-eight sets in two hours. The MET value moves with how
//     tightly packed the session actually was, which is something the app can
//     now measure rather than assume.
//
//  WHAT DOESN'T
//
//  • Effort tags. Reps-in-reserve says how close to failure you were, not how
//    much energy the set cost. At the same load and reps the mechanical work is
//    the same; RIR mostly reports fatigue. Any effect is far inside the error
//    bar, and using it would mean the number moves for reasons that aren't
//    energetic.
//
//  • Computing mechanical work from load × reps × range of motion. It looks
//    rigorous and it is a trap: external work through the bar accounts for a
//    small fraction of the metabolic cost of lifting. Isometric stabilisation,
//    the eccentric, elevated ventilation and the genuinely poor efficiency of
//    near-maximal contraction dominate, and none of them are in that sum. A
//    physics-shaped model would be confidently wrong rather than honestly
//    approximate.
//
//  This remains an ESTIMATE with no measurement of your oxygen consumption.
//  This estimate has not been validated for individual accuracy.
//

import Foundation

struct EnergyProfile {
    var bodyweightKg: Double
    var heightCm: Double?
    var age: Int?
    var sex: BiologicalSex

    enum BiologicalSex: String, CaseIterable, Identifiable, Codable {
        case male = "Male", female = "Female", unspecified = "Prefer not to say"
        var id: String { rawValue }
    }

    /// True when there's enough to compute a real BMR rather than fall back.
    var isComplete: Bool { heightCm != nil && age != nil }

    /// Mifflin-St Jeor, kcal/day. Falls back to a bodyweight-only approximation
    /// when height and age aren't known, which is roughly where the old model
    /// was — so an incomplete profile is never worse than before.
    var basalKcalPerDay: Double {
        guard let heightCm, let age else {
            return 24.0 * bodyweightKg          // ~1 kcal/kg/hour, the classic rule of thumb
        }
        let base = 10 * bodyweightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male:        return base + 5
        case .female:      return base - 161
        case .unspecified: return base - 78     // midpoint, when we're not told
        }
    }

    var basalKcalPerMinute: Double { basalKcalPerDay / 1440 }
}

struct EnergyEstimate {
    /// What gets written to Health: cost ABOVE simply being alive.
    var activeKcal: Double
    var activeMinutes: Double
    var idleMinutesRemoved: Double
    var workingSets: Int
    var setsPerMinute: Double
    var met: Double
    var usedFullProfile: Bool

    var rangeText: String {
        "Unvalidated estimate; individual error is unknown"
    }
}

enum EnergyService {

    /// A pause longer than this isn't rest between sets, it's a break.
    static let idleGapCutoff: TimeInterval = 6 * 60

    /// METs at the two ends of realistic strength-training density, gross
    /// (i.e. including the 1 MET of just existing, which is subtracted later).
    private static let sparseMET = 3.2      // long rests, heavy singles
    private static let denseMET = 6.5       // circuit-like, minimal rest

    static func estimate(session: WorkoutSession, profile: EnergyProfile) -> EnergyEstimate? {
        guard profile.bodyweightKg > 0 else { return nil }

        let working = session.workingSets
        guard !working.isEmpty else { return nil }

        // ── Active time ──────────────────────────────────────────────────────
        // Prefer the real timeline. Sets logged before timestamps existed fall
        // back to start→end, which is exactly the old behaviour.
        let stamps = working.compactMap(\.performedAt).sorted()
        let wallClock = (session.endDate ?? session.date).timeIntervalSince(session.date)

        var activeSeconds: TimeInterval
        var idleSeconds: TimeInterval = 0

        if stamps.count >= 2 {
            // Count from the session start to the last set, minus long gaps.
            var previous = session.date
            var total: TimeInterval = 0
            for stamp in stamps {
                let gap = stamp.timeIntervalSince(previous)
                if gap > 0 {
                    if gap > idleGapCutoff {
                        // Keep a normal rest's worth, discard the rest of it.
                        total += idleGapCutoff
                        idleSeconds += gap - idleGapCutoff
                    } else {
                        total += gap
                    }
                }
                previous = stamp
            }
            activeSeconds = total
        } else {
            activeSeconds = wallClock
        }

        guard activeSeconds > 60 else { return nil }
        let activeMinutes = activeSeconds / 60

        // ── Density → MET ────────────────────────────────────────────────────
        let setsPerMinute = Double(working.count) / activeMinutes
        // 0.15 sets/min is a slow heavy session; 0.6 is close to circuit work.
        let t = min(max((setsPerMinute - 0.15) / (0.60 - 0.15), 0), 1)
        let met = sparseMET + (denseMET - sparseMET) * t

        // ── Energy ───────────────────────────────────────────────────────────
        // Active = above resting, which is what HealthKit's activeEnergyBurned
        // is defined as. Writing the gross figure overstates by a full MET.
        let activeKcal = (met - 1.0) * profile.basalKcalPerMinute * activeMinutes

        return EnergyEstimate(
            activeKcal: max(activeKcal, 0),
            activeMinutes: activeMinutes,
            idleMinutesRemoved: idleSeconds / 60,
            workingSets: working.count,
            setsPerMinute: setsPerMinute,
            met: met,
            usedFullProfile: profile.isComplete
        )
    }

    /// Plain-language account of where the number came from, so it can be
    /// argued with rather than just believed.
    static func explanation(_ e: EnergyEstimate) -> [String] {
        var lines: [String] = []
        lines.append("\(e.workingSets) working sets over \(Int(e.activeMinutes.rounded())) active minutes")
        if e.idleMinutesRemoved >= 1 {
            lines.append("\(Int(e.idleMinutesRemoved.rounded())) idle minutes not counted")
        }
        lines.append("\(e.setsPerMinute.formatted(.number.precision(.fractionLength(2)))) sets/min → \(e.met.formatted(.number.precision(.fractionLength(1)))) METs")
        lines.append(e.usedFullProfile
                     ? "Scaled to your resting rate (height, age, sex)"
                     : "Scaled by bodyweight only — add height and age in Settings for a better figure")
        return lines
    }
}
