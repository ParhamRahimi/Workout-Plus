// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import SwiftData
import UserNotifications
import WidgetKit

extension Notification.Name {
    static let workoutDataErased = Notification.Name("workoutDataErased")
}

@MainActor
enum DataDeletion {
    static func erase(context: ModelContext, plans: PlanStore, engine: WorkoutEngine, alsoHealth: Bool) async throws {
        guard !HealthKitService.shared.hasActiveWrites else {
            throw PlanValidationError(problems: ["A Health sync is still running. Wait for it to finish, then retry."])
        }
        HealthKitService.shared.isErasing = true
        defer { HealthKitService.shared.isErasing = false }
        if alsoHealth {
            for session in try context.fetch(FetchDescriptor<WorkoutSession>()) {
                if let id = session.healthKitUUID {
                    guard await HealthKitService.shared.deleteWorkout(uuidString: id) else {
                        throw PlanValidationError(problems: ["Some Health data could not be deleted. Local records were retained so deletion can be retried, or local-only deletion can be chosen after managing Health directly."])
                    }
                    session.healthKitUUID = nil
                    try context.save()
                }
            }
            for stat in try context.fetch(FetchDescriptor<BodyStat>()) {
                if let id = stat.healthKitUUID {
                    try await HealthKitService.shared.deleteBodyMass(uuidString: id)
                    stat.healthKitUUID = nil; stat.syncedToHealth = false
                    try context.save()
                }
            }
        }
        try plans.replacePlans([SeedData.plan], activeID: SeedData.plan.id, recovering: true)
        do {
            try context.delete(model: WorkoutSession.self)
            try context.delete(model: BodyStat.self)
            try context.delete(model: SetEntry.self)
            try context.save()
        } catch { context.rollback(); throw error }
        UserDefaults.standard.set(false, forKey: "remoteImagesEnabled")
        engine.cancel()
        try engine.eraseSnapshot()
        LiveWorkoutActivity.end()
        RestAlerts.cancel()
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        try PhotoStore.eraseAll()
        try await DiskImageCache.shared.eraseAll()
        try ExportService.eraseFiles()
        if let url = WidgetSnapshot.fileURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        if let identifier = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .workoutDataErased, object: nil)
    }
}
