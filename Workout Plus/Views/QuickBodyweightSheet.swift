// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  QuickBodyweightSheet.swift
//  Workout Plus
//
//  A minimal, mid-workout weigh-in: just the weight wheel. Presented when
//  logging a bodyweight-relative exercise (assisted pull-up, weighted dip...)
//  and the nearest BodyStat is missing or more than a month old — see
//  WorkoutEngine.resolveBodyweight. Deliberately not the full AddBodyStatSheet
//  (waist, photo, note) — those would be a poor interruption mid-set.
//

import SwiftUI
import os
import SwiftData

struct QuickBodyweightSheet: View {
    var onSave: (Double) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var weight: Double = 70
    @State private var saveError: String?

    // Same grid as AddBodyStatSheet, built from integers so it's bit-identical
    // to snapWeight() and every value stays reachable on the wheel.
    private static let weights: [Double] = (300...2000).map { Double($0) / 10 }   // 30.0-200.0 kg by 0.1

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Your current bodyweight sets today's effective load for this exercise.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Weight (kg)", value: $weight, format: .number).keyboardType(.decimalPad).padding()

                if let saveError {
                    Label("Couldn't save: \(saveError)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)
            .navigationTitle("Quick Weigh-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard weight.isFinite, (1...1000).contains(weight) else { saveError = "Enter a weight from 1–1000 kg."; return }
        let stat = BodyStat(date: .now, weightKg: weight)
        context.insert(stat)
        if let error = context.saveLogging("quick bodyweight") {
            context.delete(stat)
            saveError = error
            return                          // don't dismiss over a lost entry
        }
        if settings.syncBodyweight {
            Task { @MainActor in
                do {
                    let uuid = try await HealthKitService.shared.saveBodyMass(kg: weight, date: stat.date, externalID: stat.id)
                    stat.healthKitUUID = uuid.uuidString
                    stat.syncedToHealth = true
                    context.saveLogging("bodyweight health flag")
                } catch {
                    Log.health.error("Bodyweight sync failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        onSave(weight)
        dismiss()
    }
}
