// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

struct PlanEditorView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var plan: Plan
    @State private var error: String?

    static func newPlan() -> Plan {
        Plan(id: UUID().uuidString, name: "My Plan", summary: "", daysPerWeek: 3, rotation: ["A"], workouts: [newWorkout(id: "A")])
    }
    static func newWorkout(id: String = UUID().uuidString) -> Workout {
        Workout(id: id, name: "Workout", focus: "", exercises: [newExercise()])
    }
    static func newExercise() -> ExerciseTemplate {
        var e = ExerciseTemplate(name: "Exercise", category: "Other", sets: 3, repRangeLow: 8, repRangeHigh: 12, isTimed: false, imageURLs: [], feel: "", steps: [], tip: "")
        e.explicitID = UUID().uuidString
        return e
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name", text: $plan.name)
                    TextField("Summary", text: $plan.summary, axis: .vertical)
                    Stepper("Days per week: \(plan.daysPerWeek)", value: $plan.daysPerWeek, in: 1...7)
                }
                Section("Workouts — rotation follows this order") {
                    ForEach($plan.workouts) { $workout in
                        NavigationLink(workout.name) { WorkoutEditor(workout: $workout) }
                    }
                    .onDelete { plan.workouts.remove(atOffsets: $0) }
                    .onMove { plan.workouts.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add workout") { plan.workouts.append(Self.newWorkout()) }.disabled(plan.workouts.count >= 14)
                }
                Text("IDs are retained when you rename items. Editing prescriptions does not rewrite logged sessions. Use manageable loads and seek instruction for unfamiliar exercises. Metric units only.").font(.caption)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            plan.rotation = plan.workouts.map(\.id)
                            _ = try store.importPlan(from: JSONEncoder().encode(plan), makeActive: false)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}

private struct WorkoutEditor: View {
    @Binding var workout: Workout
    var body: some View {
        Form {
            TextField("Workout name", text: $workout.name)
            TextField("Focus", text: $workout.focus, axis: .vertical)
            Section("Exercises") {
                ForEach($workout.exercises) { $exercise in
                    NavigationLink(exercise.name) { ExerciseEditor(exercise: $exercise) }
                }
                .onDelete { workout.exercises.remove(atOffsets: $0) }
                .onMove { workout.exercises.move(fromOffsets: $0, toOffset: $1) }
                Button("Add exercise") { workout.exercises.append(PlanEditorView.newExercise()) }.disabled(workout.exercises.count >= 40)
            }
        }.navigationTitle("Workout").toolbar { EditButton() }
    }
}

private struct ExerciseEditor: View {
    @Binding var exercise: ExerciseTemplate
    var body: some View {
        Form {
            TextField("Exercise name", text: $exercise.name)
            TextField("Category", text: $exercise.category)
            Stepper("Sets: \(exercise.sets)", value: $exercise.sets, in: 1...20)
            Toggle("Timed (targets in seconds)", isOn: $exercise.isTimed)
            TextField("Minimum target", value: $exercise.repRangeLow, format: .number).keyboardType(.numberPad)
            TextField("Maximum target", value: $exercise.repRangeHigh, format: .number).keyboardType(.numberPad)
            Toggle("Bodyweight-relative load", isOn: Binding(get: { exercise.loadIsBodyweight }, set: { exercise.isBodyweight = $0 }))
            Toggle("Assisted by default", isOn: Binding(get: { exercise.loadIsAssistance }, set: { exercise.isAssisted = $0 }))
            TextField("Weight increment (kg)", value: Binding(get: { exercise.weightIncrementKg ?? 2.5 }, set: { exercise.weightIncrementKg = $0 }), format: .number).keyboardType(.decimalPad)
            TextField("Rest (seconds)", value: Binding(get: { exercise.restSeconds ?? exercise.prescribedRest }, set: { exercise.restSeconds = $0 }), format: .number).keyboardType(.numberPad)
            TextField("Technique notes", text: $exercise.tip, axis: .vertical)
        }.navigationTitle("Exercise")
        .onAppear { if exercise.explicitID == nil { exercise.explicitID = exercise.id } }
    }
}
