// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import SwiftData
import Charts
import Accessibility

struct ReportsView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \BodyStat.date) private var stats: [BodyStat]

    @State private var latestExerciseNames: [String: String] = [:]
    @State private var selectedExercise: String?
    @State private var metric: ExerciseMetric = .topWeight
    @State private var showExport = false
    @State private var volumeMetric: VolumeMetric = .sets

    // Everything below used to be a plain computed property, so every redraw —
    // including each frame of a scroll — re-walked every session and every set.
    // Now they're computed once per appearance and once per control change.
    @State private var stalls: [Stall] = []
    @State private var exerciseNames: [String] = []
    @State private var bodyPoints: [BodyPoint] = []
    @State private var waistPoints: [WaistPoint] = []
    @State private var exercisePoints: [ExercisePoint] = []
    @State private var mixedVocabulary = false
    @State private var volumeMode: VolumeMode = .byMuscle
    @State private var window: VolumeWindow = .eight
    @State private var muscleRows: [MuscleRow] = []
    @State private var weekTotals: [WeekTotal] = []
    /// Whether the selected exercise's chart is plotting effective load
    /// (bodyweight ∓ what was logged) rather than a raw number — drives the
    /// "down is progress" caption, which is only true in the legacy fallback.
    @State private var exercisePointsUseEffectiveLoad = false

    enum VolumeMetric: String, CaseIterable, Identifiable {
        case sets = "Sets", volume = "Volume"
        var id: String { rawValue }
    }

    /// Two different questions, so two different charts. "Am I doing enough for
    /// each muscle?" is a comparison against a target and belongs on labelled
    /// horizontal bars. "Is my workload trending?" is change-over-time and
    /// belongs on a single-series column chart. The old chart tried to be both
    /// by stacking eleven categories per week, which is unreadable by
    /// construction — nobody can compare the middle segments of a stack.
    enum VolumeMode: String, CaseIterable, Identifiable {
        case byMuscle = "By muscle", byWeek = "By week"
        var id: String { rawValue }
    }

    enum VolumeWindow: Int, CaseIterable, Identifiable {
        case four = 4, eight = 8, twelve = 12
        var id: Int { rawValue }
        var label: String { "\(rawValue) wks" }
    }

    struct MuscleRow: Identifiable {
        let id = UUID()
        let category: String
        let perWeek: Double
        let total: Double
    }

    struct WeekTotal: Identifiable {
        let id = UUID()
        let week: Date
        let value: Double
    }

    enum ExerciseMetric: String, CaseIterable, Identifiable {
        case topWeight = "Top set (kg)"
        case volume = "Volume (kg)"
        var id: String { rawValue }
    }

    // MARK: - Recomputation

    private func recomputeAll() {
        latestExerciseNames = [:]
        for session in sessions {
            for entry in session.sets where !entry.exerciseID.isEmpty { latestExerciseNames[entry.exerciseID] = ExerciseTemplate.canonicalName(entry.exerciseName) }
        }
        exerciseNames = computeExerciseNames()
        if selectedExercise == nil || !exerciseNames.contains(selectedExercise ?? "") {
            selectedExercise = exerciseNames.first
        }
        computeVolume()
        mixedVocabulary = sessions.contains { session in
            session.workingSets.contains { CategoryMap.canonical($0.category) != $0.category }
        }
        bodyPoints = computeBodyPoints()
        waistPoints = computeWaistPoints()
        exercisePoints = computeExercisePoints()
        stalls = StallService.stalls(in: sessions, bodyStats: stats)
    }

    /// Warm-ups are excluded everywhere below: they were inflating weekly
    /// volume and could register a heavy warm-up single as progress.
    private func computeVolume() {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let start = cal.date(byAdding: .weekOfYear,
                             value: -(window.rawValue - 1), to: thisWeek) ?? thisWeek

        var byCategory: [String: Double] = [:]
        var byWeek: [Date: Double] = [:]

        for session in sessions where session.date >= start {
            guard let week = cal.dateInterval(of: .weekOfYear, for: session.date)?.start else { continue }
            for e in session.workingSets {
                // Kilos of assistance times reps is not volume, so assisted
                // work only ever contributes set counts. `resolvedIsAssisted`
                // is the set's own truth (corrected for history logged
                // before the per-set flag existed) — it survives an exercise
                // being renamed (e.g. "Assisted Pull-up" → "Pull-up").
                let v = volumeMetric == .sets ? 1 : (e.resolvedIsAssisted ? 0 : e.weightKg * Double(e.reps))
                // Canonical tag: history logged under an older plan's
                // vocabulary lines up with the plan you're running now.
                byCategory[CategoryMap.canonical(e.category), default: 0] += v
                byWeek[week, default: 0] += v
            }
        }

        let weeks = Double(window.rawValue)
        muscleRows = byCategory
            .map { MuscleRow(category: $0.key, perWeek: $0.value / weeks, total: $0.value) }
            .sorted { $0.perWeek > $1.perWeek }
        weekTotals = byWeek
            .map { WeekTotal(week: $0.key, value: $0.value) }
            .sorted { $0.week < $1.week }
    }

    private func computeExerciseNames() -> [String] {
        var names = Set<String>()
        for s in sessions {
            for e in s.workingSets where !e.isTimed {
                names.insert(latestExerciseNames[e.exerciseID] ?? ExerciseTemplate.canonicalName(e.exerciseName))
            }
        }
        return names.sorted()
    }

    private func computeBodyPoints() -> [BodyPoint] {
        stats.compactMap { st in
            guard let w = st.weightKg else { return nil }
            return BodyPoint(date: st.date, weight: w)
        }
    }

    private func computeWaistPoints() -> [WaistPoint] {
        stats.compactMap { st in
            guard let w = st.waistCm else { return nil }
            return WaistPoint(date: st.date, cm: w)
        }
    }

    private func computeExercisePoints() -> [ExercisePoint] {
        guard let name = selectedExercise else {
            exercisePointsUseEffectiveLoad = false
            return []
        }
        // Includes any older name this exercise used to be logged under, so a
        // rename (e.g. "Assisted Pull-up" → "Pull-up") doesn't split one
        // exercise's history into two disconnected charts.
        let names = ExerciseTemplate.namesForHistory(name)
        let usesBodyweight = sessions.flatMap(\.workingSets).first(where: { (names.contains($0.exerciseName) || latestExerciseNames[$0.exerciseID] == name) })?.isBodyweight ?? ExerciseTemplate.nameImpliesBodyweight(name)
        var points: [ExercisePoint] = []
        var usedEffectiveLoad = false
        for session in sessions {
            let matching = session.workingSets.filter { (names.contains($0.exerciseName) || latestExerciseNames[$0.exerciseID] == name) }
            guard !matching.isEmpty else { continue }
            let value: Double
            switch metric {
            case .topWeight:
                if usesBodyweight, let bw = session.resolvedBodyweightKg(bodyStats: stats) {
                    // Bodyweight ∓ what was logged: one number that simply
                    // gets bigger as you improve, whether that's removing
                    // assist or adding a belt.
                    value = matching.map {
                        ExerciseTemplate.effectiveLoad(weightKg: $0.weightKg, isAssisted: $0.resolvedIsAssisted, bodyweightKg: bw)
                    }.max() ?? bw
                    usedEffectiveLoad = true
                } else {
                    // Legacy fallback: not bodyweight-relative, or no
                    // bodyweight data resolvable yet for this session.
                    // Assisted lifts log HELP: the best set is the smallest
                    // number, so charting the max would draw the line upside
                    // down. Read per entry (`resolvedIsAssisted`), not by
                    // name — `name` here may already be canonicalized.
                    let assisted = matching.first?.resolvedIsAssisted ?? false
                    value = assisted
                        ? (matching.map(\.weightKg).min() ?? 0)
                        : (matching.map(\.weightKg).max() ?? 0)
                }
            case .volume:
                value = matching.reduce(0) { $0 + ($1.resolvedIsAssisted ? 0 : $1.weightKg * Double($1.reps)) }
            }
            points.append(ExercisePoint(date: session.date, value: value))
        }
        exercisePointsUseEffectiveLoad = usedEffectiveLoad
        return points
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                bodyweightSection
                waistSection
                exerciseSection
                volumeSection
                stallSection
                summarySection
            }
            .navigationTitle("Progress")
            // Fires each time the tab is selected, which is also how an edit
            // made over in History gets picked up.
            .onAppear { recomputeAll() }
            .onChange(of: sessions.count) { recomputeAll() }
            .onChange(of: stats.count) { recomputeAll() }
            .onChange(of: volumeMetric) { computeVolume() }
            .onChange(of: window) { computeVolume() }
            .onChange(of: metric) { exercisePoints = computeExercisePoints() }
            .onChange(of: selectedExercise) { exercisePoints = computeExercisePoints() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export and back up your data")
                }
            }
            .sheet(isPresented: $showExport) { ExportView() }
        }
    }

    // MARK: - Bodyweight

    @ViewBuilder
    private var bodyweightSection: some View {
        Section("Bodyweight") {
            if bodyPoints.count < 2 {
                Text("Log at least two weigh-ins to see a trend.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(bodyPoints) { p in
                    LineMark(x: .value("Date", p.date), y: .value("kg", p.weight))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", p.date), y: .value("kg", p.weight))
                        .symbolSize(30)
                }
                .frame(height: 220)
                .accessibilityChartDescriptor(
                    LineChartDescriptor(title: "Bodyweight over time",
                                        yLabel: "kilograms",
                                        points: bodyPoints.map { ($0.date, $0.weight) })
                )

                if let first = bodyPoints.first, let last = bodyPoints.last {
                    let diff = last.weight - first.weight
                    let sign = diff >= 0 ? "+" : ""
                    LabeledContent("Change",
                        value: "\(sign)\(diff.formatted(.number.precision(.fractionLength(1)))) kg")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Waist

    @ViewBuilder
    private var waistSection: some View {
        Section("Waist") {
            if waistPoints.count < 2 {
                Text("Log waist at least twice to see a trend. During recomposition this moves before your weight does.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(waistPoints) { p in
                    LineMark(x: .value("Date", p.date), y: .value("cm", p.cm))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", p.date), y: .value("cm", p.cm))
                        .symbolSize(30)
                }
                .frame(height: 200)
                .accessibilityChartDescriptor(
                    LineChartDescriptor(title: "Waist over time",
                                        yLabel: "centimetres",
                                        points: waistPoints.map { ($0.date, $0.cm) })
                )

                if let first = waistPoints.first, let last = waistPoints.last {
                    let diff = last.cm - first.cm
                    let sign = diff >= 0 ? "+" : ""
                    LabeledContent("Change",
                        value: "\(sign)\(diff.formatted(.number.precision(.fractionLength(1)))) cm")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Exercise progression

    @ViewBuilder
    private var exerciseSection: some View {
        Section("Exercise progress") {
            if exerciseNames.isEmpty {
                Text("Finish some workouts to see progression.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Exercise", selection: $selectedExercise) {
                    Text("Select…").tag(String?.none)
                    ForEach(exerciseNames, id: \.self) { Text($0).tag(String?.some($0)) }
                }

                Picker("Metric", selection: $metric) {
                    ForEach(ExerciseMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let name = selectedExercise, metric == .topWeight,
                   ExerciseTemplate.nameImpliesBodyweight(name) {
                    Text(exercisePointsUseEffectiveLoad
                         ? "Plotted against your bodyweight — up is progress whether that's less assist or added weight."
                         : "This is assistance, not load — down is progress. Log a bodyweight entry to switch to the combined chart.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if selectedExercise == nil {
                    Text("Choose an exercise above.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if exercisePoints.count < 2 {
                    Text("Not enough data yet — log this exercise at least twice.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(exercisePoints) { p in
                        LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                            .symbolSize(30)
                    }
                    .frame(height: 220)
                    .accessibilityChartDescriptor(
                        LineChartDescriptor(title: "\(selectedExercise ?? "Exercise"), \(metric.rawValue)",
                                            yLabel: metric.rawValue,
                                            points: exercisePoints.map { ($0.date, $0.value) })
                    )
                }
            }
        }
    }

    // MARK: - Weekly volume

    @ViewBuilder
    private var volumeSection: some View {
        Section("Weekly volume") {
            if muscleRows.isEmpty {
                Text("Finish some workouts to see your weekly distribution.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("View", selection: $volumeMode) {
                    ForEach(VolumeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Picker("Metric", selection: $volumeMetric) {
                        ForEach(VolumeMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Window", selection: $window) {
                        ForEach(VolumeWindow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                switch volumeMode {
                case .byMuscle: byMuscleChart
                case .byWeek:   byWeekChart
                }

                if mixedVocabulary {
                    Text("Some of this history was logged under a different plan's tags. They're folded together here — Settings can rewrite them permanently if you'd rather.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    /// Horizontal, one labelled bar per muscle, sorted heaviest first. The name
    /// sits on the axis next to its own bar, so identity never depends on
    /// matching a colour to a legend — and with eleven groups, matching eleven
    /// colours to a legend is exactly what nobody can do.
    @ViewBuilder
    private var byMuscleChart: some View {
        Chart {
            ForEach(muscleRows) { row in
                BarMark(
                    x: .value(volumeMetric.rawValue, row.perWeek),
                    y: .value("Group", row.category)
                )
                .foregroundStyle(row.category.categoryColor)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(row.perWeek.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // The 10–20 hard-sets guide, drawn where you're comparing against
            // it rather than written underneath in prose.
            if volumeMetric == .sets {
                RuleMark(x: .value("Maintenance", 10))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                RuleMark(x: .value("Upper end", 20))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.caption2)
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { $0.padding(.trailing, 26) }   // room for the value labels
        .frame(height: CGFloat(muscleRows.count) * 26 + 36)

        Text(volumeMetric == .sets
             ? "Average hard sets per week over the last \(window.rawValue) weeks. The dashed lines are the 10–20 range worth aiming at for a muscle you're prioritising."
             : "Average weekly volume (kg × reps) over the last \(window.rawValue) weeks. Assisted lifts are excluded — kilos of help times reps isn't work.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    /// One series, one colour. Trend questions don't need eleven segments.
    @ViewBuilder
    private var byWeekChart: some View {
        let average = weekTotals.isEmpty ? 0
            : weekTotals.reduce(0) { $0 + $1.value } / Double(weekTotals.count)

        Chart {
            ForEach(weekTotals) { point in
                BarMark(
                    x: .value("Week", point.week, unit: .weekOfYear),
                    y: .value(volumeMetric.rawValue, point.value)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(average.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel(format: .dateTime.day().month(.narrow), centered: true)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel()
            }
        }
        .frame(height: 220)

        Text("Total \(volumeMetric == .sets ? "hard sets" : "volume") per week across everything you trained. Use \"By muscle\" to see where it went.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    // MARK: - Stalls

    @ViewBuilder
    private var stallSection: some View {
        if !stalls.isEmpty {
            Section("Possible stalls") {
                ForEach(stalls) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.exercise).font(.subheadline.bold())
                                Text(stallDetail(s))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        // Detection with no prescribed action is just an
                        // anxiety-inducing orange triangle.
                        Text(s.suggestedAction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.10), in: .rect(cornerRadius: 10))
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func stallDetail(_ s: Stall) -> String {
        if s.isTimed { return "\(Int(s.weight))s for \(s.sessionCount) sessions" }
        let kg = s.weight.formatted(.number.precision(.fractionLength(0...1)))
        let unit = s.isAssisted ? "kg assist" : "kg"
        return "\(kg) \(unit) for \(s.sessionCount) sessions"
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Total workouts", value: "\(sessions.count)")
            LabeledContent("Body entries", value: "\(stats.count)")
            if let last = sessions.last {
                LabeledContent("Last workout", value: last.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }
}

// Chart data points.
struct BodyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}
struct WaistPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cm: Double
}
struct ExercisePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// Without this, VoiceOver got nothing at all from the Progress tab. With it,
/// every line chart supports Audio Graphs and value-by-value navigation.
struct LineChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let yLabel: String
    let points: [(Date, Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.0)
        let values = points.map(\.1)
        let minDate = dates.min() ?? .now
        let maxDate = dates.max() ?? .now
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: minDate.timeIntervalSince1970...max(maxDate.timeIntervalSince1970,
                                                       minDate.timeIntervalSince1970 + 1),
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: yLabel,
            range: minValue...max(maxValue, minValue + 1),
            gridlinePositions: []
        ) { value in
            value.formatted(.number.precision(.fractionLength(0...1))) + " " + yLabel
        }

        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: points.map {
                AXDataPoint(x: $0.0.timeIntervalSince1970, y: $0.1)
            }
        )

        return AXChartDescriptor(title: title,
                                 summary: nil,
                                 xAxis: xAxis,
                                 yAxis: yAxis,
                                 additionalAxes: [],
                                 series: [series])
    }

    /// Declared explicitly rather than relying on a protocol default.
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.series = makeChartDescriptor().series
    }
}
