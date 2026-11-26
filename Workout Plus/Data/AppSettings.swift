// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  AppSettings.swift
//  Workout Plus
//
//  Was HealthSyncSettings — it now carries rest-timer preferences too, and
//  these all live behind the gear in Workouts rather than buried at the bottom
//  of the data-export sheet, where nobody was ever going to find them.
//

import Foundation
import Observation

@Observable
final class AppSettings {
    var remoteImagesEnabled: Bool { didSet { UserDefaults.standard.set(remoteImagesEnabled, forKey: "remoteImagesEnabled") } }
    var showWorkoutDetails: Bool { didSet { UserDefaults.standard.set(showWorkoutDetails, forKey: "showWorkoutDetails") } }
    var appLockEnabled: Bool { didSet { UserDefaults.standard.set(appLockEnabled, forKey: "appLockEnabled") } }
    var syncWorkouts: Bool {
        didSet { UserDefaults.standard.set(syncWorkouts, forKey: "hkSyncWorkouts") }
    }
    var syncBodyweight: Bool {
        didSet { UserDefaults.standard.set(syncBodyweight, forKey: "hkSyncBodyweight") }
    }
    /// Off by default — estimated calories without heart rate are guesses.
    var writeEstimatedCalories: Bool {
        didSet { UserDefaults.standard.set(writeEstimatedCalories, forKey: "hkWriteCalories") }
    }

    /// Start a countdown automatically when a set is saved.
    var restTimerEnabled: Bool {
        didSet { UserDefaults.standard.set(restTimerEnabled, forKey: "restTimerEnabled") }
    }
    /// Fire a notification when rest is up, so the phone can go back in your
    /// pocket. Requires notification permission, which is why it's off until
    /// you ask for it.
    var restAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(restAlertsEnabled, forKey: "restAlertsEnabled") }
    }

    /// Warn before the 7-day sideloading signature runs out. On by default:
    /// the failure mode it prevents is arriving at the gym with an app that
    /// won't launch and no Mac to fix it with. See `BuildExpiry`.
    var expiryAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(expiryAlertsEnabled, forKey: "expiryAlertsEnabled") }
    }

    // MARK: Body data, used only for the energy estimate

    /// 0 = not set.
    var heightCm: Double {
        didSet { UserDefaults.standard.set(heightCm, forKey: "profileHeightCm") }
    }
    /// Stored as a date, not a year number.
    ///
    /// A device may use the Persian calendar, so `Calendar.current` reports the
    /// year as 1405, not 2026. A year typed as "2000" against that gives an age
    /// of minus four hundred and eight. A `Date` has no such ambiguity — it is
    /// the same instant in every calendar, and age comes from a calendar-aware
    /// difference rather than subtracting two numbers that may not be in the
    /// same system.
    var birthDate: Date? {
        didSet {
            if let birthDate {
                UserDefaults.standard.set(birthDate.timeIntervalSince1970, forKey: "profileBirthDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "profileBirthDate")
            }
        }
    }
    var biologicalSex: EnergyProfile.BiologicalSex {
        didSet { UserDefaults.standard.set(biologicalSex.rawValue, forKey: "profileSex") }
    }

    /// Height, age and sex estimate resting metabolic rate instead of the
    /// population-average 1 MET ≈ 1 kcal/kg/hour. Everything else in the
    /// estimate scales off that, so it's the single most useful thing to fill in.
    /// Whole years between the birth date and today, in whatever calendar the
    /// device is set to. Correct in all of them.
    var age: Int? {
        guard let birthDate, birthDate < .now else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
        guard let years, years > 0, years < 130 else { return nil }
        return years
    }

    func profile(bodyweightKg: Double?) -> EnergyProfile {
        EnergyProfile(
            bodyweightKg: bodyweightKg ?? 0,
            heightCm: heightCm > 0 ? heightCm : nil,
            age: age,
            sex: biologicalSex
        )
    }

    init() {
        let d = UserDefaults.standard
        remoteImagesEnabled = d.bool(forKey: "remoteImagesEnabled")
        showWorkoutDetails = d.bool(forKey: "showWorkoutDetails")
        appLockEnabled = d.bool(forKey: "appLockEnabled")
        syncWorkouts = d.bool(forKey: "hkSyncWorkouts")
        syncBodyweight = d.bool(forKey: "hkSyncBodyweight")
        writeEstimatedCalories = d.bool(forKey: "hkWriteCalories")
        restTimerEnabled = d.object(forKey: "restTimerEnabled") as? Bool ?? true
        restAlertsEnabled = d.bool(forKey: "restAlertsEnabled")
        expiryAlertsEnabled = d.object(forKey: "expiryAlertsEnabled") as? Bool ?? false
        heightCm = d.double(forKey: "profileHeightCm")

        // Resolved into a local first: reading a stored property back before
        // every one of them is initialised isn't allowed in an initialiser.
        let legacyYear = d.integer(forKey: "profileBirthYear")
        var resolvedBirthDate: Date?
        if let stamp = d.object(forKey: "profileBirthDate") as? Double {
            resolvedBirthDate = Date(timeIntervalSince1970: stamp)
        } else if legacyYear > 1900 {
            // Migrate a year typed into the old text field. It was entered as a
            // Gregorian year, so read it back as one explicitly rather than
            // through Calendar.current, which on this device is Persian.
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = .current
            resolvedBirthDate = gregorian.date(from: DateComponents(year: legacyYear, month: 7, day: 1))
            // `didSet` never fires inside init, so persist the migration here or
            // it's recomputed from a key we're about to delete — and lost.
            if let migrated = resolvedBirthDate {
                d.set(migrated.timeIntervalSince1970, forKey: "profileBirthDate")
            }
            d.removeObject(forKey: "profileBirthYear")
        }
        birthDate = resolvedBirthDate
        biologicalSex = EnergyProfile.BiologicalSex(rawValue: d.string(forKey: "profileSex") ?? "")
            ?? .unspecified
    }
}
