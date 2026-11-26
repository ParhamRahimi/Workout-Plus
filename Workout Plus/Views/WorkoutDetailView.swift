// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let ref: WorkoutRef
    private var workout: Workout { ref.workout }

    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \BodyStat.date, order: .reverse) private var bodyStats: [BodyStat]

    @State private var showFinishConfirm = false
    @State private var showCancelConfirm = false
    @State private var quickLogged: String?

    private var isLive: Bool { engine.isRunning(ref) }

    var body: some View {
        List {
            Section {
                Text(workout.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Exercises") {
                ForEach(workout.exercises) { exercise in
                    let effective = engine.effective(for: exercise)
                    NavigationLink(value: ExerciseRef(planID: ref.planID,
                                                      workoutID: workout.id,
                                                      exercise: exercise)) {
                        ExerciseRow(
                            exercise: effective,
                            isSubstituted: effective.id != exercise.id,
                            done: isLive ? engine.completedSets(for: exercise.id) : 0,
                            planned: max(effective.sets, 1),
                            logged: isLive && engine.isLogged(exercise.id),
                            supersetLabel: exercise.supersetGroup
                        )
                    }
                    // One tap instead of six, for the common case where you did
                    // exactly what the app already suggested.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if isLive {
                            Button {
                                quickLog(exercise)
                            } label: {
                                Label(engine.isLogged(exercise.id) ? "Re-log" : "Same as suggested",
                                      systemImage: "bolt.fill")
                            }
                            .tint(.green)
                        }
                    }
                }
            }

            if let quickLogged {
                Section {
                    Label(quickLogged, systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                }
            }

            if let error = engine.lastSaveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ExerciseRef.self) { exerciseRef in
            ExerciseDetailView(ref: exerciseRef)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if isLive, engine.restEndsAt != nil { restBar }
                bottomBar
            }
        }
        .confirmationDialog("Finish this workout?",
                            isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish & Save") {
                let bw = bodyStats.first(where: { $0.weightKg != nil })?.weightKg
                engine.finish(context: context, settings: settings, bodyweightKg: bw)
            }
            Button("Keep Going", role: .cancel) {}
        }
        .confirmationDialog("Discard this workout?",
                            isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { engine.cancel() }
            Button("Keep Going", role: .cancel) {}
        }
    }

    // MARK: Quick log

    private func quickLog(_ exercise: ExerciseTemplate) {
        let effective = engine.effective(for: exercise)
        // Best-effort only: quick-log is a one-tap shortcut and shouldn't
        // block on a weigh-in popup the way opening the set sheet does — if
        // nothing fresh is on hand it just falls back to nearest-BodyStat
        // resolution later, same as any pre-existing history.
        if effective.loadIsBodyweight, !effective.isTimed {
            _ = engine.resolveBodyweight(from: bodyStats)
        }
        var prefill = SetPrefillService.make(for: effective, context: context, bodyStats: bodyStats)
        let now = Date.now
        for i in prefill.sets.indices {
            prefill.sets[i].isDone = true
            prefill.sets[i].finishedAt = now
        }
        engine.saveSets(prefill.sets,
                        for: exercise.id,
                        restSeconds: settings.restTimerEnabled ? effective.prescribedRest : nil,
                        exerciseName: effective.name)
        let what = prefill.hasHistory ? "as suggested" : "with an empty set sheet"
        quickLogged = "\(effective.name) logged \(what). Open it to adjust."
    }

    // MARK: Rest bar

    @ViewBuilder
    private var restBar: some View {
        if let end = engine.restEndsAt {
            VStack(spacing: 6) {
                // Where to walk, shown only while the clock is running — the
                // one moment it's useful and the one moment you can act on it.
                if let hop = engine.upNext {
                    HStack(spacing: 5) {
                        Image(systemName: engine.upNextIsSuperset
                              ? "arrow.triangle.2.circlepath" : "arrow.turn.down.right")
                            .font(.caption2)
                        Text(engine.upNextIsSuperset ? "Superset now: \(hop)" : "Up next: \(hop)")
                            .font(.caption.bold())
                        Spacer()
                    }
                    .foregroundStyle(engine.upNextIsSuperset ? .cyan : .orange)
                }

                HStack(spacing: 12) {
                    Button {
                        engine.adjustRest(by: -15)
                    } label: {
                        Text("−15").font(.subheadline.bold()).monospacedDigit()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Take 15 seconds off the rest")

                    VStack(spacing: 0) {
                        Text("REST").font(.caption2.bold()).foregroundStyle(.secondary)
                        // Self-updating: no Timer, no re-render storm, and it
                        // stays correct while the app is backgrounded.
                        // `max(end, now)`: a ClosedRange traps if the deadline
                        // has already passed, which it can between the deadline
                        // and the timer task waking up.
                        Text(timerInterval: countdownRange(to: end), countsDown: true)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        engine.adjustRest(by: 15)
                    } label: {
                        Text("+15").font(.subheadline.bold()).monospacedDigit()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Add 15 seconds to the rest")

                    Button("Skip") { engine.stopRest() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func countdownRange(to end: Date) -> ClosedRange<Date> {
        let now = Date.now
        return now...max(end, now)
    }

    // MARK: Bottom bar (3 states)

    @ViewBuilder
    private var bottomBar: some View {
        if isLive {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.restEndsAt != nil ? .green : .orange)
                            .frame(width: 6, height: 6)
                        Text("In progress").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let start = engine.startDate {
                        Text(start, style: .timer)            // auto-updating elapsed time
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                Spacer()
                Button("Discard", role: .destructive) { showCancelConfirm = true }
                    .buttonStyle(.bordered)
                Button("Finish") { showFinishConfirm = true }
                    .buttonStyle(.glassProminent)
            }
            .padding()
            .background(.bar)
        } else if !engine.isActive {
            Button {
                engine.start(workout, planID: ref.planID)
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            Text("Another workout is in progress")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

private struct ExerciseRow: View {
    let exercise: ExerciseTemplate
    let isSubstituted: Bool
    let done: Int
    let planned: Int
    let logged: Bool
    let supersetLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(exercise.category.categoryColor).frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name).font(.headline)
                    if isSubstituted {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.caption2).foregroundStyle(.blue)
                            .accessibilityLabel("Substituted")
                    }
                }
                HStack(spacing: 6) {
                    Text("\(exercise.category)  ·  \(exercise.prescription)  ·  \(exercise.restText) rest")
                        .font(.caption).foregroundStyle(.secondary)
                    if let g = supersetLabel {
                        Text("SUPERSET \(g)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
            }
            Spacer()
            if done >= planned && done > 0 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel("All \(planned) sets done")
            } else if done > 0 {
                Text("\(done)/\(planned)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(done) of \(planned) sets done")
            } else if logged {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    .accessibilityLabel("Logged")
            }
        }
        .padding(.vertical, 2)
    }
}
