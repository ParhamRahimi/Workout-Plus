// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import UniformTypeIdentifiers

struct ImportPlanView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var pendingReplace: (plan: Plan, data: Data)?
    @State private var showReplaceConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paste a plan as JSON, or import a .json file. Use the example format in the project documentation, or create a plan from the Plans screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Paste JSON") {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 200)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import from file", systemImage: "doc.badge.plus")
                    }
                }

                if let errorMessage {
                    Section("Problems") {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importFromText() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.json]) { result in
                handleFile(result)
            }
            .confirmationDialog("Replace \(pendingReplace?.plan.name ?? "this plan")?",
                                isPresented: $showReplaceConfirm, titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    if let data = pendingReplace?.data {
                        do { try commit(data) }
                        catch { errorMessage = error.localizedDescription }
                    }
                    pendingReplace = nil
                }
                Button("Cancel", role: .cancel) { pendingReplace = nil }
            } message: {
                Text("A plan with the same id is already installed. Importing will overwrite it — your logged sessions are not affected.")
            }
        }
    }

    private func importFromText() {
        guard let data = jsonText.data(using: .utf8) else { return }
        finish(data)
    }

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? ImportLimits.read(url, maximum: ImportLimits.planBytes) else {
                errorMessage = "Couldn't read that file."
                return
            }
            finish(data)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func finish(_ data: Data) {
        errorMessage = nil
        // Decode and validate first, so a re-import that would silently
        // overwrite a plan you've been tweaking asks before it does it.
        do {
            try ImportLimits.check(data, maximum: ImportLimits.planBytes)
            let decoded = try JSONDecoder().decode(Plan.self, from: data)
            let validated = try PlanValidator.validated(decoded)
            if let existing = planStore.wouldReplacePlan(id: validated.id) {
                pendingReplace = (existing, data)
                showReplaceConfirm = true
                return
            }
            try commit(data)
        } catch let error as PlanValidationError {
            errorMessage = error.errorDescription
        } catch let error as DecodingError {
            errorMessage = "That isn't a valid plan. \(readable(error))"
        } catch {
            errorMessage = "Couldn't import that plan: \(error.localizedDescription)"
        }
    }

    private func commit(_ data: Data) throws {
        _ = try planStore.importPlan(from: data)
        dismiss()
    }

    /// DecodingError's `localizedDescription` is "The data couldn't be read",
    /// which tells you nothing about which field is wrong.
    private func readable(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx):
            return "Missing \"\(key.stringValue)\" at \(path(ctx))."
        case .typeMismatch(_, let ctx):
            return "Wrong type at \(path(ctx))."
        case .valueNotFound(_, let ctx):
            return "Null where a value was required at \(path(ctx))."
        case .dataCorrupted(let ctx):
            return ctx.debugDescription
        @unknown default:
            return "Check the JSON against the schema."
        }
    }

    private func path(_ ctx: DecodingError.Context) -> String {
        let parts = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        return parts.isEmpty ? "the top level" : parts.joined(separator: " → ")
    }
}
