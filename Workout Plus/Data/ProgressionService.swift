// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  ProgressionService.swift
//  Workout Plus
//
//

import Foundation

enum ProgressionService {

    struct Suggestion {
        var headline: String
        var detail: String
        var suggestedWeight: Double?
        var isReady: Bool          // true = time to progress
        /// Assist machines progress by taking load OFF. The arrow has to agree.
        var lowerIsBetter: Bool = false
        /// What the earlier sets should stay at while you test a heavier top
        /// set. nil when there's nothing to probe.
        var baseWeight: Double? = nil
        /// The heavier weight to try on the last set only.
        var probeWeight: Double? = nil
        /// Whether `suggestedWeight` is assistance (help) rather than added
        /// load — only meaningful for a bodyweight-relative exercise. Needed
        /// because a set now carries its own regime (`DraftSet.isAssisted`);
        /// applying a suggestion has to set that flag, not just the number.
        var suggestedIsAssisted: Bool = false

        var symbolName: String {
            guard isReady else { return "equal.circle.fill" }
            return lowerIsBetter ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
        }
    }

    /// Smallest sensible jump for a given load.
    static func increment(for weight: Double) -> Double {
        if weight < 12 { return 1.0 }
        if weight < 30 { return 2.5 }
        return 5.0
    }

    /// Applies your own rule: top of range on every set with clean form → add
    /// weight. "Clean form" is the recorded effort (reps in reserve); when it
    /// wasn't recorded the rule falls back to reps alone, as before.
    static func suggest(template: ExerciseTemplate, lastSets: [SetEntry], bodyStats: [BodyStat] = []) -> Suggestion? {
        // Warm-ups are not evidence of anything.
        let working = lastSets.filter { !$0.isWarmup }
        let sets = working.isEmpty ? lastSets : working

        guard !sets.isEmpty else {
            return Suggestion(headline: "First time",
                              detail: "Pick a weight you could stop 2 reps short of failure with.",
                              suggestedWeight: nil, isReady: false)
        }

        // Bodyweight-relative exercises (assisted → bodyweight → weighted)
        // get one continuous "effective load" number instead of the
        // assist/added split below — see `ExerciseTemplate.effectiveLoad`.
        // Falls through to the legacy path when there's no bodyweight to
        // compute it against yet (fresh install, no BodyStat logged) rather
        // than block a suggestion.
        if template.loadIsBodyweight, !template.isTimed,
           let bodyweightKg = sets.first?.session?.resolvedBodyweightKg(bodyStats: bodyStats) {
            return suggestBodyweightRelative(template: template, sets: sets, bodyweightKg: bodyweightKg)
        }

        if template.isTimed {
            let best = sets.map(\.seconds).min() ?? 0
            if best >= template.repRangeHigh {
                return Suggestion(headline: "Progress the hold",
                                  detail: "You hit \(best)s on every set. Add 5s, or move to a harder variation.",
                                  suggestedWeight: nil, isReady: true)
            }
            return Suggestion(headline: "Hold steady",
                              detail: "Target \(template.repRangeHigh)s on all sets before progressing.",
                              suggestedWeight: nil, isReady: false)
        }

        // On an assist machine the number logged is HELP, not load: the hardest
        // set is the one with the LEAST of it, and progress means it goes down.
        let assisted = template.loadIsAssistance
        let workingWeight = assisted
            ? (sets.map(\.weightKg).min() ?? 0)
            : (sets.map(\.weightKg).max() ?? 0)
        let setsAtWorking = sets.filter { $0.weightKg == workingWeight }
        let minReps = setsAtWorking.map(\.reps).min() ?? 0
        let allAtCeiling = minReps >= template.repRangeHigh
        let effort = Effort(sets: setsAtWorking)

        // Did last session end with a single heavier set — a top-set probe?
        // That's a deliberate pattern, not a failed session, and it deserves
        // its own answer: the whole point of probing is to find out whether the
        // new load is ready to be taken across every set.
        if !assisted,
           let probe = probeFrom(sets: sets, workingWeight: workingWeight) {
            return followUpToProbe(template: template, probe: probe)
        }

        if allAtCeiling {
            // A ceiling reached at true failure isn't the same evidence as a
            // ceiling reached with two in the tank.
            if effort == .toFailure {
                let label = assisted ? "\(fmt(workingWeight)) kg assist" : "\(fmt(workingWeight)) kg"
                return Suggestion(
                    headline: "Repeat \(label)",
                    detail: "You hit \(template.repRangeHigh) but the last set went to failure. Own this load for one more session before changing it.",
                    suggestedWeight: workingWeight, isReady: false,
                    lowerIsBetter: assisted)
            }
            if assisted { return dropAssistance(template: template, current: workingWeight, effort: effort) }
            if workingWeight == 0 { return progressBodyweight(template: template, minReps: minReps) }
            return addWeight(template: template, current: workingWeight, effort: effort)
        }

        let stay = assisted ? "Stay at \(fmt(workingWeight)) kg assist" : "Stay at \(fmt(workingWeight)) kg"

        if minReps < template.repRangeLow {
            let advice = assisted
                ? "Keep the assistance here until the reps climb."
                : "Chase reps first."
            return Suggestion(headline: stay,
                              detail: "Lowest set was \(minReps) reps, below the \(template.repRangeLow) floor. \(advice)",
                              suggestedWeight: workingWeight, isReady: false,
                              lowerIsBetter: assisted)
        }

        var advice = assisted
            ? "Get \(template.repRangeHigh) on every set, then drop the assist."
            : "Get \(template.repRangeHigh) on every set, then add weight."
        if effort == .unknown {
            advice += " Tag how hard the last set felt and this gets sharper."
        }
        return Suggestion(headline: stay, detail: advice,
                          suggestedWeight: workingWeight, isReady: false,
                          lowerIsBetter: assisted)
    }

    // MARK: - Top-set probing

    struct Probe {
        var weight: Double       // the heavier set
        var reps: Int
        var base: Double         // what the other sets were at
    }

    /// A probe is exactly one set heavier than the rest. A normal session has
    /// every working set at the same load, so this only fires when you actually
    /// went up on the last one.
    private static func probeFrom(sets: [SetEntry], workingWeight: Double) -> Probe? {
        guard workingWeight > 0 else { return nil }
        let atTop = sets.filter { $0.weightKg == workingWeight }
        let below = sets.filter { $0.weightKg < workingWeight }
        guard atTop.count == 1, below.count >= 1,
              let base = below.map(\.weightKg).max(), base > 0
        else { return nil }
        return Probe(weight: workingWeight, reps: atTop[0].reps, base: base)
    }

    private static func followUpToProbe(template: ExerciseTemplate, probe: Probe) -> Suggestion {
        let low = template.repRangeLow
        let high = template.repRangeHigh

        if probe.reps >= high {
            return Suggestion(
                headline: "Take \(fmt(probe.weight)) across every set",
                detail: "Your top set at \(fmt(probe.weight)) hit \(probe.reps) — the full range, on the most fatigued set of the day. There's nothing left to test.",
                suggestedWeight: probe.weight, isReady: true)
        }

        if probe.reps >= low {
            return Suggestion(
                headline: "Take \(fmt(probe.weight)) across every set",
                detail: "Your top set at \(fmt(probe.weight)) gave \(probe.reps), inside the \(low)–\(high) range. Start every set there and work the reps back up to \(high).",
                suggestedWeight: probe.weight, isReady: true)
        }

        if probe.reps >= max(1, low - 2) {
            return Suggestion(
                headline: "Start at \(fmt(probe.weight))",
                detail: "The probe gave \(probe.reps), just under the \(low) floor — but that was your last set, fresh legs will do better. Start every set at \(fmt(probe.weight)) and expect the reps to be short for a session or two.",
                suggestedWeight: probe.weight, isReady: true)
        }

        let smaller = probe.base + max((template.weightIncrementKg ?? increment(for: probe.base)) / 2, 0.5)
        return Suggestion(
            headline: "Back to \(fmt(probe.base))",
            detail: "The probe at \(fmt(probe.weight)) only gave \(probe.reps). That jump was too big — rebuild at \(fmt(probe.base)) and try \(fmt(smaller)) next time instead.",
            suggestedWeight: probe.base, isReady: false,
            baseWeight: probe.base, probeWeight: smaller)
    }

    // MARK: - Recorded effort

    enum Effort {
        case unknown, easy, hard, toFailure

        var label: String? {
            switch self {
            case .unknown:   return nil
            case .easy:      return "easy"
            case .hard:      return "hard"
            case .toFailure: return "like a max"
            }
        }

        /// The hardest thing recorded across the working sets wins: one set
        /// taken to failure characterises the session.
        init(sets: [SetEntry]) {
            let recorded = sets.compactMap(\.rir)
            guard let lowest = recorded.min() else { self = .unknown; return }
            switch lowest {
            case ...0:  self = .toFailure
            case 1:     self = .hard
            default:    self = .easy
            }
        }
    }

    // MARK: - The directions of "progress"

    private static func addWeight(template: ExerciseTemplate, current: Double, effort: Effort) -> Suggestion {
        // Two in the tank at the top of the range means the jump can be bigger.
        let step = template.weightIncrementKg ?? increment(for: current)
        let next = current + step
        let pct = current > 0 ? (next - current) / current * 100 : 0

        var detail = "All sets hit \(template.repRangeHigh) at \(fmt(current)) kg."
        if effort == .easy {
            detail += " Use the configured equipment increment."
        }
        if pct > 20 {
            detail += " That's a +\(Int(pct))% jump — try it on the top set only."
        }
        if effort == .unknown {
            detail += " Tag how hard the last set felt and this gets sharper."
        }
        return Suggestion(headline: "Try \(fmt(next)) kg",
                          detail: detail, suggestedWeight: next, isReady: true,
                          baseWeight: current, probeWeight: next)
    }

    /// Nothing to add weight TO — "Try 1.0 kg" is technically valid and
    /// completely useless as a default on a hanging leg raise.
    private static func progressBodyweight(template: ExerciseTemplate, minReps: Int) -> Suggestion {
        Suggestion(headline: "Make it harder",
                   detail: "All sets hit \(template.repRangeHigh) at bodyweight. Slow the lowering down, move to a harder variation, or choose an appropriate progression with qualified instruction.",
                   suggestedWeight: 0, isReady: true)
    }

    /// Assisted work progresses by REMOVING help, never by adding it.
    private static func dropAssistance(template: ExerciseTemplate, current: Double, effort: Effort) -> Suggestion {
        guard current > 0 else {
            return Suggestion(headline: "Add weight",
                              detail: "All sets hit \(template.repRangeHigh) with no assistance at all. Start loading a belt, or bank the extra reps.",
                              suggestedWeight: 0, isReady: true)
        }

        let step = template.weightIncrementKg ?? increment(for: current)
        let next = max(0, current - step)

        if next == 0 {
            return Suggestion(headline: "Try unassisted",
                              detail: "All sets hit \(template.repRangeHigh) at \(fmt(current)) kg of assistance — that's the last of it. Next stop is a clean bodyweight rep.",
                              suggestedWeight: 0, isReady: true, lowerIsBetter: true)
        }

        var detail = "All sets hit \(template.repRangeHigh) at \(fmt(current)) kg of assistance. Less help is the progress."
        let cut = (current - next) / current * 100
        if cut > 20 {
            detail += " That's \(Int(cut))% less help — use a smaller step or repeat the current load if control would be lost."
        }
        if effort == .unknown {
            detail += " Tag how hard the last set felt and this gets sharper."
        }
        return Suggestion(headline: "Try \(fmt(next)) kg assist",
                          detail: detail, suggestedWeight: next, isReady: true,
                          lowerIsBetter: true)
    }

    // MARK: - Bodyweight-relative progression

    /// Runs the same ceiling/floor logic as an ordinary weighted lift, fed
    /// `effectiveLoad` instead of raw `weightKg` — it simply gets bigger as
    /// you improve in every regime, so no `assisted`/`lowerIsBetter` split is
    /// needed here. Top-set probing doesn't extend to this path (it didn't
    /// for assisted lifts before either — the numbers are still transitional
    /// enough that fatigue-testing the whole jump isn't the priority).
    private static func suggestBodyweightRelative(template: ExerciseTemplate, sets: [SetEntry], bodyweightKg: Double) -> Suggestion {
        let entries = sets.map {
            (load: ExerciseTemplate.effectiveLoad(weightKg: $0.weightKg, isAssisted: $0.resolvedIsAssisted, bodyweightKg: bodyweightKg), reps: $0.reps)
        }
        let workingLoad = entries.map(\.load).max() ?? bodyweightKg
        let atWorking = entries.filter { $0.load == workingLoad }
        let minReps = atWorking.map(\.reps).min() ?? 0
        let allAtCeiling = minReps >= template.repRangeHigh
        let effort = Effort(sets: sets.filter {
            ExerciseTemplate.effectiveLoad(weightKg: $0.weightKg, isAssisted: $0.resolvedIsAssisted, bodyweightKg: bodyweightKg) == workingLoad
        })

        let (curRaw, curIsAssisted) = rawTerms(for: workingLoad, bodyweightKg: bodyweightKg)
        let label = loadLabel(workingLoad, bodyweightKg: bodyweightKg)

        if allAtCeiling {
            if effort == .toFailure {
                return Suggestion(
                    headline: "Repeat \(label)",
                    detail: "You hit \(template.repRangeHigh) but the last set went to failure. Own this load for one more session before changing it.",
                    suggestedWeight: curRaw, isReady: false,
                    lowerIsBetter: curIsAssisted, suggestedIsAssisted: curIsAssisted)
            }
            return progressEffectiveLoad(template: template, workingLoad: workingLoad, bodyweightKg: bodyweightKg, effort: effort)
        }

        if minReps < template.repRangeLow {
            return Suggestion(
                headline: "Stay at \(label)",
                detail: "Lowest set was \(minReps) reps, below the \(template.repRangeLow) floor. Keep this load here until the reps climb.",
                suggestedWeight: curRaw, isReady: false,
                lowerIsBetter: curIsAssisted, suggestedIsAssisted: curIsAssisted)
        }

        var advice = curIsAssisted
            ? "Get \(template.repRangeHigh) on every set, then drop the assist."
            : "Get \(template.repRangeHigh) on every set, then add weight."
        if effort == .unknown {
            advice += " Tag how hard the last set felt and this gets sharper."
        }
        return Suggestion(headline: "Stay at \(label)", detail: advice,
                          suggestedWeight: curRaw, isReady: false,
                          lowerIsBetter: curIsAssisted, suggestedIsAssisted: curIsAssisted)
    }

    private static func progressEffectiveLoad(template: ExerciseTemplate, workingLoad: Double, bodyweightKg: Double, effort: Effort) -> Suggestion {
        let (curRaw, curIsAssisted) = rawTerms(for: workingLoad, bodyweightKg: bodyweightKg)
        let step = template.weightIncrementKg ?? increment(for: max(curRaw, 1))

        var detail = curIsAssisted
            ? "All sets hit \(template.repRangeHigh) at \(fmt(curRaw)) kg of assistance. Less help is the progress."
            : (curRaw == 0
               ? "All sets hit \(template.repRangeHigh) at bodyweight."
               : "All sets hit \(template.repRangeHigh) at \(fmt(curRaw)) kg added.")
        if effort == .easy { detail += " Use the configured equipment increment." }
        if effort == .unknown { detail += " Tag how hard the last set felt and this gets sharper." }

        // Crossing from assisted to unassisted: land on the milestone exactly
        // rather than overshoot into a fractional "added" number the moment
        // the assistance runs out.
        if curIsAssisted, workingLoad + step >= bodyweightKg {
            return Suggestion(
                headline: "Try unassisted",
                detail: detail + " That's the last of the assistance — next stop is a clean bodyweight rep.",
                suggestedWeight: 0, isReady: true, suggestedIsAssisted: false)
        }

        let next = workingLoad + step
        let (nextRaw, nextIsAssisted) = rawTerms(for: next, bodyweightKg: bodyweightKg)
        let headline = nextIsAssisted ? "Try \(fmt(nextRaw)) kg assist"
            : (nextRaw == 0 ? "Try unassisted" : "Try \(fmt(nextRaw)) kg added")

        return Suggestion(headline: headline, detail: detail,
                          suggestedWeight: nextRaw, isReady: true,
                          lowerIsBetter: nextIsAssisted, suggestedIsAssisted: nextIsAssisted)
    }

    /// "38 kg added" once past bodyweight, "bodyweight" exactly at it,
    /// "6 kg assist" still under it.
    private static func loadLabel(_ load: Double, bodyweightKg: Double) -> String {
        let (raw, isAssisted) = rawTerms(for: load, bodyweightKg: bodyweightKg)
        if isAssisted { return "\(fmt(raw)) kg assist" }
        if raw == 0 { return "bodyweight" }
        return "\(fmt(raw)) kg added"
    }

    /// Effective load back to what you'd actually dial in: distance below
    /// bodyweight is assistance, distance above is added load.
    private static func rawTerms(for load: Double, bodyweightKg: Double) -> (weight: Double, isAssisted: Bool) {
        if load < bodyweightKg { return (bodyweightKg - load, true) }
        return (load - bodyweightKg, false)
    }

    private static func fmt(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...1)))
    }
}
