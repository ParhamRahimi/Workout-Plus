// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import os
import SwiftData
import PhotosUI

struct AddBodyStatSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var healthSettings

    @State private var date = Date.now
    @State private var weight: Double = 70
    @State private var includeWeight = true
    @State private var note = ""

    @State private var waist: Double = 80
    @State private var includeWaist = true

    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var saveError: String?

    @Query(sort: \BodyStat.date, order: .reverse) private var stats: [BodyStat]

    // Built from integers, not `stride(by: 0.1)`: a 0.1 stride accumulates
    // floating-point drift, so the wheel's own values stop being bit-identical
    // to anything snapWeight() produces and the Picker silently matches no tag.
    private static let weights: [Double] = (10...10000).map { Double($0) / 10 }   // 30.0-200.0 kg by 0.1
    private static let waists: [Double] = (2...1000).map { Double($0) / 2 }      // 55.0-130.0 cm by 0.5

    /// Snap onto the wheel's grid AND clamp into range - an out-of-range value
    /// has no tag either, which fails just as silently.
    private static func snapWeight(_ w: Double) -> Double {
        min(max((w * 10).rounded() / 10, weights.first!), weights.last!)
    }

    private static func snapWaist(_ w: Double) -> Double {
        min(max((w * 2).rounded() / 2, waists.first!), waists.last!)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }

                Section("Bodyweight") {
                    Toggle("Log weight", isOn: $includeWeight)
                    if includeWeight {
                        TextField("Weight (kg)", value: $weight, format: .number).keyboardType(.decimalPad)
                    }
                }

                Section("Waist") {
                    Toggle("Log waist", isOn: $includeWaist)
                    if includeWaist {
                        TextField("Waist (cm)", value: $waist, format: .number).keyboardType(.decimalPad)
                    }
                    Text("Measure at the navel, first thing in the morning, relaxed. Same conditions every time.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Progress photo") {
                    if let image = pickedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(.rect(cornerRadius: 12))
                        Button("Remove photo", role: .destructive) {
                            pickedImage = nil; photoItem = nil
                        }
                    } else {
                        HStack {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderless)                    // <-- add
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                            Spacer()

                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Library", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.borderless)                    // <-- add
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("How you're feeling, etc.", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let saveError {
                    Section {
                        Label("Couldn't save: \(saveError)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!includeWeight && !includeWaist && pickedImage == nil && note.isEmpty)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in pickedImage = image }
                    .ignoresSafeArea()
            }
            .task(id: photoItem) {
                if let photoItem,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    pickedImage = img
                }
            }
            .task {
                if healthSettings.syncBodyweight,
                   let hk = await HealthKitService.shared.latestBodyMass() {
                    let lastLocal = stats.first(where: { $0.weightKg != nil })?.date ?? .distantPast
                    if hk.date > lastLocal { weight = hk.kg }
                }
            }
            .onAppear {
                if let lastWeight = stats.first(where: { $0.weightKg != nil })?.weightKg {
                    weight = lastWeight
                }
                if let lastWaist = stats.first(where: { $0.waistCm != nil })?.waistCm {
                    waist = lastWaist
                }
            }
        }
    }

    private func save() {
        guard (!includeWeight || (weight.isFinite && (1...1000).contains(weight))),
              (!includeWaist || (waist.isFinite && (1...500).contains(waist))), note.count <= 8000 else {
            saveError = "Enter a valid weight (1–1000 kg), waist (1–500 cm), and a note under 8000 characters."
            return
        }
        var filename: String?
        if let pickedImage {
            guard let saved = PhotoStore.save(pickedImage) else {
                saveError = "The photo could not be saved. Check available storage and retry."
                return
            }
            filename = saved
        }

        let stat = BodyStat(
            date: date,
            weightKg: includeWeight ? weight : nil,
            waistCm: includeWaist ? waist : nil,
            photoFilename: filename,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        context.insert(stat)
        if let error = context.saveLogging("add body stat") {
            context.delete(stat)
            PhotoStore.delete(filename)
            saveError = error
            return                          // don't dismiss over a lost entry
        }
        if healthSettings.syncBodyweight, let kg = stat.weightKg {
            let date = stat.date
            Task { @MainActor in
                do {
                    let uuid = try await HealthKitService.shared.saveBodyMass(kg: kg, date: date, externalID: stat.id)
                    stat.healthKitUUID = uuid.uuidString
                    stat.syncedToHealth = true
                    context.saveLogging("bodyweight health flag")
                } catch {
                    Log.health.error("Bodyweight sync failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        dismiss()
    }
}
