// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  SettingsView.swift
//  Workout Plus
//
//  The Health toggles used to live at the bottom of Progress → Export Data,
//  which is not a place anybody goes looking for settings. They live here now,
//  behind the gear on the Workouts tab, together with the rest-timer options.
//

import SwiftUI
import os
import SwiftData
import UserNotifications
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var planStore

    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \BodyStat.date, order: .reverse) private var bodyStats: [BodyStat]

    @Environment(WorkoutEngine.self) private var engine
    @State private var lockError: String?
    @State private var showErase = false
    @State private var eraseError: String?
    @State private var erasing = false
    @State private var authMessage: String?
    @State private var backfilling = false
    @State private var backfillDone: Int?
    @State private var notificationDenied = false
    @State private var showRemoveEnergyConfirm = false
    @State private var removingEnergy = false
    @State private var removedEnergyMessage: String?
    @State private var shareStatus: HealthKitService.ShareStatus = .notDetermined
    @State private var showHeightWheel = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showExport = false

    // Exercise images
    @State private var imageCount = 0
    @State private var imageBytes = 0
    @State private var warming = false

    // History tags
    @State private var retagPreview: CategoryMap.RetagPreview?
    @State private var showRetagConfirm = false
    @State private var retagDone: String?

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            List {
                // First section on purpose. A free-account build stops
                // launching after seven days with no warning from iOS, and the
                // fix needs a Mac — so the date has to be somewhere you can
                // check before you leave the house, not only in a notification
                // you might have swiped away.
                #if DEBUG
                Section("App signing") {
                    if let profile = BuildExpiry.profile {
                        LabeledContent("Expires", value: profile.expiryText)
                        LabeledContent("Time left") {
                            Text(expiryRemainingText(profile))
                                .foregroundStyle(profile.daysRemaining <= 2 ? .orange : .secondary)
                        }
                        Toggle("Warn me before it expires", isOn: $settings.expiryAlertsEnabled)
                        if notificationDenied {
                            Text("Notifications are turned off for Workout Plus in iOS Settings.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("One warning arrives 6 hours before it runs out. Expiration is set when Apple issues the signing profile; rebuilding with the same profile does not reset it. To renew, move only the Workout Plus app and widget profiles out of ~/Library/Developer/Xcode/UserData/Provisioning Profiles (older Xcode: ~/Library/MobileDevice/Provisioning Profiles), then build and run on your iPhone with automatic signing enabled. Check the new expiration here afterward.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("No provisioning profile in this build — expiry doesn't apply here (simulator or App Store build).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                #endif
                Section("Rest timer") {
                    Toggle("Start rest automatically", isOn: $settings.restTimerEnabled)
                    Toggle("Notify me when rest is up", isOn: Binding(
                        get: { settings.restAlertsEnabled },
                        set: { wants in
                            if wants {
                                Task {
                                    let granted = await RestAlerts.requestPermission()
                                    settings.restAlertsEnabled = granted
                                    notificationDenied = !granted
                                }
                            } else {
                                settings.restAlertsEnabled = false
                                RestAlerts.cancel()
                            }
                        }))
                    .disabled(!settings.restTimerEnabled)

                    if notificationDenied {
                        Text("Notifications are turned off for Workout Plus in iOS Settings.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("Rest length comes from each exercise's prescription — long for heavy 5–8s, short for high-rep isolation. You can add or subtract 15 seconds on the fly.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Apple Health") {
                    if !HealthKitService.shared.isAvailable {
                        Text("Health data isn't available on this device.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        // A real Toggle would be a lie: an app can ask for
                        // Health access but has no way to revoke it — only you
                        // can, from inside Health. So this shows the live state
                        // and hands you to the right place to change it.
                        LabeledContent {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(shareStatus.title)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Label("Health access", systemImage: "heart.fill")
                        }
                        .accessibilityElement(children: .combine)

                        switch shareStatus {
                        case .notDetermined:
                            Button {
                                Task {
                                    let ok = await HealthKitService.shared.requestAuthorization()
                                    shareStatus = HealthKitService.shared.shareStatus
                                    authMessage = ok
                                        ? nil
                                        : (HealthKitService.shared.lastError
                                           ?? "Nothing was granted. You can change it in Health → Sharing → Apps.")
                                }
                            } label: {
                                Label("Connect to Health", systemImage: "link")
                            }
                        case .denied, .partial, .authorized:
                            Button {
                                if let url = URL(string: "x-apple-health://") { openURL(url) }
                            } label: {
                                Label(shareStatus == .authorized
                                      ? "Change permissions in Health"
                                      : "Turn on the rest in Health",
                                      systemImage: "arrow.up.forward.app")
                            }
                        }

                        Text("Health never tells an app whether it may READ your data — only whether it may write. This shows the write side, which is everything this app puts into Health.")
                            .font(.caption2).foregroundStyle(.secondary)

                        Toggle("Sync workouts", isOn: $settings.syncWorkouts)
                        Toggle("Sync bodyweight", isOn: $settings.syncBodyweight)
                        Toggle("Write estimated calories", isOn: $settings.writeEstimatedCalories)

                        if let sample = latestEstimate {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your last session would have written \(Int(sample.activeKcal.rounded())) kcal. \(sample.rangeText).")
                                    .font(.caption.bold())
                                ForEach(EnergyService.explanation(sample), id: \.self) { line in
                                    Text("• " + line)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        Text("Still an estimate — nothing here measures your oxygen use. It now counts only real training time (long idle gaps are dropped), scales to your resting metabolic rate rather than raw bodyweight, and moves with how densely packed the session was. This estimate has not been validated for individual accuracy.")
                            .font(.caption2).foregroundStyle(.secondary)

                        if settings.writeEstimatedCalories {
                            Label("If you record this workout on an Apple Watch as well, turn this off — otherwise both estimates land in the same Move ring and it counts twice.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }

                        Text("This only ever applies to workouts you finish from now on. Past sessions are never given a calorie figure retroactively — \"Send past workouts to Health\" deliberately sends no energy at all.")
                            .font(.caption2).foregroundStyle(.secondary)

                        if syncedSessionCount > 0 {
                            Button(role: .destructive) {
                                showRemoveEnergyConfirm = true
                            } label: {
                                if removingEnergy {
                                    Label("Removing…", systemImage: "arrow.triangle.2.circlepath")
                                } else {
                                    Label("Remove estimated calories from Health", systemImage: "flame.slash")
                                }
                            }
                            .disabled(removingEnergy)

                            if let removedEnergyMessage {
                                Text(removedEnergyMessage)
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }

                        Button {
                            Task { await backfill() }
                        } label: {
                            if backfilling {
                                Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Send past workouts to Health",
                                      systemImage: "square.and.arrow.up.on.square")
                            }
                        }
                        .disabled(backfilling)

                        if let backfillDone {
                            Text("Synced \(backfillDone) workout(s).")
                                .font(.caption).foregroundStyle(.green)
                        }
                        if let authMessage {
                            Text(authMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Exercise images") {
                    Toggle("Allow exercise image downloads", isOn: $settings.remoteImagesEnabled)
                    Text("Off by default. When enabled, image requests contact raw.githubusercontent.com, which receives your IP address and request metadata. Only the supported exercise library is allowed.").font(.caption)
                    LabeledContent("Saved on this phone",
                                   value: "\(imageCount) images · \(byteText)")
                    Button {
                        Task {
                            warming = true
                            await DiskImageCache.warm(planStore.allImageURLs)
                            await refreshImageStats()
                            warming = false
                        }
                    } label: {
                        if warming {
                            Label("Downloading…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Download every image now", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(warming)

                    Button(role: .destructive) {
                        Task {
                            await DiskImageCache.shared.removeOrphans(keeping: planStore.allImageURLs)
                            await refreshImageStats()
                        }
                    } label: {
                        Label("Free up space", systemImage: "trash")
                    }

                    Text("Exercise images are optional downloads from GitHub. The cache is limited to 100 MB and excluded from device backups. Images may need downloading again after a device change.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("History tags") {
                    if let preview = retagPreview, preview.total > 0 {
                        Text("\(preview.total) logged set(s) are tagged differently from this plan.")
                            .font(.caption)
                        ForEach(preview.changes.prefix(8), id: \.self) { line in
                            Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        if preview.changes.count > 8 {
                            Text("…and \(preview.changes.count - 8) more")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            showRetagConfirm = true
                        } label: {
                            Label("Re-tag history to match this plan", systemImage: "tag")
                        }
                    } else if let retagDone {
                        Label(retagDone, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Everything in your history already matches this plan's muscle groups.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text("Every plan invents its own tags — one calls face pulls \"Posture\", the next calls them \"Upper Back\". The charts already fold obvious synonyms together. This rewrites the stored tags so they match \(planStore.activePlan.name) exactly, which is the only way to fix a disagreement a synonym list can't guess.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("About you") {
                    // A wheel, not a slider. A slider is for a value you're
                    // adjusting by feel where the exact number is secondary;
                    // height is an exact number you set once and never touch
                    // again, and dragging a thumb to land on 172 rather than
                    // 171 is needless precision work. It stays collapsed until
                    // tapped so Settings isn't 150pt taller for a field you
                    // will use approximately once — the same behaviour a
                    // DatePicker has.
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showHeightWheel.toggle() }
                    } label: {
                        LabeledContent("Height") {
                            Text(settings.heightCm > 0 ? "\(Int(settings.heightCm)) cm" : "Set")
                                .monospacedDigit()
                                .foregroundStyle(showHeightWheel ? Color.accentColor
                                                 : (settings.heightCm > 0 ? .primary : .secondary))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Height")
                    .accessibilityValue(settings.heightCm > 0
                                        ? "\(Int(settings.heightCm)) centimetres" : "not set")

                    if showHeightWheel {
                        Picker("Height", selection: heightBinding) {
                            ForEach(Self.heightChoices, id: \.self) { cm in
                                Text("\(cm) cm").tag(cm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .clipped()
                    }

                    Toggle("Use date of birth for the optional estimate", isOn: Binding(get: { settings.birthDate != nil }, set: { settings.birthDate = $0 ? Calendar.current.date(byAdding: .year, value: -30, to: .now) : nil }))
                    if settings.birthDate != nil {
                    DatePicker("Date of birth",
                               selection: birthDateBinding,
                               in: earliestBirthDate...Date.now,
                               displayedComponents: .date)
                    }

                    Picker("Sex", selection: $settings.biologicalSex) {
                        ForEach(EnergyProfile.BiologicalSex.allCases) { Text($0.rawValue).tag($0) }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Label(bodyDataHint, systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Everything in this app is metric — centimetres and kilograms throughout.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Used for one thing only: turning your bodyweight into a resting metabolic rate for the calorie estimate. It stays on this device, isn't included in JSON exports. Device backups may include it.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export & backup", systemImage: "square.and.arrow.up")
                    }
                    if planStore.loadFailed {
                        ShareLink("Export original plans for recovery", item: PlanStore.recoveryURL)
                    }
                    if let error = planStore.lastSaveError {
                        Label("Your plans couldn't be saved: \(error)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Delete all app data", role: .destructive) { showErase = true }
                    Text("Removes local training records, photos, custom plans, settings, and caches. Previously shared files and device backups remain. Health deletion is a separate choice; legacy unlinked samples may need deletion in Health.").font(.caption)
                    if let eraseError { Text(eraseError).foregroundStyle(.red) }
                }
                Section("Privacy") {
                    Toggle("Show workout details in widgets and Live Activities", isOn: $settings.showWorkoutDetails)
                    Toggle("Require device authentication", isOn: Binding(get: { settings.appLockEnabled }, set: setAppLock))
                    if let lockError { Text(lockError).font(.caption).foregroundStyle(.orange) }
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }
                    Link("Support and feedback", destination: URL(string: "https://github.com/ParhamRahimi/Workout-Plus/issues")!)
                    Text("Progress photos use protected app storage and are excluded from JSON/CSV exports. Device backups may include photos and other app data. Optional image downloads contact GitHub; workout logs are not sent to an app server.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(erasing)
            .confirmationDialog("Permanently delete app data?", isPresented: $showErase, titleVisibility: .visible) {
                Button("Delete local data only", role: .destructive) { erase(alsoHealth: false) }
                Button("Delete local and linked Health data", role: .destructive) { erase(alsoHealth: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Export a training-data backup first if needed. Photos are not in that backup. This action cannot remove existing exports or device backups.") }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showExport) { ExportView() }
            .confirmationDialog("Remove estimated calories from Apple Health?",
                                isPresented: $showRemoveEnergyConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task { await removeEstimatedEnergy() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes only the energy figures this app wrote, from this app's own workouts. The workouts stay in Health, and nothing an Apple Watch recorded is touched.")
            }
            .confirmationDialog("Re-tag \(retagPreview?.total ?? 0) logged set(s)?",
                                isPresented: $showRetagConfirm, titleVisibility: .visible) {
                Button("Re-tag", role: .destructive) { applyRetag() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This rewrites the muscle-group tag stored on those sets. Weights, reps and dates are untouched, and a backup taken beforehand can put the old tags back.")
            }
            .onChange(of: scenePhase) {
                // You may have changed permissions in Health and come back.
                if scenePhase == .active {
                    shareStatus = HealthKitService.shared.shareStatus
                    Task { notificationDenied = await notificationsAreDenied() }
                }
            }
            .task {
                shareStatus = HealthKitService.shared.shareStatus
                notificationDenied = await notificationsAreDenied()
                await refreshImageStats()
                retagPreview = CategoryMap.retag(sessions: sessions,
                                                 to: planStore.activePlan,
                                                 apply: false)
            }
        }
    }

    /// What the most recent finished session would write, so the estimate can
    /// be judged before it's switched on rather than after.
    private var latestEstimate: EnergyEstimate? {
        guard let last = sessions.last(where: { $0.endDate != nil }) else { return nil }
        let bw = bodyStats.first(where: { $0.weightKg != nil })?.weightKg
        return EnergyService.estimate(session: last, profile: settings.profile(bodyweightKg: bw))
    }

    private func setAppLock(_ enabled: Bool) {
        if !enabled { settings.appLockEnabled = false; return }
        Task { @MainActor in
            let auth = LAContext()
            guard auth.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                lockError = "Set a device passcode in iOS Settings before enabling app lock."
                return
            }
            do {
                if try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Enable protection for private training data") {
                    settings.appLockEnabled = true; lockError = nil
                }
            } catch { lockError = "App lock was not enabled. Authentication was cancelled or unavailable." }
        }
    }

    private func erase(alsoHealth: Bool) {
        erasing = true
        Task { @MainActor in
            defer { erasing = false }
            do {
                try await DataDeletion.erase(context: context, plans: planStore, engine: engine, alsoHealth: alsoHealth)
                dismiss()
            } catch { eraseError = "Deletion incomplete: \(error.localizedDescription). Retry to finish; existing backups and exports are unaffected." }
        }
    }

    private var byteText: String {
        ByteCountFormatter.string(fromByteCount: Int64(imageBytes), countStyle: .file)
    }

    private func refreshImageStats() async {
        let s = await DiskImageCache.shared.stats()
        imageCount = s.count
        imageBytes = s.bytes
    }

    private func applyRetag() {
        let result = CategoryMap.retag(sessions: sessions,
                                       to: planStore.activePlan,
                                       apply: true)
        context.saveLogging("retag history")
        retagDone = "Re-tagged \(result.total) set(s) to match \(planStore.activePlan.name)."
        retagPreview = CategoryMap.retag(sessions: sessions,
                                         to: planStore.activePlan,
                                         apply: false)
    }

    /// Wider range; direct entry is also available.
    private static let heightChoices: [Int] = Array(50...280)

    /// Opens on 170 when nothing is set, rather than on the bottom of the wheel.
    private var heightBinding: Binding<Int> {
        Binding(
            get: {
                let current = Int(settings.heightCm.rounded())
                return Self.heightChoices.contains(current) ? current : 170
            },
            set: { settings.heightCm = Double($0) }
        )
    }

    /// Read back rather than remembered: the answer can change in iOS Settings
    /// while this screen is open, and the rest-timer toggle only ever knew the
    /// result of the one time it asked.
    private func notificationsAreDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Days and hours from a calendar difference, never from dividing seconds:
    /// a device may use the Persian calendar and the project rule is to let the
    /// calendar do date arithmetic.
    private func expiryRemainingText(_ profile: BuildExpiry.Profile) -> String {
        guard !profile.hasExpired else { return "Expired" }
        let parts = Calendar.current.dateComponents([.day, .hour], from: .now, to: profile.expires)
        let days = parts.day ?? 0
        let hours = parts.hour ?? 0
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        return "\(hours)h"
    }

    private var statusColor: Color {
        switch shareStatus {
        case .authorized:    return .green
        case .partial:       return .yellow
        case .denied:        return .orange
        case .notDetermined: return .secondary
        }
    }

    /// Nobody was born more than 120 years ago.
    private var earliestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
    }

    /// A sensible starting point the first time the picker is opened, rather
    /// than today's date, which nobody's birthday is.
    private var birthDateBinding: Binding<Date> {
        Binding(
            get: {
                settings.birthDate
                    ?? Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    ?? .now
            },
            set: { settings.birthDate = $0 }
        )
    }

    /// Says out loud which calendar the picker above is showing, and gives the
    /// Gregorian year alongside it, because on a Persian-calendar device
    /// a local year and a Gregorian year are the same birthday and it is not obvious which one
    /// a field is asking for.
    private var bodyDataHint: String {
        // The localised calendar name lives on Locale, not Calendar.
        let calendarName = Locale.current
            .localizedString(for: Calendar.current.identifier)
            ?? "\(Calendar.current.identifier)"

        guard let birth = settings.birthDate, let age = settings.age else {
            return "Dates are shown in the \(calendarName) calendar — your device setting."
        }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let gregorianYear = gregorian.component(.year, from: birth)
        let localYear = Calendar.current.component(.year, from: birth)

        if gregorianYear == localYear {
            return "Born \(gregorianYear) · age \(age). Shown in the \(calendarName) calendar."
        }
        return "Born \(localYear) in the \(calendarName) calendar — \(gregorianYear) Gregorian · age \(age)."
    }

    private var syncedSessionCount: Int {
        sessions.filter { $0.healthKitUUID != nil }.count
    }

    private func removeEstimatedEnergy() async {
        removingEnergy = true
        let uuids = sessions.compactMap(\.healthKitUUID)
        let result = await HealthKitService.shared.deleteEstimatedEnergy(fromWorkoutUUIDs: uuids)
        removedEnergyMessage = result.samples == 0
            ? "Nothing to remove — no calorie figures from this app were in Health."
            : "Removed \(result.samples) calorie entr(ies) from \(result.workouts) workout(s)."
        removingEnergy = false
    }

    private func backfill() async {
        backfilling = true
        var count = 0
        for session in sessions where session.healthKitUUID == nil {
            guard let end = session.endDate,
                  end.timeIntervalSince(session.date) > 60 else { continue }
            let summary = session.workingSets
                .map { "\($0.exerciseName) \($0.summary)" }
                .joined(separator: "; ")
            do {
                let uuid = try await HealthKitService.shared.saveWorkout(
                    start: session.date, end: end,
                    externalID: session.id,
                    exerciseSummary: summary,
                    energyKcal: nil
                )
                session.healthKitUUID = uuid.uuidString
                count += 1
            } catch {
                Log.health.error("Backfill failed: \(error.localizedDescription, privacy: .private)")
                continue
            }
        }
        context.saveLogging("health backfill")
        backfillDone = count
        backfilling = false
    }
}
