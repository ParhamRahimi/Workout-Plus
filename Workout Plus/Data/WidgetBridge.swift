// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WidgetBridge.swift
//  Workout Plus
//
//  Publishes the small shared snapshot the widget reads, and asks WidgetKit to
//  reload — but only when something actually changed. WidgetKit budgets how
//  often an extension may refresh, and burning that budget on identical
//  timelines is the classic way to end up with a widget that stops updating
//  when it matters.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetBridge {

    static func publish(planStore: PlanStore, engine: WorkoutEngine, context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "showWorkoutDetails") else {
            if WidgetSnapshot().save() { WidgetCenter.shared.reloadAllTimelines() }
            return
        }
        let plan = planStore.activePlan

        // ── Week to date ────────────────────────────────────────────────────
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.date >= weekStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.sets]
        let thisWeek = (try? context.fetch(descriptor)) ?? []
        let setsThisWeek = thisWeek.reduce(0) { $0 + $1.workingSets.count }

        // ── What's next in the rotation ─────────────────────────────────────
        var allDescriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        allDescriptor.fetchLimit = 12          // enough to find this plan's last session
        let recent = (try? context.fetch(allDescriptor)) ?? []
        let lastForPlan = recent.first {
            $0.planID == plan.id || ($0.planID.isEmpty && plan.rotation.contains($0.workoutID))
        }
        let nextID: String
        if let last = lastForPlan, let index = plan.rotation.firstIndex(of: last.workoutID) {
            nextID = plan.rotation[(index + 1) % plan.rotation.count]
        } else {
            nextID = plan.rotation.first ?? plan.workouts.first?.id ?? ""
        }
        let next = plan.workout(id: nextID)

        var snapshot = WidgetSnapshot(
            planName: plan.name,
            nextWorkoutID: nextID,
            nextWorkoutName: next?.name ?? "",
            nextWorkoutFocus: next?.focus ?? "",
            exerciseCount: next?.exercises.count ?? 0,
            setsThisWeek: setsThisWeek,
            sessionsThisWeek: thisWeek.count,
            lastSessionDate: recent.first?.date
        )

        if let live = engine.workout {
            snapshot.liveWorkoutName = live.name
            snapshot.liveProgress = engine.progressText
            snapshot.restEndsAt = engine.restEndsAt
            snapshot.upNext = engine.upNext
        }

        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
