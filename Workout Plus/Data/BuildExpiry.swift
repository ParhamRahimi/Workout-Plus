// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  BuildExpiry.swift
//  Workout Plus
//
//  A free Apple Developer account signs with a provisioning profile that has
//  `TimeToLive = 7`: seven days, then the app refuses to launch. There is no
//  warning from iOS — you find out at the gym, holding a phone that won't open
//  the thing you came to use.
//
//  Two things are worth knowing and neither is guessable:
//
//  1. The seven days run from when the *profile* was created, not from when you
//     built. Rebuilding on day 3 against a profile Xcode already has reuses it,
//     so the new build still dies on day 7. That is why this reads the real
//     expiry out of the signed profile instead of storing "build date + 7".
//  2. The profile is embedded in the app bundle as `embedded.mobileprovision`,
//     a CMS-signed blob with an XML plist inside it. iOS has no CMSDecoder, so
//     the plist is located by scanning for its delimiters — the standard
//     approach, and the payload is Apple's own signed data, not user input.
//
//  App Store and simulator builds have no embedded profile at all, so
//  everything here degrades to "no expiry known" rather than lying.
//

import Foundation
import os
import UserNotifications

nonisolated enum BuildExpiry {

    struct Profile {
        let name: String
        let created: Date?
        let expires: Date
        /// Nominal lifetime in days as Apple issued it — 7 for a free account,
        /// 365 for a paid one.
        let timeToLiveDays: Int?

        var hasExpired: Bool { expires <= .now }
        var secondsRemaining: TimeInterval { expires.timeIntervalSinceNow }

        /// Whole days left, via calendar arithmetic rather than dividing a
        /// number of seconds — a device may use the Persian calendar and the
        /// rule in this project is to let the calendar do date maths.
        var daysRemaining: Int {
            Calendar.current.dateComponents([.day], from: .now, to: expires).day ?? 0
        }

        /// "Sat 3 Sep, 12:18" in whatever calendar and locale the device uses.
        var expiryText: String {
            expires.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// Read once. The profile cannot change while the process is alive.
    static let profile: Profile? = readProfile()

    // MARK: Notifications

    /// One warning, six hours out. Deliberately the only one: a second and
    /// third reminder for the same deadline trains you to swipe the first one
    /// away, and this alert only works if it still means something.
    static let leadTime: TimeInterval = 6 * 3600

    private static let identifier = "workout-plus.build-expiry"

    /// Ids written by an earlier version of this file, which scheduled a
    /// three-day, one-day and at-expiry alert as well. Cleared so a phone that
    /// ran that build doesn't keep firing them.
    private static let retiredIdentifiers = (0...3).map { "workout-plus.build-expiry.\($0)" }

    /// Re-schedules the pending expiry warning. Safe to call on each launch —
    /// it clears its own notification first, so repeated calls never stack up.
    ///
    /// Called at launch specifically because a sideloaded app gets reinstalled
    /// every week, and a reinstall wipes pending notifications. The launch after
    /// the rebuild is the only reliable moment to put it back.
    static func scheduleAlerts(enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier] + retiredIdentifiers)

        guard enabled, let profile, !profile.hasExpired else { return }

        let fireDate = profile.expires.addingTimeInterval(-leadTime)
        guard fireDate > .now else { return }

        // Ask only if nobody has been asked yet; a previous "no" is not
        // something to nag about on every launch.
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
            } catch {
                Log.data.error("Expiry alert permission failed: \(error.localizedDescription, privacy: .private)")
                return
            }
        case .denied:
            return
        default:
            break
        }

        add(
            identifier: identifier,
            title: "Workout Plus expires in 6 hours",
            body: "Signing runs out \(profile.expiryText). Renew the signing profile, then build and run on your iPhone from Xcode before then or the app won't open.",
            at: fireDate
        )
    }

    private static func add(identifier: String, title: String, body: String, at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // This is a deadline you cannot recover from once it passes, so it is
        // allowed through Focus.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.data.error("Expiry alert failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    static func cancelAlerts() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier] + retiredIdentifiers)
    }

    // MARK: In-app banner

    /// How loud the banner should be: above 2 = hidden, 2 = two days out, 1 = one day out,
    /// 0 = under a day, -1 = already dead.
    static func bannerLevel(for profile: Profile) -> Int {
        profile.hasExpired ? -1 : profile.daysRemaining
    }

    private static let dismissalKey = "expiryBannerDismissed"

    /// Dismissal is remembered against the expiry date *and* the level, so:
    /// swiping the amber two-day banner away keeps it away, but the red
    /// one-day escalation still gets one chance to be seen, and renewing the
    /// profile — which moves the expiry date — starts over. Persisted rather than held
    /// in memory, or every trip back into the app would bring it back.
    static func bannerIsDismissed(for profile: Profile) -> Bool {
        UserDefaults.standard.string(forKey: dismissalKey) == dismissalToken(for: profile)
    }

    static func dismissBanner(for profile: Profile) {
        UserDefaults.standard.set(dismissalToken(for: profile), forKey: dismissalKey)
    }

    private static func dismissalToken(for profile: Profile) -> String {
        "\(Int(profile.expires.timeIntervalSince1970))#\(bannerLevel(for: profile))"
    }

    // MARK: Reading the embedded profile

    private static func readProfile() -> Profile? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            // Simulator, or an App Store build. Not an error.
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            Log.data.error("Could not read embedded.mobileprovision")
            return nil
        }
        guard let plist = embeddedPlist(in: data) else {
            Log.data.error("embedded.mobileprovision had no readable plist")
            return nil
        }
        guard let expires = plist["ExpirationDate"] as? Date else {
            Log.data.error("Provisioning profile has no ExpirationDate")
            return nil
        }
        return Profile(
            name: plist["Name"] as? String ?? "Provisioning profile",
            created: plist["CreationDate"] as? Date,
            expires: expires,
            timeToLiveDays: plist["TimeToLive"] as? Int
        )
    }

    /// The file is DER-encoded CMS with the plist sitting in the clear inside
    /// the signed payload. Scanning for `<?xml` … `</plist>` is how this is done
    /// on iOS; `.backwards` for the terminator so a `</plist>` that happened to
    /// appear inside the profile's own data can't truncate it.
    private static func embeddedPlist(in data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)) else { return nil }
        guard let end = data.range(
            of: Data("</plist>".utf8),
            options: .backwards,
            in: start.lowerBound..<data.endIndex
        ) else { return nil }

        let xml = Data(data[start.lowerBound..<end.upperBound])
        guard let any = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil),
              let dict = any as? [String: Any] else { return nil }
        return dict
    }
}
