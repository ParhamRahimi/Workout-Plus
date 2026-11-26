// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  HealthKitService.swift
//  Workout Plus
//
//


import Foundation
import os
import HealthKit

/// @MainActor because `lastError` is observable UI state that was being
/// mutated from `async` contexts with no isolation at all — a Swift 6 strict
/// concurrency error waiting to happen.
@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var lastError: String?
    private var writesInFlight = Set<UUID>()
    var isErasing = false
    var hasActiveWrites: Bool { !writesInFlight.isEmpty }

    private init() {}

    // MARK: Authorization

    private var writeTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.activeEnergyBurned)
        ]
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "Health data isn't available on this device."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // `requestAuthorization` succeeds whether you granted or denied —
            // it only throws when the request itself failed. Reporting
            // "Permission granted" off the back of it was simply wrong.
            return shareStatus.isOn
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Whether we're allowed to write workouts (nil-safe check for UI).
    var canWriteWorkouts: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    enum ShareStatus {
        case notDetermined, denied, partial, authorized

        var title: String {
            switch self {
            case .notDetermined: return "Not connected"
            case .denied:        return "Turned off in Health"
            case .partial:       return "Partly connected"
            case .authorized:    return "Connected"
            }
        }

        var isOn: Bool { self == .authorized || self == .partial }
    }

    /// What Health will actually let us WRITE, right now.
    ///
    /// Read permission is deliberately never disclosed by HealthKit — an app
    /// that could see it would learn something about you just by asking — so
    /// this only ever reports the write side. That's the side that matters for
    /// everything this app puts into Health.
    var shareStatus: ShareStatus {
        let types: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.activeEnergyBurned)
        ]
        let statuses = types.map { store.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) { return .authorized }
        if statuses.allSatisfy({ $0 == .notDetermined }) { return .notDetermined }
        if statuses.contains(.sharingAuthorized) { return .partial }
        return .denied
    }

    // MARK: Delete

    /// Deleting a session locally used to leave its workout in Apple Health
    /// forever. We already store the UUID, so it can be cleaned up properly.
    /// Returns false if the sample isn't ours to delete or can't be found.
    @discardableResult
    func deleteWorkout(uuidString: String) async -> Bool {
        guard let uuid = UUID(uuidString: uuidString) else { return false }
        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                sortDescriptors: [],
                limit: 1
            )
            guard let sample = try await descriptor.result(for: store).first else {
                lastError = "The Health workout is unavailable. Check read/delete permissions in Health and retry, or delete only the local copy."
                return false
            }
            try await store.delete(sample)
            return true
        } catch {
            Log.health.error("Deleting a Health workout failed: \(error.localizedDescription, privacy: .private)")
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Write a workout

    /// Saves a strength-training workout. Returns the HealthKit UUID.
    /// `externalID` makes the write idempotent-ish and traceable back to our session.
    @discardableResult
    func saveWorkout(start: Date,
                     end: Date,
                     externalID: UUID,
                     exerciseSummary: String,
                     energyKcal: Double?) async throws -> UUID {

        guard !isErasing, writesInFlight.insert(externalID).inserted else {
            throw PlanValidationError(problems: ["This workout is already syncing. Retry shortly."])
        }
        defer { writesInFlight.remove(externalID) }
        let identity = "workout-plus.session." + externalID.uuidString
        let identityPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identity]),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [externalID.uuidString])
        ])
        let ownedIdentity = NSCompoundPredicate(andPredicateWithSubpredicates: [identityPredicate, HKQuery.predicateForObjects(from: HKSource.default())])
        let existing = HKSampleQueryDescriptor(predicates: [.workout(ownedIdentity)], sortDescriptors: [], limit: 1)
        if let sample = try await existing.result(for: store).first { return sample.uuid }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store,
                                       configuration: config,
                                       device: .local())

        try await builder.beginCollection(at: start)

        // Custom metadata: HealthKit accepts String / NSNumber / Date / HKQuantity values.
        // Other apps won't understand these keys, but the Health app shows them
        // and they make the record self-describing.
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: externalID.uuidString,
            HKMetadataKeySyncIdentifier: identity,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyIndoorWorkout: true,
            "WorkoutPlusExercises": exerciseSummary
        ]
        metadata[HKMetadataKeyWorkoutBrandName] = "Workout Plus"

        try await builder.addMetadata(metadata)

        if let energyKcal, energyKcal > 0 {
            let sample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
                start: start,
                end: end
            )
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)

        guard let workout = try await builder.finishWorkout() else {
            throw NSError(domain: "WorkoutPlus", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "HealthKit didn't return a workout."])
        }
        return workout.uuid
    }

    /// Strips the estimated active-energy samples this app attached to its own
    /// workouts, leaving the workouts themselves intact. HealthKit only lets an
    /// app delete what it wrote, so this can never touch a Watch's numbers.
    ///
    /// This exists so switching calorie estimates on is a reversible decision
    /// rather than a permanent mark on your Move ring.
    @discardableResult
    func deleteEstimatedEnergy(fromWorkoutUUIDs uuidStrings: [String]) async -> (workouts: Int, samples: Int) {
        var touchedWorkouts = 0
        var removedSamples = 0

        for string in uuidStrings {
            guard let uuid = UUID(uuidString: string) else { continue }
            do {
                let workoutQuery = HKSampleQueryDescriptor(
                    predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                    sortDescriptors: [],
                    limit: 1
                )
                guard let workout = try await workoutQuery.result(for: store).first else { continue }

                let energyQuery = HKSampleQueryDescriptor(
                    predicates: [.quantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                 predicate: HKQuery.predicateForObjects(from: workout))],
                    sortDescriptors: []
                )
                let samples = try await energyQuery.result(for: store)
                guard !samples.isEmpty else { continue }

                for sample in samples {
                    try await store.delete(sample)
                    removedSamples += 1
                }
                touchedWorkouts += 1
            } catch {
                Log.health.error("Removing estimated energy failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        return (touchedWorkouts, removedSamples)
    }

    // MARK: Bodyweight

    @discardableResult
    func saveBodyMass(kg: Double, date: Date, externalID: UUID) async throws -> UUID {
        guard !isErasing, writesInFlight.insert(externalID).inserted else { throw PlanValidationError(problems: ["Health is busy. Retry later."]) }
        defer { writesInFlight.remove(externalID) }
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date,
                                      metadata: [HKMetadataKeySyncIdentifier: "workout-plus.body." + externalID.uuidString, HKMetadataKeySyncVersion: 1])
        try await store.save(sample)
        return sample.uuid
    }

    func deleteBodyMass(uuidString: String) async throws {
        guard let uuid = UUID(uuidString: uuidString) else { return }
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForObject(with: uuid))], sortDescriptors: [], limit: 1)
        guard let sample = try await query.result(for: store).first else {
            throw PlanValidationError(problems: ["Bodyweight sample unavailable in Health. Check permissions or delete it in Health."])
        }
        try await store.delete(sample)
    }

    /// Most recent bodyweight in Health, if any.
    func latestBodyMass() async -> (kg: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            let results = try await descriptor.result(for: store)
            guard let sample = results.first else { return nil }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            return (kg, sample.endDate)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}