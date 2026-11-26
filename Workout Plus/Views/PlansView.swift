// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

struct PlansView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImport = false
    @State private var editingPlan: Plan?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Your plans") {
                    ForEach(planStore.plans) { plan in
                        Button {
                            planStore.activePlanID = plan.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.name).font(.headline).foregroundStyle(Color.primary)
                                    Text("\(plan.workouts.count) workouts · \(plan.daysPerWeek)×/week")
                                        .font(.caption).foregroundStyle(Color.primary.opacity(0.75))
                                }
                                Spacer()
                                if plan.id == planStore.activePlanID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(plan.id == planStore.activePlanID ? "Selected" : "Not selected")
                        .swipeActions(edge: .leading) { Button("Edit") { editingPlan = plan }.tint(.blue) }
                    }
                    .onDelete(perform: deletePlans)
                }
            }
            .navigationTitle("Plans")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Create plan") { editingPlan = PlanEditorView.newPlan() }
                        Button("Import JSON") { showImport = true }
                    } label: { Label("Add plan", systemImage: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Plan not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .sheet(item: $editingPlan) { plan in PlanEditorView(plan: plan) }
            .sheet(isPresented: $showImport) { ImportPlanView() }
        }
    }

    private func deletePlans(_ offsets: IndexSet) {
        let selected = offsets.map { planStore.plans[$0] }
        do { for plan in selected { try planStore.delete(plan) } }
        catch { self.error = error.localizedDescription }
        // Deliberately NOT sweeping the image cache here. Those exercises still
        // appear in your logged history, and re-downloading them later assumes
        // the source URL still works. Settings has an explicit "free up space"
        // button for when you actually want the disk back.
    }
}
