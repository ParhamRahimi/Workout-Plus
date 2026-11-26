// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import UIKit

/// Deliberately unavailable in physical-device and Release builds. Never reads
/// the personal store, imports a backup, or writes samples to Apple Health.
@MainActor
enum ScreenshotDemo {
    static let argument = "--synthetic-screenshot-demo"
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutPlusSchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        var plan = SeedData.plan
        plan.summary = "Synthetic demonstration records. Follow a three-day rotation, log completed sets, and track progress. All measurements, loads, dates, notes, and illustrations in this gallery are invented."
        try PlanStore().replacePlans([plan], activeID: plan.id, recovering: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        for visit in 0..<18 {
            let workout = plan.workouts[visit % plan.workouts.count]
            let day = calendar.date(byAdding: .day, value: -(52 - visit * 3), to: today)!
            let start = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day)!
            let session = WorkoutSession(date: start, workoutID: workout.id, workoutName: workout.name, planID: plan.id)
            session.endDate = start.addingTimeInterval(43 * 60)
            session.bodyweightKgAtTime = 76 - Double(visit) * 0.08
            session.notes = "Synthetic demonstration session. No personal training data."
            context.insert(session)
            for (exerciseIndex, exercise) in workout.exercises.enumerated() {
                for setIndex in 0..<exercise.sets {
                    let relative = exercise.loadIsBodyweight && !exercise.isTimed
                    let load = relative ? max(8, 24 - Double(visit)) : Double(8 + exerciseIndex * 3) + Double(visit / 3)
                    let set = SetEntry(exerciseName: exercise.name, category: exercise.category, setNumber: setIndex + 1, weightKg: exercise.isTimed ? 0 : load, reps: exercise.isTimed ? 0 : min(exercise.repRangeHigh, exercise.repRangeLow + visit % 4), seconds: exercise.isTimed ? 35 : 0, isTimed: exercise.isTimed, orderIndex: exerciseIndex, isWarmup: false, isAssisted: relative, rir: 2, targetLow: exercise.repRangeLow, targetHigh: exercise.repRangeHigh)
                    set.exerciseID = exercise.id
                    set.isBodyweight = exercise.loadIsBodyweight
                    set.performedAt = start.addingTimeInterval(Double(exerciseIndex * 240 + setIndex * 60 + 30))
                    set.note = "Demo set"
                    set.session = session
                    context.insert(set)
                }
            }
        }
        for index in 0..<8 {
            let date = calendar.date(byAdding: .day, value: -(49 - index * 7), to: today)!
            let filename = PhotoStore.save(illustration(index: index))
            let stat = BodyStat(date: date, weightKg: 76 - Double(index) * 0.2, waistCm: 86 - Double(index) * 0.3, photoFilename: filename, note: "SYNTHETIC DEMO — invented measurement and illustration")
            context.insert(stat)
        }
        try context.save()
        return container
    }

    private static func illustration(index: Int) -> UIImage {
        let size = CGSize(width: 720, height: 960)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor(red: 0.06, green: 0.13, blue: 0.20, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor.systemMint.setFill()
            cg.fillEllipse(in: CGRect(x: 280, y: 180, width: 160, height: 160))
            cg.addPath(CGPath(roundedRect: CGRect(x: CGFloat(235 + index * 2), y: 365, width: CGFloat(250 - index * 4), height: 310), cornerWidth: 65, cornerHeight: 65, transform: nil)); cg.fillPath()
            for x in [205, 475] { cg.fill(CGRect(x: CGFloat(x), y: 390, width: 40, height: 230)) }
            for x in [275, 395] { cg.fill(CGRect(x: CGFloat(x), y: 650, width: 55, height: 160)) }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
            ("DEMO ILLUSTRATION" as NSString).draw(in: CGRect(x: 20, y: 65, width: 680, height: 50), withAttributes: attributes)
            ("NOT A REAL PROGRESS PHOTO" as NSString).draw(in: CGRect(x: 20, y: 870, width: 680, height: 55), withAttributes: attributes)
        }
    }
}
#endif
