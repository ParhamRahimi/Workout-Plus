// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WorkoutPlusLiveActivity.swift
//  WorkoutPlusWidget
//
//  The Lock Screen / Dynamic Island presentation of a live workout.
//
//  Every countdown here is `Text(timerInterval:)`. That renders a self-updating
//  clock that iOS drives itself — neither the app nor this extension is woken
//  once a second, which is the only way a rest timer can stay accurate while
//  the phone is in your pocket.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct WorkoutPlusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .privacySensitive()
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(state.progress, systemImage: "checklist")
                            .font(.caption.bold())
                        Text("logged")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.isResting ? .green : .orange)
                                .frame(width: 6, height: 6)
                            Text(state.isResting ? "REST" : "ELAPSED")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        countdown(state)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(state.isResting ? .green : .primary)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(state.workoutName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: state.isResting ? "timer" : "figure.strengthtraining.traditional")
                                .font(.caption2)
                            Text(state.detailLine)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)

                        if let hop = state.upNextLine {
                            HStack(spacing: 6) {
                                Image(systemName: state.upNextIsSuperset
                                      ? "arrow.triangle.2.circlepath" : "arrow.turn.down.right")
                                    .font(.caption2)
                                Text(hop)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            }
                            .foregroundStyle(state.upNextIsSuperset ? .cyan : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.upNextLine != nil
                      ? "arrow.turn.down.right"
                      : (state.isResting ? "timer" : "figure.strengthtraining.traditional"))
                    .foregroundStyle(state.isResting ? .green : .primary)
            } compactTrailing: {
                countdown(state)
                    .monospacedDigit()
                    .foregroundStyle(state.isResting ? .green : .primary)
                    .frame(maxWidth: 52)
            } minimal: {
                Circle()
                    .fill(state.isResting ? .green : .orange)
                    .frame(width: 10, height: 10)
            }
            .keylineTint(state.isResting ? .green : .orange)
        }
    }

    /// Resting counts down to the deadline; otherwise the session time counts up.
    @ViewBuilder
    private func countdown(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let end = state.restEndsAt {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
        } else {
            Text(state.startDate, style: .timer)
        }
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(state.workoutName)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let hop = state.upNextLine {
                    HStack(spacing: 5) {
                        Image(systemName: state.upNextIsSuperset
                              ? "arrow.triangle.2.circlepath" : "arrow.turn.down.right")
                            .font(.caption2)
                        Text(hop)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                    .foregroundStyle(state.upNextIsSuperset ? .cyan : .orange)
                } else {
                    Text(state.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // A quiet progress bar reads faster than "4/10" alone.
                ProgressView(value: state.fractionLogged)
                    .tint(.orange)
                    .frame(maxWidth: 150)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isResting ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(state.isResting ? "REST" : "ELAPSED")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                if let end = state.restEndsAt {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        .font(.system(.title, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(.green)
                } else {
                    Text(state.startDate, style: .timer)
                        .font(.system(.title, design: .rounded).monospacedDigit().bold())
                }
            }
            .frame(maxWidth: 118, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Presentation helpers

extension WorkoutActivityAttributes.ContentState {
    var isResting: Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > .now
    }

    var detailLine: String {
        if let resting = restingFor { return "Resting after \(resting)" }
        return "\(progress) exercises logged"
    }

    /// Only shown while resting — knowing where to walk is useful during the
    /// rest and noise the moment you're back under the bar.
    var upNextLine: String? {
        guard isResting, let upNext else { return nil }
        return upNextIsSuperset ? "Superset now: \(upNext)" : "Up next: \(upNext)"
    }

    /// "4/10" → 0.4, for the Lock Screen progress bar.
    var fractionLogged: Double {
        let parts = progress.split(separator: "/")
        guard parts.count == 2,
              let done = Double(parts[0]), let total = Double(parts[1]), total > 0
        else { return 0 }
        return min(max(done / total, 0), 1)
    }
}
