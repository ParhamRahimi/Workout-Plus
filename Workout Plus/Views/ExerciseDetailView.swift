// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

struct ExerciseDetailView: View {
    let ref: ExerciseRef
    private var exercise: ExerciseTemplate { ref.exercise }   // the planned slot

    @Environment(WorkoutEngine.self) private var engine

    @State private var showLogSheet = false
    @State private var showSubstitute = false

    /// What you're actually doing (may differ from the plan).
    private var effective: ExerciseTemplate { engine.effective(for: exercise) }
    private var isSubstituted: Bool { effective.id != exercise.id }

    /// Plan-scoped: without the plan check, opening Plan 2's "Leg Press" while
    /// Plan 1 was live showed the Log Sets button and logged into the wrong
    /// session.
    private var inWorkoutMode: Bool {
        engine.isRunning(ref) &&
        (engine.workout?.exercises.contains { $0.id == exercise.id } ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                HStack {
                    Text(effective.category)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(effective.category.categoryColor.opacity(0.2), in: .capsule)
                        .foregroundStyle(effective.category.categoryColor)
                    Spacer()
                    if inWorkoutMode && engine.isLogged(exercise.id) {
                        Label("Logged", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(effective.prescription)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(effective.restText) rest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Substitution banner (#8)
                if isSubstituted {
                    HStack {
                        Label("Standing in for \(exercise.name)", systemImage: "arrow.triangle.swap")
                            .font(.caption.bold()).foregroundStyle(.blue)
                        Spacer()
                        Button("Undo") { engine.clearSubstitution(for: exercise.id) }
                            .font(.caption)
                    }
                    .padding(10)
                    .background(.blue.opacity(0.1), in: .rect(cornerRadius: 12))
                }

                ExerciseImageSlideshow(imageURLs: effective.imageURLs)

                sectionCard(title: "Where you feel it", systemImage: "target") {
                    Text(effective.feel)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("How to do it", systemImage: "list.number")
                        .font(.headline)
                    ForEach(Array(effective.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold())
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.15), in: .circle)
                            Text(step)
                        }
                    }
                }

                sectionCard(title: "Tip", systemImage: "lightbulb.fill") {
                    Text(effective.tip)
                }
                .tint(.yellow)
            }
            .padding()
        }
        .navigationTitle(effective.name)
        .navigationBarTitleDisplayMode(.inline)
        // Swap + Log buttons only appear while in workout mode.
        .safeAreaInset(edge: .bottom) {
            if inWorkoutMode {
                HStack(spacing: 10) {
                    Button {
                        showSubstitute = true
                    } label: {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Swap this exercise for another")

                    Button {
                        showLogSheet = true
                    } label: {
                        Label(engine.isLogged(exercise.id) ? "Edit Sets" : "Log Sets",
                              systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogSetsSheet(exercise: exercise)
        }
        .sheet(isPresented: $showSubstitute) {
            SubstituteExerciseSheet(slot: exercise)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String, systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            content().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}
