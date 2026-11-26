// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import SwiftData

@Model
final class BodyStat {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var photoFilename: String?
    var note: String
    var syncedToHealth: Bool = false
    var healthKitUUID: String?

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
