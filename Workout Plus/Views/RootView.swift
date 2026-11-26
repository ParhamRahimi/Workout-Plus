// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData
import LocalAuthentication

struct RootView: View {
    @State private var engine = WorkoutEngine()
    @State private var planStore = PlanStore()
    @State private var settings = AppSettings()
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var pending: WorkoutSnapshot?
    @State private var showResume = false
    @State private var isLocked = true
    @State private var unlocking = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    private var tabs: some View {
        TabView {
            Tab("Workouts", systemImage: "dumbbell.fill") { HomeView() }
            Tab("History", systemImage: "clock.arrow.circlepath") { HistoryView() }
            Tab("Progress", systemImage: "chart.xyaxis.line") { ReportsView() }
            Tab("Body", systemImage: "figure.stand") { BodyView() }
        }
        .environment(engine)
        .environment(planStore)
        .environment(settings)
    }

    private var privateTabs: some View {
        tabs
            .background(PrivacyWindowCover(isVisible: scenePhase != .active || (settings.appLockEnabled && isLocked), canUnlock: scenePhase == .active && settings.appLockEnabled && isLocked, onUnlock: { Task { await unlock() } }).frame(width: 0, height: 0))
            .safeAreaInset(edge: .top) {
                VStack {
                    signingBanner
                    if planStore.loadFailed {
                        Label("Saved plans need recovery. The original file is preserved. Open Settings → Data to export it.", systemImage: "exclamationmark.triangle")
                            .font(.caption).padding().background(.orange, in: .rect(cornerRadius: 12))
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutDataErased)) { _ in
                engine = WorkoutEngine(); planStore = PlanStore(); settings = AppSettings()
                pending = nil; showResume = false
            }
            .onChange(of: settings.restAlertsEnabled, initial: true) { engine.restAlertsEnabled = settings.restAlertsEnabled }
            .onChange(of: settings.appLockEnabled) { isLocked = false }
            .onChange(of: settings.showWorkoutDetails) {
                if !settings.showWorkoutDetails { LiveWorkoutActivity.end(); RestAlerts.cancel() }
                republish()
            }
    }

    var body: some View {
        privateTabs
            .onChange(of: scenePhase) {
                if scenePhase == .background { isLocked = true }
                if scenePhase == .active, settings.appLockEnabled, isLocked { Task { await unlock() } }
                republish()
            }
            .onChange(of: engine.workout?.id) { republish() }
            .onChange(of: engine.restEndsAt) { republish() }
            .onChange(of: engine.progressText) { republish() }
            .onChange(of: planStore.activePlanID) { republish() }
            .task { await prepare() }
            .alert("Unfinished workout", isPresented: $showResume, presenting: pending) { snapshot in
                Button("Resume") { engine.resume(snapshot, fallbackPlanID: planStore.activePlanID); pending = nil }
                Button("Discard", role: .destructive) {
                    engine.clearSnapshot(); LiveWorkoutActivity.end(); pending = nil
                }
            } message: { snapshot in
                Text("\(snapshot.workout.name) from \(snapshot.startDate.formatted(date: .abbreviated, time: .shortened)) — \(snapshot.logged.count) exercise(s) logged.")
            }
            .fullScreenCover(isPresented: Binding(get: { !hasCompletedWelcome && (!settings.appLockEnabled || !isLocked) }, set: { _ in })) {
                WelcomeView { hasCompletedWelcome = true }
            }
    }

    @ViewBuilder private var signingBanner: some View {
        #if DEBUG
        if let profile = BuildExpiry.profile, BuildExpiry.bannerLevel(for: profile) <= 2,
           !BuildExpiry.bannerIsDismissed(for: profile) {
            Label("Development build expires \(profile.expiryText). Renew signing before it expires.", systemImage: "hourglass")
                .font(.caption).padding().background(.orange, in: .rect(cornerRadius: 12))
        }
        #endif
    }

    @MainActor private func prepare() async {
        ExportService.cleanup()
        if settings.appLockEnabled { await unlock() }
        #if DEBUG
        await BuildExpiry.scheduleAlerts(enabled: settings.expiryAlertsEnabled)
        #endif
        republish()
        if !engine.isActive, let snapshot = engine.pendingSnapshot() { pending = snapshot; showResume = true }
        else if !engine.isActive { LiveWorkoutActivity.adoptOrEndOrphans(activeWorkout: nil) }
    }

    @MainActor private func unlock() async {
        guard !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        if (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "View private workout and body data")) == true { isLocked = false }
    }

    private func republish() { WidgetBridge.publish(planStore: planStore, engine: engine, context: context) }
}
