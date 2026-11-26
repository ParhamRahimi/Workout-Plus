// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData

struct LogSetsSheet: View {
    let exercise: ExerciseTemplate          // the planned slot

    @Environment(WorkoutEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BodyStat.date, order: .reverse) private var bodyStats: [BodyStat]

    @State private var sets: [DraftSet] = []
    @State private var showQuickBodyweight = false
    @State private var selected = 0
    @State private var lastSummary: String?
    @State private var suggestion: ProgressionService.Suggestion?
    @State private var didSetup = false
    @State private var lastEffortLabel: String?
    @State private var lastWorkingWeight: Double?
    /// Sheet height: opens just tall enough for header + chips + wheels.
    @State private var detent: PresentationDetent = .height(600)
    /// Personal bests, fetched ONCE on appear — no history scan while spinning wheels.
    @State private var cachedBests = (weight: 0.0, reps: 0, volume: 0.0, seconds: 0)

    // Fixed pixel heights clip badly at large Dynamic Type sizes.
    @ScaledMetric(relativeTo: .body) private var headerCap: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var wheelHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var chipRowHeight: CGFloat = 62

    /// What you're actually doing (handles substitutions).
    private var effective: ExerciseTemplate { engine.effective(for: exercise) }

    /// Assisted → bodyweight → weighted: the load is tracked relative to
    /// your bodyweight instead of as an absolute number.
    private var usesBodyweight: Bool { effective.loadIsBodyweight && !effective.isTimed }

    private var inputIsValid: Bool {
        sets.allSatisfy { $0.weightKg.isFinite && (0...5000).contains($0.weightKg) && (0...1000).contains($0.reps) && (0...86400).contains($0.seconds) }
    }

    private var prs: [PRResult] {
        guard inputIsValid else { return [] }
        return         PRService.check(bests: cachedBests,
                        isTimed: effective.isTimed,
                        usesBodyweight: usesBodyweight,
                        bodyweightKg: engine.resolvedBodyweightKg,
                        draft: sets.filter { !$0.isWarmup })
    }

    // Discrete wheel values, built from integers so every one of them is
    // bit-identical to what the snap helpers produce.
    private static let weights: [Double] = (0...600).map { Double($0) / 2 }   // 0-300 kg by 0.5
    private static let reps: [Int] = Array(0...60)
    private static let seconds: [Int] = Array(stride(from: 0, through: 300, by: 5))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Header: capped height, scrolls internally if long ──
                ScrollView {
                    VStack(spacing: 8) {
                        if let s = suggestion {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: s.symbolName)
                                    .foregroundStyle(s.isReady ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.headline).font(.subheadline.bold())
                                    Text(s.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
                            .accessibilityElement(children: .combine)

                            // Both ways of taking a jump, one tap each. The
                            // wheels open on the probe; this is how you say
                            // "no, I'll take it everywhere".
                            if s.isReady, !effective.isTimed,
                               let base = s.baseWeight, let probe = s.probeWeight {
                                HStack(spacing: 8) {
                                    Button {
                                        applyWeight(probe, toLastSetOnly: true, base: base)
                                    } label: {
                                        Label("Top set only", systemImage: "arrow.up.right")
                                            .font(.caption2)
                                    }
                                    Button {
                                        applyWeight(probe, toLastSetOnly: false, base: base)
                                    } label: {
                                        Label("All sets at \(fmt(probe))", systemImage: "equal")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !prs.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(prs) { pr in
                                    Label("\(pr.kind.rawValue): \(fmt(pr.value)) (was \(fmt(pr.previous)))",
                                          systemImage: "trophy.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
                        }

                        if let lastSummary {
                            Text("Last time: \(lastSummary)")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .frame(maxHeight: headerCap)              // scaled cap — wheels stay visible

                // ── Set chips ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sets.indices, id: \.self) { i in
                            Button {
                                selected = i
                            } label: {
                                VStack(spacing: 1) {
                                    HStack(spacing: 3) {
                                        if sets[i].isDone {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                        Text(sets[i].isWarmup ? "W" : "Set \(workingNumber(of: i))")
                                            .font(.subheadline.bold())
                                    }
                                    Text(chipSummary(sets[i]))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(i == selected ? Color.accentColor.opacity(0.2)
                                                          : Color.secondary.opacity(0.12),
                                            in: .rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(i == selected ? Color.accentColor : .clear,
                                                      lineWidth: 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                (sets[i].isWarmup
                                 ? "Warm-up set, \(chipSummary(sets[i]))"
                                 : "Set \(workingNumber(of: i)), \(chipSummary(sets[i]))")
                                + (sets[i].isDone ? ", done" : ""))
                            .accessibilityAddTraits(i == selected ? [.isSelected] : [])
                        }

                        // Add-set button (duplicates the last set)
                        Button {
                            let new = sets.last.map { DraftSet(weightKg: $0.weightKg,
                                                               reps: $0.reps,
                                                               seconds: $0.seconds,
                                                               isAssisted: $0.isAssisted) } ?? DraftSet()
                            sets.append(new)
                            selected = sets.count - 1
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline)
                                .frame(width: 40, height: 44)
                                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a set")
                    }
                    .padding(.horizontal)
                }
                .frame(height: chipRowHeight)

                Divider()

                // ── Wheels ──
                if sets.indices.contains(selected) {
                    if effective.isTimed {
                        TextField("Seconds", value: $sets[selected].seconds, format: .number)
                            .keyboardType(.numberPad).padding()
                    } else {
                        HStack {
                            TextField(weightUnitLabel, value: $sets[selected].weightKg, format: .number).keyboardType(.decimalPad)
                            TextField("Reps", value: $sets[selected].reps, format: .number).keyboardType(.numberPad)
                        }.textFieldStyle(.roundedBorder).padding()

                        if let readout = effectiveLoadReadout {
                            Text(readout)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    setOptions
                }

                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom) { finishSetBar }
            .navigationTitle(effective.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if !inputIsValid { Text("Enter a nonnegative load up to 5000 kg, reps up to 1000, or seconds up to 86400.").font(.caption).foregroundStyle(.red).padding() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.fontWeight(.semibold).disabled(!inputIsValid)
                }
            }
            // .task rather than .onAppear: the history read no longer happens
            // synchronously while the sheet is animating in.
            .task {
                guard !didSetup else { return }
                didSetup = true
                setup()
                if usesBodyweight, engine.resolveBodyweight(from: bodyStats) == nil {
                    showQuickBodyweight = true
                }
            }
            .sheet(isPresented: $showQuickBodyweight) {
                QuickBodyweightSheet { kg in
                    engine.setResolvedBodyweight(kg)
                }
            }
        }
        .presentationDetents([.height(600), .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: Per-set options

    @ViewBuilder
    private var setOptions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Warm-up set", isOn: $sets[selected].isWarmup)
                    .font(.subheadline)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(sets[selected].isWarmup ? Color.orange : Color.gray)

                if usesBodyweight {
                    Toggle("Assisted", isOn: $sets[selected].isAssisted)
                        .font(.subheadline)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .tint(sets[selected].isAssisted ? Color.green : Color.gray)
                }
            }

            if !sets[selected].isWarmup {
                VStack(spacing: 2) {
                    Picker("How hard?", selection: $sets[selected].rir) {
                        Text("—").tag(Int?.none)
                        Text("Easy").tag(Int?.some(3))
                        Text("Hard").tag(Int?.some(1))
                        Text("Max").tag(Int?.some(0))
                    }
                    .pickerStyle(.segmented)
                    Text(effortHint)
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }

            if sets.count > 1 {
                Button(role: .destructive) {
                    sets.remove(at: selected)
                    selected = min(selected, sets.count - 1)
                } label: {
                    Label("Remove this set", systemImage: "trash")
                        .font(.subheadline)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Finish-a-set bar

    /// The gym does not work in batches. You do a set, you rest, you do the
    /// next one — so the primary action banks ONE set and starts the clock,
    /// rather than making you fill in every row before anything is recorded.
    @ViewBuilder
    private var finishSetBar: some View {
        VStack(spacing: 6) {
            if let end = engine.restEndsAt {
                HStack(spacing: 10) {
                    Image(systemName: "timer").font(.footnote)
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Button("+15") { engine.adjustRest(by: 15) }
                        .font(.footnote)
                    Button("Skip") { engine.stopRest() }
                        .font(.footnote)
                }
                .foregroundStyle(.green)

                if let hop = engine.upNext {
                    HStack(spacing: 5) {
                        Image(systemName: engine.upNextIsSuperset
                              ? "arrow.triangle.2.circlepath" : "arrow.turn.down.right")
                            .font(.caption2)
                        Text(engine.upNextIsSuperset ? "Superset now: \(hop)" : "Up next: \(hop)")
                            .font(.caption.bold())
                        Spacer()
                    }
                    .foregroundStyle(engine.upNextIsSuperset ? .cyan : .orange)
                }
            }

            Button(action: finishCurrentSet) {
                Text(finishButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(sets.indices.contains(selected) == false)

            Text(allDone
                 ? "Every planned set is banked. Done closes this."
                 : "Banks this set, starts the rest clock, and moves you to the next one.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var allDone: Bool {
        sets.filter(\.isDone).count >= max(effective.sets, 1)
    }

    private var finishButtonTitle: String {
        guard sets.indices.contains(selected) else { return "Done" }
        let restText = settings.restTimerEnabled ? " · rest \(effective.restText)" : ""
        if sets[selected].isDone { return "Update this set\(restText)" }
        if sets[selected].isWarmup { return "Warm-up done\(restText)" }
        return "Finish set \(workingNumber(of: selected))\(restText)"
    }

    private func finishCurrentSet() {
        guard inputIsValid else { return }
        guard sets.indices.contains(selected) else { return }
        sets[selected].isDone = true
        sets[selected].finishedAt = .now

        // Persist immediately: the snapshot on disk is now correct even if the
        // app dies between sets.
        engine.saveSets(sets,
                        for: exercise.id,
                        restSeconds: settings.restTimerEnabled ? effective.prescribedRest : nil,
                        exerciseName: effective.name)

        advanceToNextSet()
    }

    private func advanceToNextSet() {
        // Prefer the next un-banked row after this one.
        if let next = sets.indices.first(where: { $0 > selected && !sets[$0].isDone }) {
            selected = next
            return
        }
        // Otherwise open a fresh row, seeded from the one you just did, until
        // the prescription is met. Past that you can still add sets by hand.
        if sets.count < max(effective.sets, 1) {
            let seed = sets[selected]
            sets.append(DraftSet(weightKg: seed.weightKg,
                                 reps: seed.reps,
                                 seconds: seed.seconds,
                                 isAssisted: seed.isAssisted))
            selected = sets.count - 1
            return
        }
        // Everything planned is done — fall back to any earlier gap.
        if let gap = sets.indices.first(where: { !sets[$0].isDone }) {
            selected = gap
        }
    }

    // MARK: - Helpers

    /// Warm-ups don't consume a working-set number.
    private func workingNumber(of index: Int) -> Int {
        sets.prefix(index + 1).filter { !$0.isWarmup }.count
    }

    private func chipSummary(_ s: DraftSet) -> String {
        effective.isTimed ? "\(s.seconds)s"
            : "\(s.weightKg.formatted(.number.precision(.fractionLength(0...1))))×\(s.reps)"
    }

    private func fmt(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var weightUnitLabel: String {
        guard usesBodyweight, sets.indices.contains(selected) else { return "kg" }
        let s = sets[selected]
        if s.isAssisted { return "kg assist" }
        return s.weightKg == 0 ? "bodyweight" : "kg added"
    }

    /// "≈ 62 kg total" — the whole point of tracking this: one number that
    /// simply gets bigger as you improve, whether you're taking assist off
    /// or adding a belt.
    private var effectiveLoadReadout: String? {
        guard usesBodyweight, sets.indices.contains(selected),
              let bodyweightKg = engine.resolvedBodyweightKg
        else { return nil }
        let s = sets[selected]
        let load = ExerciseTemplate.effectiveLoad(weightKg: s.weightKg, isAssisted: s.isAssisted, bodyweightKg: bodyweightKg)
        return "≈ \(fmt(load)) kg total"
    }

    /// Deliberately a statement about LAST time, not a prediction filled into
    /// this set. Effort is the one input the app can't derive for itself —
    /// everything else about the set it already knows. Pre-selecting a value
    /// would feed the app's own guess back to it as though it were an
    /// observation, and would anchor you into agreeing with it.
    private var effortHint: String {
        guard sets.indices.contains(selected) else { return "" }
        let base = "How hard the set was. The app can't tell a clean 15 from a grinder without this."
        guard let label = lastEffortLabel else { return base }

        if let lastWeight = lastWorkingWeight, !effective.isTimed {
            let now = sets[selected].weightKg
            if now > lastWeight {
                return "Last time \(fmt(lastWeight)) kg felt \(label) — this is heavier."
            }
            if now < lastWeight {
                return "Last time \(fmt(lastWeight)) kg felt \(label) — this is lighter."
            }
        }
        return "Last time this felt \(label)."
    }

    /// Loads the jump either across every working set, or on the last one only.
    private func applyWeight(_ weight: Double, toLastSetOnly: Bool, base: Double) {
        let working = sets.indices.filter { !sets[$0].isWarmup }
        guard !working.isEmpty else { return }
        for i in working {
            sets[i].weightKg = SetPrefillService.snapWeight(toLastSetOnly ? base : weight)
        }
        if toLastSetOnly, let last = working.last {
            sets[last].weightKg = SetPrefillService.snapWeight(weight)
        }
    }

    private func save() {
        guard inputIsValid else { return }
        engine.saveSets(sets,
                        for: exercise.id,                 // key by SLOT id, not name
                        restSeconds: settings.restTimerEnabled ? effective.prescribedRest : nil,
                        exerciseName: effective.name)
        dismiss()
    }

    /// One history read for everything we need: bests, last-time, the
    /// suggestion and the pre-filled wheels.
    private func setup() {
        let prefill = SetPrefillService.make(for: effective, context: context, bodyStats: bodyStats)
        cachedBests = prefill.bests
        suggestion = prefill.suggestion
        lastSummary = prefill.lastSummary
        lastEffortLabel = prefill.lastEffortLabel
        lastWorkingWeight = prefill.lastWorkingWeight

        if let existing = engine.drafts[exercise.id] {
            sets = existing                // resuming an edit — keep what was entered
        } else {
            sets = prefill.sets
        }
        selected = 0
    }
}
