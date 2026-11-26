// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WorkoutPlusStatusWidget.swift
//  WorkoutPlusWidget
//
//  Home Screen and Lock Screen widget. Reads the shared JSON snapshot the app
//  publishes — see Shared/WidgetSnapshot.swift for why it isn't reading the
//  database directly.
//
//  Refresh policy is deliberately lazy. The app calls
//  `WidgetCenter.reloadAllTimelines()` whenever something actually changes, so
//  the timeline here only needs a slow backstop for the case where you haven't
//  opened the app in a while. Asking for frequent refreshes would spend the
//  system's budget and get the widget throttled exactly when it matters.
//

import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now,
                               snapshot: context.isPreview ? .placeholder
                                                           : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let entry = StatusEntry(date: .now, snapshot: snapshot)

        // While resting, one extra entry at the moment the clock runs out so
        // the tile stops showing a countdown that has already finished.
        var entries = [entry]
        if let end = snapshot.restEndsAt, end > .now {
            entries.append(StatusEntry(date: end, snapshot: snapshot))
        }

        let backstop = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now
        completion(Timeline(entries: entries, policy: .after(backstop)))
    }
}

struct WorkoutPlusStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutPlusStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive()
        }
        .configurationDisplayName("Next Workout")
        .description("What's next in your rotation, and how much you've trained this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct StatusWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: accessory
        case .systemMedium:         medium
        default:                    small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)

            if snapshot.isLive {
                liveBody
            } else {
                Text(snapshot.nextWorkoutName.isEmpty ? "No plan" : snapshot.nextWorkoutName)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(snapshot.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            weekLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                if snapshot.isLive {
                    liveBody
                } else {
                    Text(snapshot.nextWorkoutName.isEmpty ? "No plan" : snapshot.nextWorkoutName)
                        .font(.title2.bold())
                        .lineLimit(1)
                    Text(snapshot.nextWorkoutFocus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                weekLine
            }

            Divider()

            VStack(alignment: .trailing, spacing: 2) {
                Text("THIS WEEK")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text("\(snapshot.setsThisWeek)")
                    .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                Text("hard sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(snapshot.sessionsThisWeek) session\(snapshot.sessionsThisWeek == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .trailing)
        }
    }

    // MARK: Lock Screen

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            if snapshot.isLive {
                Text(snapshot.liveWorkoutName ?? "")
                    .font(.headline)
                    .lineLimit(1)
                if let end = snapshot.restEndsAt, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.caption.monospacedDigit())
                } else {
                    Text("\(snapshot.liveProgress ?? "") logged")
                        .font(.caption)
                }
            } else {
                Text(snapshot.nextWorkoutName.isEmpty ? "Workout Plus" : snapshot.nextWorkoutName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(snapshot.setsThisWeek) sets this week")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.isLive
                  ? "figure.strengthtraining.traditional"
                  : "calendar")
                .font(.caption2)
            Text(snapshot.isLive ? "IN PROGRESS" : "NEXT UP")
                .font(.caption2.bold())
        }
        .foregroundStyle(snapshot.isLive ? .orange : .secondary)
    }

    @ViewBuilder
    private var liveBody: some View {
        Text(snapshot.liveWorkoutName ?? "")
            .font(.title3.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.8)

        if let end = snapshot.restEndsAt, end > .now {
            HStack(spacing: 4) {
                Image(systemName: "timer").font(.caption2)
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.caption.monospacedDigit().bold())
            }
            .foregroundStyle(.green)
            if let hop = snapshot.upNext {
                Text("Then: \(hop)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            ProgressView(value: snapshot.fractionLogged)
                .tint(.orange)
            Text("\(snapshot.liveProgress ?? "") exercises")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var weekLine: some View {
        Text("\(snapshot.setsThisWeek) sets this week")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
