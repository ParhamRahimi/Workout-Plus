// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  RestAlerts.swift
//  Workout Plus
//
//  A rest timer you have to stare at isn't a rest timer. This schedules one
//  local notification for the end of the current rest and cancels it the moment
//  rest is stopped or restarted, so there is never more than one pending.
//

import Foundation
import os
import UserNotifications
import UIKit

enum RestAlerts {
    private static let identifier = "workout-plus.rest-finished"

    /// Asks for permission. Returns whether alerts can actually be delivered.
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.data.error("Notification permission failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    static func schedule(at date: Date, exercise: String?) {
        cancel()
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest is up"
        content.body = UserDefaults.standard.bool(forKey: "showWorkoutDetails") ? (exercise.map { "Next set: \($0)" } ?? "Back to it.") : "Your rest timer has finished."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.data.error("Rest alert failed: \(error.localizedDescription, privacy: .private)") }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// In-app end-of-rest feedback, for when the phone is already in your hand.
    @MainActor
    static func buzz() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
