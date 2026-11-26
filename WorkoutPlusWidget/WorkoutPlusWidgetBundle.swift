// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

//
//  WorkoutPlusWidgetBundle.swift
//  WorkoutPlusWidget
//
//  Add to the Widget Extension target only — never the app target.
//

import WidgetKit
import SwiftUI

@main
struct WorkoutPlusWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutPlusLiveActivity()
        WorkoutPlusStatusWidget()
    }
}
