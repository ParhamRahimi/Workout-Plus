// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import os
import SwiftData

/// A workout together with the plan it came from. `Workout.id` is only "A" /
/// "B" / "C", which is unique inside a plan and worthless across two — without
/// the plan id, opening Plan 2's Workout A while Plan 1's Workout A was live
/// showed the running-workout bar, the checkmarks and a Finish button that
/// would have committed the other plan's exercises.
struct WorkoutRef: Hashable, Identifiable {
    let planID: String
    let workout: Workout
    var id: String { Plan.slug(planID: planID, workoutID: workout.id) }
}

/// An exercise slot together with the workout and plan it belongs to — the same
/// reason `WorkoutRef` exists. Two installed plans can both contain a "Leg
/// Press" slot with the same id, so the detail screen has to know which one it
/// is looking at before it decides you're mid-workout.
struct ExerciseRef: Hashable, Identifiable {
    let planID: String
    let workoutID: String
    let exercise: ExerciseTemplate
    var id: String { "\(planID)/\(workoutID)/\(exercise.id)" }
}

/// Everything needed to rebuild an interrupted workout after a crash.
struct WorkoutSnapshot: Codable {
    var workout: Workout
    var startDate: Date
    /// Keyed by slot id. For a plan with no repeated names that id *is* the
    /// name, so snapshots written before slot ids existed still resume.
    var drafts: [String: [DraftSet]]
    var logged: [String]
    var substitutions: [String: ExerciseTemplate]
    var lastActivity: Date
    var planID: String?

    init(workout: Workout, startDate: Date, drafts: [String: [DraftSet]],
         logged: [String], substitutions: [String: ExerciseTemplate],
         lastActivity: Date, planID: String?) {
        self.workout = workout
        self.startDate = startDate
        self.drafts = drafts
        self.logged = logged
        self.substitutions = substitutions
        self.lastActivity = lastActivity
        self.planID = planID
    }

    /// Tolerant decode: `planID` didn't exist in older snapshots.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workout = try c.decode(Workout.self, forKey: .workout)
        startDate = try c.decode(Date.self, forKey: .startDate)
        drafts = try c.decodeIfPresent([String: [DraftSet]].self, forKey: .drafts) ?? [:]
        logged = try c.decodeIfPresent([String].self, forKey: .logged) ?? []
        substitutions = try c.decodeIfPresent([String: ExerciseTemplate].self, forKey: .substitutions) ?? [:]
        lastActivity = try c.decodeIfPresent(Date.self, forKey: .lastActivity) ?? startDate
        planID = try c.decodeIfPresent(String.self, forKey: .planID)
    }
}

/// Shared, app-level state for a live workout.
@MainActor
@Observable
final class WorkoutEngine {
    /// Nothing here needs the main actor to be CONSTRUCTED — only to be
    /// mutated — and `@State private var engine = WorkoutEngine()` runs in a
    /// property initialiser that isn't main-actor isolated.
    nonisolated init() {}

    private(set) var workout: Workout?
    /// The plan the live workout belongs to.
    private(set) var planID: String?
    private(set) var startDate: Date?

    /// slot id (the planned exercise's slot) -> its logged sets
    var drafts: [String: [DraftSet]] = [:]
    private(set) var loggedExercises: Set<String> = []
    /// slot id -> replacement exercise, for this session only
    private(set) var substitutions: [String: ExerciseTemplate] = [:]
    private(set) var lastActivity: Date?

    // MARK: Bodyweight (for assisted / bodyweight / weighted exercises)

    /// Resolved once per session and reused for every bodyweight-relative set
    /// — bodyweight doesn't change mid-workout. nil until `resolveBodyweight`
    /// finds a fresh-enough `BodyStat` or `setResolvedBodyweight` is called
    /// after the user fills in a quick weigh-in.
    private(set) var resolvedBodyweightKg: Double?
    /// A `BodyStat` older than this isn't trusted silently — the user is
    /// asked for a fresh one instead of computing effective load off a
    /// months-old number.
    static let bodyweightFreshnessWindow: TimeInterval = 30 * 24 * 3600

    /// The most recent bodyweight, if it's fresh enough to use without
    /// asking. Returns nil when nothing fresh exists — the caller should
    /// prompt for a quick weigh-in and call `setResolvedBodyweight`.
    func resolveBodyweight(from bodyStats: [BodyStat]) -> Double? {
        if let resolvedBodyweightKg { return resolvedBodyweightKg }
        guard let recent = bodyStats.first(where: { $0.weightKg != nil }),
              let weight = recent.weightKg,
              Date.now.timeIntervalSince(recent.date) <= Self.bodyweightFreshnessWindow
        else { return nil }
        resolvedBodyweightKg = weight
        return weight
    }

    func setResolvedBodyweight(_ kg: Double) {
        resolvedBodyweightKg = kg
    }

    /// Set when committing the session to disk fails. Non-nil means the workout
    /// is still on disk in the snapshot and has NOT been thrown away.
    var lastSaveError: String?

    // MARK: Rest timer

    private(set) var restEndsAt: Date?
    private(set) var restTotal: Int = 0
    private(set) var restingFor: String?          // exercise name, for the alert
    /// Where to walk next, worked out when rest starts. nil while you still
    /// have sets left on the same machine.
    private(set) var upNext: String?
    private(set) var upNextIsSuperset = false
    private var restTask: Task<Void, Never>?
    /// Injected from settings so the engine doesn't have to know about them.
    var restAlertsEnabled = false

    var isActive: Bool { workout != nil }

    func isRunning(_ w: Workout, in planID: String) -> Bool {
        self.workout?.id == w.id && self.planID == planID
    }
    func isRunning(_ ref: WorkoutRef) -> Bool { isRunning(ref.workout, in: ref.planID) }
    func isRunning(_ ref: ExerciseRef) -> Bool {
        workout?.id == ref.workoutID && planID == ref.planID
    }
    func isLogged(_ slotID: String) -> Bool { loggedExercises.contains(slotID) }

    /// Sets actually ticked off for a slot, for the "2/4" progress on the list.
    func completedSets(for slotID: String) -> Int {
        drafts[slotID]?.filter(\.isDone).count ?? 0
    }

    /// True once every planned set has been ticked off.
    func isComplete(_ template: ExerciseTemplate) -> Bool {
        completedSets(for: template.id) >= max(template.sets, 1)
    }

    /// How many planned exercises are logged (for the Live Activity).
    var progressText: String {
        guard let workout else { return "" }
        return "\(loggedExercises.count)/\(workout.exercises.count)"
    }

    // MARK: - Substitutions

    /// The exercise actually being performed for a planned slot.
    func effective(for template: ExerciseTemplate) -> ExerciseTemplate {
        substitutions[template.id] ?? template
    }

    func substitute(_ replacement: ExerciseTemplate, for slotID: String) {
        substitutions[slotID] = replacement
        drafts[slotID] = nil                   // old numbers don't apply to a new lift
        loggedExercises.remove(slotID)
        lastActivity = .now
        persist()
    }

    func clearSubstitution(for slotID: String) {
        substitutions[slotID] = nil
        drafts[slotID] = nil
        loggedExercises.remove(slotID)
        lastActivity = .now
        persist()
    }

    // MARK: - Lifecycle

    func start(_ workout: Workout, planID: String) {
        self.workout = workout
        self.planID = planID
        self.startDate = .now
        self.drafts = [:]
        self.loggedExercises = []
        self.substitutions = [:]
        self.lastActivity = .now
        self.lastSaveError = nil
        self.resolvedBodyweightKg = nil
        stopRest()
        persist()
        LiveWorkoutActivity.start(engine: self)
    }

    func saveSets(_ sets: [DraftSet], for slotID: String, restSeconds: Int? = nil, exerciseName: String? = nil) {
        drafts[slotID] = sets
        loggedExercises.insert(slotID)
        lastActivity = .now
        persist()
        if let restSeconds, restSeconds > 0 {
            startRest(seconds: restSeconds, exercise: exerciseName, finishedSlot: slotID)
        } else {
            LiveWorkoutActivity.update(engine: self)
        }
    }

    func cancel() {
        workout = nil; planID = nil; startDate = nil
        drafts = [:]; loggedExercises = []
        substitutions = [:]; lastActivity = nil
        resolvedBodyweightKg = nil
        stopRest()
        clearSnapshot()
        LiveWorkoutActivity.end()
    }

    /// End time to stamp on the session. If the app died and we resume much later,
    /// use the last logged set instead of "now" so duration stays honest.
    var resolvedEndDate: Date {
        if let last = lastActivity, Date.now.timeIntervalSince(last) > 3 * 3600 {
            return last
        }
        return .now
    }

    // MARK: - Rest timer

    func startRest(seconds: Int, exercise: String?, finishedSlot: String? = nil) {
        guard seconds > 0 else { return }
        restTotal = seconds
        restingFor = exercise
        if let finishedSlot, let hop = nextStop(after: finishedSlot) {
            upNext = hop.name
            upNextIsSuperset = hop.isSuperset
        } else {
            upNext = nil
            upNextIsSuperset = false
        }
        restEndsAt = Date.now.addingTimeInterval(Double(seconds))
        armRestTimer()
    }

    /// What to walk to during this rest.
    ///
    /// Two cases, and the superset one comes first: if the slot you just
    /// finished is part of a superset group and another exercise in that group
    /// still has sets left, that partner is next NOW — you alternate between
    /// them rather than finishing one and moving on. Otherwise there's only
    /// somewhere to go once the current exercise is actually finished; while
    /// you still have sets left you're staying where you are, and naming the
    /// next machine would just be wrong.
    private func nextStop(after slotID: String) -> (name: String, isSuperset: Bool)? {
        guard let workout,
              let index = workout.exercises.firstIndex(where: { $0.id == slotID })
        else { return nil }

        let finished = workout.exercises[index]

        if let group = finished.supersetGroup {
            let partner = workout.exercises.first {
                $0.id != slotID && $0.supersetGroup == group && !isComplete($0)
            }
            if let partner {
                return (effective(for: partner).name, true)
            }
        }

        guard isComplete(finished) else { return nil }

        // Everything after this slot, then wrap around to anything skipped.
        let after = workout.exercises[(index + 1)...]
        let before = workout.exercises[..<index]
        guard let next = (Array(after) + Array(before)).first(where: { !isComplete($0) })
        else { return nil }
        return (effective(for: next).name, false)
    }

    func adjustRest(by delta: Int) {
        guard let current = restEndsAt else { return }
        let newEnd = current.addingTimeInterval(Double(delta))
        guard newEnd > .now else { stopRest(); return }
        restEndsAt = newEnd
        restTotal = max(0, restTotal + delta)
        armRestTimer()
    }

    func stopRest() {
        restTask?.cancel(); restTask = nil
        restEndsAt = nil
        restTotal = 0
        restingFor = nil
        upNext = nil
        upNextIsSuperset = false
        RestAlerts.cancel()
        LiveWorkoutActivity.update(engine: self)
    }

    private func armRestTimer() {
        restTask?.cancel()
        guard let end = restEndsAt else { return }

        if restAlertsEnabled {
            RestAlerts.schedule(at: end, exercise: restingFor)
        } else {
            RestAlerts.cancel()
        }
        LiveWorkoutActivity.update(engine: self)

        restTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            guard let self, self.restEndsAt == end else { return }
            self.restEndsAt = nil
            self.restTotal = 0
            self.restingFor = nil
            self.upNext = nil
            self.upNextIsSuperset = false
            RestAlerts.buzz()
            LiveWorkoutActivity.update(engine: self)
        }
    }

    // MARK: - Crash recovery snapshot

    private static var snapshotURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("active-workout.json")
    }

    private func persist() {
        guard let workout, let startDate else { return }
        let snap = WorkoutSnapshot(
            workout: workout,
            startDate: startDate,
            drafts: drafts,
            logged: Array(loggedExercises),
            substitutions: substitutions,
            lastActivity: lastActivity ?? .now,
            planID: planID
        )
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: Self.snapshotURL, options: .atomic)
        } catch {
            Log.data.error("Snapshot write failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func eraseSnapshot() throws {
        if FileManager.default.fileExists(atPath: Self.snapshotURL.path) {
            try FileManager.default.removeItem(at: Self.snapshotURL)
        }
    }

    func clearSnapshot() {
        try? FileManager.default.removeItem(at: Self.snapshotURL)
    }

    func pendingSnapshot() -> WorkoutSnapshot? {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let snap = try? JSONDecoder().decode(WorkoutSnapshot.self, from: data)
        else { return nil }
        return snap
    }

    func resume(_ snap: WorkoutSnapshot, fallbackPlanID: String) {
        workout = snap.workout
        planID = snap.planID ?? fallbackPlanID
        startDate = snap.startDate
        drafts = snap.drafts
        loggedExercises = Set(snap.logged)
        substitutions = snap.substitutions
        lastActivity = snap.lastActivity
        lastSaveError = nil
        LiveWorkoutActivity.start(engine: self)
    }

    // MARK: - Commit

    /// Commits the session to SwiftData, then optionally mirrors it to Health.
    /// Returns true when the session is safely on disk. On failure NOTHING is
    /// cleared — the snapshot stays, so the workout can be finished again.
    @discardableResult
    func finish(context: ModelContext,
                settings: AppSettings,
                bodyweightKg: Double?) -> Bool {
        guard let workout, let startDate else { return false }
        let end = resolvedEndDate

        let session = WorkoutSession(date: startDate,
                                     workoutID: workout.id,
                                     workoutName: workout.name,
                                     planID: planID ?? "")
        session.endDate = end
        session.bodyweightKgAtTime = resolvedBodyweightKg
        context.insert(session)

        var summaryParts: [String] = []

        for (index, ex) in workout.exercises.enumerated() {
            guard let sets = drafts[ex.id] else { continue }
            let eff = effective(for: ex)
            // Rows you opened but never performed shouldn't become logged sets.
            let performed = sets.filter { !$0.isEmptyPlaceholder }
            for (i, s) in performed.enumerated() {
                let entry = SetEntry(
                    exerciseName: eff.name,
                    category: eff.category,
                    setNumber: i + 1,
                    weightKg: s.weightKg,
                    reps: s.reps,
                    seconds: s.seconds,
                    isTimed: eff.isTimed,
                    orderIndex: index,          // the order you actually trained in
                    isWarmup: s.isWarmup,
                    isAssisted: s.isAssisted,
                    rir: s.rir,
                    targetLow: eff.repRangeLow,
                    targetHigh: eff.repRangeHigh
                )
                entry.isBodyweight = eff.loadIsBodyweight
                entry.exerciseID = eff.id
                entry.performedAt = s.finishedAt
                entry.substitutedFor = (eff.id == ex.id) ? nil : ex.name
                // Setting one side of a declared inverse is enough. Doing all
                // three (assign + append + insert) has produced duplicate rows
                // in some SwiftData releases.
                entry.session = session
                context.insert(entry)
                if !s.isWarmup { summaryParts.append("\(eff.name) \(entry.summary)") }
            }
        }

        if let error = context.saveLogging("finish workout") {
            context.delete(session)
            lastSaveError = "Couldn't save this workout: \(error). It's still here — try Finish again."
            return false
        }
        lastSaveError = nil

        if settings.syncWorkouts {
            let summary = summaryParts.joined(separator: "; ")
            let kcal = settings.writeEstimatedCalories
                ? EnergyService.estimate(session: session,
                                         profile: settings.profile(bodyweightKg: bodyweightKg))?.activeKcal
                : nil
            let sessionID = session.id

            Task { @MainActor in
                do {
                    let uuid = try await HealthKitService.shared.saveWorkout(
                        start: startDate, end: end,
                        externalID: sessionID,
                        exerciseSummary: summary,
                        energyKcal: kcal
                    )
                    session.healthKitUUID = uuid.uuidString
                    context.saveLogging("health uuid")
                } catch {
                    // A Health failure must never lose your log — but it should
                    // no longer vanish without trace either.
                    Log.health.error("Workout sync failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }

        cancel()
        return true
    }

}
