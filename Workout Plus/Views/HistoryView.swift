// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var pendingDelete: WorkoutSession?
    @State private var showDeleteOptions = false
    @State private var deleteError: String?
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finish a workout and it'll show up here.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.workoutName).font(.headline)
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        Text("\(session.workingSets.count) sets")
                                        if let d = session.durationText { Text("· \(d)") }
                                        if session.healthKitUUID != nil {
                                            Image(systemName: "heart.fill").foregroundStyle(.pink)
                                        }
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = session
                                    showDeleteOptions = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .disabled(deleting)
            .alert("Deletion incomplete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK") { deleteError = nil }
            } message: { Text(deleteError ?? "") }
            .navigationTitle("History")
            .navigationDestination(for: WorkoutSession.self) { session in
                SessionDetailView(session: session)
            }
            .confirmationDialog("Delete this workout?",
                                isPresented: $showDeleteOptions, titleVisibility: .visible) {
                if let hk = pendingDelete?.healthKitUUID {
                    Button("Delete here and in Health", role: .destructive) {
                        delete(pendingDelete, alsoHealthKit: hk)
                    }
                    Button("Delete here only", role: .destructive) {
                        delete(pendingDelete, alsoHealthKit: nil)
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        delete(pendingDelete, alsoHealthKit: nil)
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                if pendingDelete?.healthKitUUID != nil {
                    Text("This workout was also written to Apple Health. Deleting here alone leaves it in Health until you delete it there.")
                }
            }
        }
    }

    private func delete(_ session: WorkoutSession?, alsoHealthKit hk: String?) {
        guard let session else { return }
        deleting = true
        Task { @MainActor in
            defer { deleting = false }
            if let hk, !(await HealthKitService.shared.deleteWorkout(uuidString: hk)) {
                deleteError = HealthKitService.shared.lastError ?? "Health deletion failed. Your local record was retained so you can retry."
                return
            }
            context.delete(session)
            if let error = context.saveLogging("delete session") {
                context.rollback()
                deleteError = error
            } else { pendingDelete = nil }
        }
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyStat.date, order: .reverse) private var bodyStats: [BodyStat]
    @State private var editing: SetEntry?
    @State private var showNotes = false

    private var energy: EnergyEstimate? {
        let bw = bodyStats.first(where: { $0.weightKg != nil })?.weightKg
        return EnergyService.estimate(session: session,
                                      profile: settings.profile(bodyweightKg: bw))
    }

    /// Grouped by the exercise slot, in the order it was actually performed.
    /// This used to sort by first set number and then re-sort alphabetically,
    /// which discarded the first sort entirely — and `SetEntry` had no ordering
    /// field to recover the real sequence from anyway.
    private var grouped: [(key: String, name: String, sets: [SetEntry])] {
        let byExercise = Dictionary(grouping: session.sets) {
            "\($0.orderIndex)|\($0.exerciseName)"
        }
        return byExercise
            .map { (key: $0.key,
                    name: $0.value.first?.exerciseName ?? "",
                    sets: $0.value.sorted { $0.setNumber < $1.setNumber }) }
            .sorted { a, b in
                let ao = a.sets.first?.orderIndex ?? 0
                let bo = b.sets.first?.orderIndex ?? 0
                if ao != bo { return ao < bo }
                return a.name < b.name
            }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.key) { group in
                Section {
                    ForEach(group.sets) { s in
                        Button {
                            editing = s
                        } label: {
                            HStack {
                                Text(s.isWarmup ? "Warm-up" : "Set \(s.setNumber)")
                                    .foregroundStyle(s.isWarmup ? .orange : .secondary)
                                if let effort = s.effortText {
                                    Text("· \(effort)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(s.summary).monospacedDigit().foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityHint("Edit this set")
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        if let sub = group.sets.first?.substitutedFor {
                            Text("· stood in for \(sub)")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
            }

            if let energy {
                Section("Estimated energy") {
                    LabeledContent("Active energy",
                                   value: "\(Int(energy.activeKcal.rounded())) kcal")
                    Text(energy.rangeText)
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(EnergyService.explanation(energy), id: \.self) { line in
                        Text("• " + line).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section { Text("Editing this log does not change a previously synced Apple Health workout.").font(.caption).foregroundStyle(.secondary) }
            Section("Notes") {
                TextField("How it went, anything that hurt…",
                          text: Binding(get: { session.notes },
                                        set: { session.notes = $0 }),
                          axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { context.saveLogging("session notes") }
            }
        }
        .navigationTitle(session.workoutName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .onDisappear { context.saveLogging("session notes") }
        .sheet(item: $editing) { set in
            EditSetSheet(entry: set)
        }
    }
}

/// A mistyped 100 kg used to permanently corrupt a chart and a PR, with
/// deleting the entire session as the only way out.
private struct EditSetSheet: View {
    let entry: SetEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var seconds: Int = 0
    @State private var isWarmup = false
    @State private var rir: Int?
    @State private var note = ""
    @State private var loaded = false

    private static let weights: [Double] = (0...600).map { Double($0) / 2 }
    private static let repRange: [Int] = Array(0...60)
    private static let secondsRange: [Int] = Array(stride(from: 0, through: 300, by: 5))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if entry.isTimed {
                        Picker("Seconds", selection: $seconds) {
                            ForEach(Self.secondsRange, id: \.self) { Text("\($0) sec").tag($0) }
                        }
                    } else {
                        Picker("Weight (kg)", selection: $weight) {
                            ForEach(Self.weights, id: \.self) {
                                Text($0.formatted(.number.precision(.fractionLength(0...1)))).tag($0)
                            }
                        }
                        Picker("Reps", selection: $reps) {
                            ForEach(Self.repRange, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                }

                Section {
                    Toggle("Warm-up set", isOn: $isWarmup)
                    Picker("How hard?", selection: $rir) {
                        Text("Not recorded").tag(Int?.none)
                        Text("Easy").tag(Int?.some(3))
                        Text("Hard").tag(Int?.some(1))
                        Text("Max").tag(Int?.some(0))
                    }
                } footer: {
                    Text("Warm-up sets are excluded from PRs, weekly volume and stall detection.")
                }

                Section("Note") {
                    TextField("Anything worth remembering", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button("Delete this set", role: .destructive) {
                        context.delete(entry)
                        context.saveLogging("delete set")
                        dismiss()
                    }
                }
            }
            .navigationTitle(entry.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                weight = min(max((entry.weightKg * 2).rounded() / 2, 0), 300)
                reps = min(max(entry.reps, 0), 60)
                seconds = min(max(Int((Double(entry.seconds) / 5).rounded()) * 5, 0), 300)
                isWarmup = entry.isWarmup
                rir = entry.rir
                note = entry.note
            }
        }
    }

    private func save() {
        entry.weightKg = weight
        entry.reps = reps
        entry.seconds = seconds
        entry.isWarmup = isWarmup
        entry.rir = rir
        entry.note = note
        context.saveLogging("edit set")
        dismiss()
    }
}
