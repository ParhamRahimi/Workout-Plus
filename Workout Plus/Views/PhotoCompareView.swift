// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  PhotoCompareView.swift
//  Workout Plus
//
//


import SwiftUI
import SwiftData

struct PhotoCompareView: View {
    @Query(sort: \BodyStat.date) private var stats: [BodyStat]
    @Environment(\.dismiss) private var dismiss

    @State private var leftIndex = 0
    @State private var rightIndex = 0

    private var withPhotos: [BodyStat] { stats.filter { $0.photoFilename != nil } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if withPhotos.count < 2 {
                    ContentUnavailableView("Need two photos",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Log at least two entries with photos to compare."))
                } else {
                    HStack(spacing: 8) {
                        pane(index: leftIndex)
                        pane(index: rightIndex)
                    }
                    .padding(.horizontal, 8)

                    VStack(spacing: 4) {
                        labeledSlider("Before", value: $leftIndex)
                        labeledSlider("After", value: $rightIndex)
                    }
                    .padding(.horizontal)

                    if let a = withPhotos[safe: leftIndex], let b = withPhotos[safe: rightIndex] {
                        HStack(spacing: 16) {
                            if let wa = a.weightKg, let wb = b.weightKg {
                                delta("Weight", wb - wa, "kg")
                            }
                            if let ca = a.waistCm, let cb = b.waistCm {
                                delta("Waist", cb - ca, "cm")
                            }
                        }
                        .font(.footnote)
                    }
                }
                Spacer()
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                leftIndex = 0
                rightIndex = max(withPhotos.count - 1, 0)
            }
        }
    }

    @ViewBuilder
    private func pane(index: Int) -> some View {
        VStack(spacing: 4) {
            if let stat = withPhotos[safe: index], let img = PhotoStore.load(stat.photoFilename) {
                Image(uiImage: img).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 10))
                Text(stat.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
                Text([stat.weightText, stat.waistText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func labeledSlider(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 50, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: 0...Double(max(withPhotos.count - 1, 1)), step: 1)
        }
    }

    @ViewBuilder
    private func delta(_ label: String, _ d: Double, _ unit: String) -> some View {
        let sign = d >= 0 ? "+" : ""
        Label("\(label) \(sign)\(d.formatted(.number.precision(.fractionLength(1)))) \(unit)",
              systemImage: d <= 0 ? "arrow.down" : "arrow.up")
            .foregroundStyle(d <= 0 ? .green : .orange)
    }
}