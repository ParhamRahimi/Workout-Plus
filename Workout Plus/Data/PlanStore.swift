// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import Observation

@Observable
final class PlanStore {
    private(set) var plans: [Plan] = []
    var activePlanID: String {
        didSet { UserDefaults.standard.set(activePlanID, forKey: "activePlanID") }
    }
    private(set) var lastSaveError: String?
    private(set) var loadFailed = false
    static var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("plans.json")
    }
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = PlanStore.recoveryURL) {
        self.fileURL = fileURL
        var loaded = [SeedData.plan]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try ImportLimits.read(fileURL, maximum: ImportLimits.backupBytes)
                let decoded = try JSONDecoder().decode([Plan].self, from: data)
                guard !decoded.isEmpty else { throw PlanValidationError(problems: ["The plans file is empty."]) }
                loaded = decoded
            } catch {
                loadFailed = true
                lastSaveError = "Saved plans could not be opened. The original file is preserved; export it for recovery before resetting plans."
            }
        }
        plans = loaded
        let saved = UserDefaults.standard.string(forKey: "activePlanID")
        activePlanID = loaded.first(where: { $0.id == saved })?.id ?? loaded[0].id
    }

    var activePlan: Plan { plans.first { $0.id == activePlanID } ?? plans[0] }

    /// Persist the candidate before changing observable state. Used once per import/batch.
    func replacePlans(_ candidate: [Plan], activeID: String? = nil, recovering: Bool = false) throws {
        guard recovering || !loadFailed else { throw PlanValidationError(problems: [lastSaveError ?? "Plans require recovery."]) }
        guard !candidate.isEmpty, candidate.count <= 100 else { throw PlanValidationError(problems: ["Keep 1–100 installed plans."]) }
        do {
            let data = try JSONEncoder().encode(candidate)
            try ImportLimits.check(data, maximum: ImportLimits.backupBytes)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: PrivateFiles.writeOptions)
            plans = candidate
            if let activeID { activePlanID = activeID }
            if !plans.contains(where: { $0.id == activePlanID }) { activePlanID = plans[0].id }
            lastSaveError = nil
            loadFailed = false
        } catch {
            lastSaveError = "Plans were not saved. Check available storage and retry."
            throw error
        }
    }

    func wouldReplacePlan(id: String) -> Plan? { plans.first { $0.id == id } }

    @discardableResult
    func importPlan(from data: Data, makeActive: Bool = true) throws -> Plan {
        try ImportLimits.check(data, maximum: ImportLimits.planBytes)
        let plan = try PlanValidator.validated(JSONDecoder().decode(Plan.self, from: data))
        var candidate = plans
        if let i = candidate.firstIndex(where: { $0.id == plan.id }) { candidate[i] = plan }
        else { candidate.append(plan) }
        try replacePlans(candidate, activeID: makeActive ? plan.id : nil)
        return plan
    }

    func delete(_ plan: Plan) throws {
        var candidate = plans.filter { $0.id != plan.id }
        if candidate.isEmpty { candidate = [SeedData.plan] }
        try replacePlans(candidate)
    }

    func plan(containing workoutID: String) -> Plan? {
        plans.first { $0.workouts.contains { $0.id == workoutID } }
    }
    var allImageURLs: [URL] {
        plans.flatMap { $0.workouts }.flatMap { $0.exercises }.flatMap { $0.imageURLs }
            .filter(PlanValidator.isAllowedImageURL).compactMap(URL.init(string:))
    }
}
