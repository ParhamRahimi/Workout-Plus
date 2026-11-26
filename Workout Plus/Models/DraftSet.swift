// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation

/// One in-memory set being edited. Codable so it can be snapshotted to disk.
struct DraftSet: Identifiable, Codable {
    var id = UUID()
    var weightKg: Double = 0
    var reps: Int = 0
    var seconds: Int = 0
    var isWarmup: Bool = false
    /// True when `weightKg` is assistance (help) rather than added load.
    /// Per-set, mirroring `isWarmup` — see `SetEntry.isAssisted`.
    var isAssisted: Bool = false
    /// Reps in reserve. nil = not recorded.
    var rir: Int?
    /// Marked the moment you actually finish the set, rather than when you
    /// finish the whole exercise. This is what lets rest start after set 1.
    var isDone: Bool = false
    /// When you tapped "finish set". Turns the session from a start and an end
    /// time into an actual timeline of work and rest.
    var finishedAt: Date?

    init(weightKg: Double = 0, reps: Int = 0, seconds: Int = 0,
         isWarmup: Bool = false, isAssisted: Bool = false,
         rir: Int? = nil, isDone: Bool = false) {
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.isWarmup = isWarmup
        self.isAssisted = isAssisted
        self.rir = rir
        self.isDone = isDone
    }

    /// Hand-written so a snapshot saved by an older build — which has no
    /// `isWarmup` or `rir` keys — still decodes instead of throwing away an
    /// interrupted workout.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 0
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
        isWarmup = try c.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        isAssisted = try c.decodeIfPresent(Bool.self, forKey: .isAssisted) ?? false
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    }

    /// A row you never actually performed: no reps, no seconds, not ticked off.
    var isEmptyPlaceholder: Bool { !isDone && reps == 0 && seconds == 0 }
}
