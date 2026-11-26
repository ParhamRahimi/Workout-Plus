// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 48)).accessibilityHidden(true)
                    Text("Welcome to Workout Plus").font(.largeTitle.bold())
                    Text("Choose a workout, log the sets you actually complete, then tap Finish to save it. Your next workout follows the plan's rotation.")
                    Text("The included three-day plan is an editable example. Choose loads for your own experience and recovery; stop for pain. You can create, edit, or import plans from the Plans screen.")
                    Text("This version uses kilograms and centimetres. Apple Health, notifications, remote images, and displaying workout details outside the app are optional.")
                    Text("Backups protect training records but exclude photos and profile settings. Device backups may include those. Review Privacy and Export & backup in Settings.")
                    NavigationLink("Read privacy policy") { PrivacyPolicyView() }
                    Button("Start tracking", action: onContinue).buttonStyle(.borderedProminent)
                }.padding()
            }
        }.interactiveDismissDisabled()
    }
}
