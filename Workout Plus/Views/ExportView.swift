// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  ExportView.swift
//  Workout Plus
//
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlanStore.self) private var planStore

    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \BodyStat.date) private var stats: [BodyStat]

    // Nothing is built until you ask for it. Opening this sheet used to
    // generate both CSVs AND encode the entire pretty-printed backup JSON on
    // the main actor, every single time.
    @State private var setsURL: URL?
    @State private var bodyURL: URL?
    @State private var backupURL: URL?
    @State private var working: String?
    @State private var copied: String?

    @State private var showRestore = false
    @State private var restoreMessage: String?

    private var setCount: Int { sessions.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Workouts", value: "\(sessions.count)")
                    LabeledContent("Logged sets", value: "\(setCount)")
                    LabeledContent("Body entries", value: "\(stats.count)")
                }

                Section("Workout sets (CSV)") {
                    if let setsURL {
                        ShareLink(item: setsURL) {
                            Label("Share workout_sets.csv", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyToPasteboard(ExportService.setsCSV(sessions), label: "Workout sets copied")
                        } label: {
                            Label("Copy to clipboard", systemImage: "doc.on.doc")
                        }
                    } else {
                        Button {
                            build("workout sets") {
                                setsURL = ExportService.writeTempFile(
                                    named: "workout_sets.csv",
                                    contents: ExportService.setsCSV(sessions))
                            }
                        } label: {
                            Label("Prepare workout_sets.csv", systemImage: "tablecells")
                        }
                    }
                    Text("One row per set, in the order you trained, with warm-up and effort columns.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Body stats (CSV)") {
                    if let bodyURL {
                        ShareLink(item: bodyURL) {
                            Label("Share body_stats.csv", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyToPasteboard(ExportService.bodyCSV(stats), label: "Body stats copied")
                        } label: {
                            Label("Copy to clipboard", systemImage: "doc.on.doc")
                        }
                    } else {
                        Button {
                            build("body stats") {
                                bodyURL = ExportService.writeTempFile(
                                    named: "body_stats.csv",
                                    contents: ExportService.bodyCSV(stats))
                            }
                        } label: {
                            Label("Prepare body_stats.csv", systemImage: "tablecells")
                        }
                    }
                }

                if let copied {
                    Section {
                        Label(copied, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.footnote)
                    }
                }

                Section("Training-data backup") {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Share workout-plus-backup.json", systemImage: "arrow.up.doc")
                        }
                    } else {
                        Button {
                            build("backup") {
                                let backup = BackupService.makeBackup(plans: planStore.plans,
                                                                      sessions: sessions,
                                                                      stats: stats)
                                if let data = BackupService.encode(backup),
                                   let str = String(data: data, encoding: .utf8) {
                                    backupURL = ExportService.writeTempFile(
                                        named: "workout-plus-backup.json", contents: str)
                                }
                            }
                        } label: {
                            Label("Prepare backup file", systemImage: "arrow.up.doc")
                        }
                    }

                    Button { showRestore = true } label: {
                        Label("Restore from backup", systemImage: "arrow.down.doc")
                    }
                    if let restoreMessage {
                        Text(restoreMessage).font(.caption).foregroundStyle(.green)
                    }
                    Text("Includes plans, every session and set, and body measurements. Photos are not included. Restoring only adds what's missing, never overwrites, and never changes which plan is active.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if let working {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing \(working)…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("Photos aren't included in any export — only weights, reps, dates, measurements and notes. Shared files contain private training data and are not encrypted. Clipboard copies stay on this device and expire after five minutes. Device backups may separately include app data and photos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDisappear { ExportService.cleanup() }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { result in
                handleRestore(result)
            }
        }
    }

    private func build(_ what: String, _ work: @escaping () -> Void) {
        working = what
        // One runloop hop so the spinner actually paints before the work starts.
        Task { @MainActor in
            await Task.yield()
            work()
            working = nil
        }
    }

    /// Your entire training history on the system clipboard with no expiry was
    /// readable by every app you opened afterwards.
    private func copyToPasteboard(_ text: String, label: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        copied = label
    }

    // MARK: Restore

    private func handleRestore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            restoreMessage = "No file selected."
            return
        }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? ImportLimits.read(url, maximum: ImportLimits.backupBytes) else {
            restoreMessage = "Couldn't read that file, or it exceeds the 32 MB backup limit."
            return
        }
        do {
            let r = try BackupService.restore(
                from: data,
                context: context,
                existingSessionIDs: Set(sessions.map(\.id)),
                existingStatIDs: Set(stats.map(\.id)),
                planStore: planStore)
            restoreMessage = "Restored \(r.sessions) session(s), \(r.stats) body entr(ies), \(r.plans) plan(s)."
        } catch {
            restoreMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}
