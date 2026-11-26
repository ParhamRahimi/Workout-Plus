// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(WorkoutEngine.self) private var engine
    @Environment(PlanStore.self) private var planStore
    @State private var prefetcher = ImagePrefetcher()
    @State private var showPlans = false
    @State private var showSettings = false

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    private var plan: Plan { planStore.activePlan }

    /// "What's next" has to look at THIS plan's history. Reading the last
    /// session globally meant switching plans handed you a suggestion computed
    /// from a rotation you're no longer running.
    private var suggestedWorkoutID: String {
        let mine = sessions.first {
            $0.planID == plan.id || ($0.planID.isEmpty && plan.rotation.contains($0.workoutID))
        }
        guard let last = mine,
              let idx = plan.rotation.firstIndex(of: last.workoutID)
        else { return plan.rotation.first ?? "A" }
        return plan.rotation[(idx + 1) % plan.rotation.count]
    }

    var body: some View {
        NavigationStack {
            List {
                if let active = engine.workout {
                    Section("In progress") {
                        NavigationLink(value: WorkoutRef(planID: engine.planID ?? plan.id, workout: active)) {
                            HStack {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(active.name).font(.headline)
                                    if let end = engine.restEndsAt {
                                        HStack(spacing: 4) {
                                            Circle().fill(.green).frame(width: 6, height: 6)
                                            Image(systemName: "timer").font(.caption2)
                                            // A ClosedRange traps if the end is
                                            // already in the past.
                                            Text(timerInterval: Date.now...max(end, Date.now),
                                                 countsDown: true)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    } else if let start = engine.startDate {
                                        HStack(spacing: 4) {
                                            Circle().fill(.orange).frame(width: 6, height: 6)
                                            Text(start, style: .timer)
                                                .font(.caption.monospacedDigit())
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Next up") {
                    if let w = plan.workout(id: suggestedWorkoutID) {
                        NavigationLink(value: WorkoutRef(planID: plan.id, workout: w)) {
                            WorkoutRow(workout: w, highlighted: true)
                        }
                    }
                }

                Section("All workouts") {
                    ForEach(plan.workouts) { workout in
                        NavigationLink(value: WorkoutRef(planID: plan.id, workout: workout)) {
                            WorkoutRow(workout: workout, highlighted: false)
                        }
                    }
                }
            }
            .navigationTitle(plan.name)
            .navigationDestination(for: WorkoutRef.self) { ref in
                WorkoutDetailView(ref: ref)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPlans = true } label: {
                        Image(systemName: "square.stack.3d.up.fill")
                    }
                    .accessibilityLabel("Plans")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if prefetcher.isDownloading {
                        Text("\(prefetcher.completed)/\(prefetcher.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Downloading images, \(prefetcher.completed) of \(prefetcher.total)")
                    } else {
                        Button {
                            Task { await prefetcher.downloadAll(for: plan) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .accessibilityLabel("Download all exercise images for offline use")
                    }
                }
            }
            .sheet(isPresented: $showPlans) { PlansView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(workout.id)
                .font(.title2.bold())
                .frame(width: 44, height: 44)
                .background(highlighted ? Color.accentColor : Color.secondary.opacity(0.2),
                            in: .rect(cornerRadius: 12))
                .foregroundStyle(highlighted ? .white : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.headline)
                Text("\(workout.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [WorkoutSession.self, SetEntry.self, BodyStat.self], inMemory: true)
        .environment(WorkoutEngine())
        .environment(PlanStore())
        .environment(AppSettings())
}
