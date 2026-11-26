// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  SubstituteExerciseSheet.swift
//  Workout Plus
//
//


import SwiftUI

struct SubstituteExerciseSheet: View {
    let slot: ExerciseTemplate

    @Environment(WorkoutEngine.self) private var engine
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// Every exercise across all stored plans, deduped by name.
    private var candidates: [ExerciseTemplate] {
        var seen = Set<String>()
        var out: [ExerciseTemplate] = []
        for plan in planStore.plans {
            for w in plan.workouts {
                for e in w.exercises where !seen.contains(e.name) {
                    seen.insert(e.name)
                    out.append(e)
                }
            }
        }
        return out.sorted {
            ($0.category == slot.category ? 0 : 1, $0.name)
                < ($1.category == slot.category ? 0 : 1, $1.name)
        }
    }

    private var filtered: [ExerciseTemplate] {
        search.isEmpty ? candidates
            : candidates.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Same-category options first. Your logs record the exercise you actually did, tagged as a stand-in for \(slot.name) — so each progression chart stays accurate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(filtered) { ex in
                    Button {
                        engine.substitute(ex, for: slot.id)
                        dismiss()
                    } label: {
                        HStack {
                            Circle().fill(ex.category.categoryColor).frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(ex.name).foregroundStyle(.primary)
                                Text("\(ex.category) · \(ex.prescription)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}