// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyStat.date, order: .reverse) private var stats: [BodyStat]

    @State private var deleteError: String?
    @State private var showAdd = false
    @State private var fullScreenPhoto: PhotoID?
    @State private var showCompare = false

    var body: some View {
        NavigationStack {
            Group {
                if stats.isEmpty {
                    ContentUnavailableView {
                        Label("No entries yet", systemImage: "figure.stand")
                    } description: {
                        Text("Log your weight and a progress photo to start tracking.")
                    } actions: {
                        Button("Add Entry") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(stats) { stat in
                            row(for: stat)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .alert("Deletion failed", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK") { deleteError = nil }
            } message: { Text(deleteError ?? "") }
            .privacySensitive()
            .safeAreaInset(edge: .bottom) {
                Text("Deleting an entry here leaves Apple Health unchanged. Remove linked Health data from Settings when erasing all data, or manage it in Health.").font(.caption2).padding().background(.bar)
            }
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCompare = true } label: { Image(systemName: "rectangle.on.rectangle") }
                        .accessibilityLabel("Compare photos")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add entry")
                }
            }
            .sheet(isPresented: $showAdd) { AddBodyStatSheet() }
            .sheet(isPresented: $showCompare) { PhotoCompareView() }
            .fullScreenCover(item: $fullScreenPhoto) { photo in
                PhotoViewer(filename: photo.id)
            }
        }
    }

    @ViewBuilder
    private func row(for stat: BodyStat) -> some View {
        HStack(spacing: 14) {
            if let img = PhotoStore.load(stat.photoFilename, maximumPixelSize: 256) {
                Button {
                    if let name = stat.photoFilename { fullScreenPhoto = PhotoID(id: name) }
                } label: {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View progress photo from \(stat.date.formatted(date: .abbreviated, time: .omitted))")
                .privacySensitive()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.secondary.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay { Image(systemName: "figure.stand").foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stat.weightText ?? "—").font(.headline)
                    if let w = stat.waistText {
                        Text("· \(w)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text(stat.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                if !stat.note.isEmpty {
                    Text(stat.note)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(_ offsets: IndexSet) {
        let selected = offsets.map { stats[$0] }
        let filenames = selected.compactMap(\.photoFilename)
        for stat in selected { context.delete(stat) }
        if let error = context.saveLogging("delete body stat") {
            context.rollback()
            deleteError = error
        } else {
            for filename in filenames { PhotoStore.delete(filename) }
        }
    }
}

/// Full-screen photo viewer.
private struct PhotoViewer: View {
    let filename: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = PhotoStore.load(filename) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

/// A one-line wrapper instead of `extension String: @retroactive Identifiable`.
/// That conformance was app-wide: it silently changed overload resolution in
/// unrelated `ForEach`/`sheet(item:)` call sites and would collide outright if
/// the standard library ever added it.
struct PhotoID: Identifiable, Hashable {
    let id: String
}
