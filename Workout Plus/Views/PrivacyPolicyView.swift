// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy policy").font(.title.bold())
                Text("Effective 26 November 2026")
                Text("Your workout logs, body measurements, notes, optional profile, and progress photos are stored in the app's local container. Workout Plus has no account system, analytics SDK, advertising SDK, or app-operated server receiving these records.")
                Text("Apple Health is optional. Connecting can request access to bodyweight, workouts, and active energy. The app reads bodyweight and its synced samples to support syncing and deletion. It writes workouts/bodyweight only when enabled. Estimated calorie writing is off by default and is not a validated measurement. Access can be changed in the Health app.")
                Text("Remote exercise images are off by default. Enabling downloads contacts GitHub's raw.githubusercontent.com service for the supported free-exercise-db library. GitHub receives your IP address and request metadata under its own privacy policy. No workout log is included in those requests. Cached exercise images are bounded and excluded from device backups.")
                Text("Progress photos use complete file protection. System/device backups may include photos, logs, and profile settings, depending on your Apple settings. The app does not implement cloud synchronization. JSON/CSV exports exclude photos and optional profile settings. Shared exports are unencrypted and contain private fitness information; copies saved or sent elsewhere are controlled by you and the recipient.")
                Text("Clipboard exports are local-only and expire after five minutes. Temporary export files are removed when the export screen closes or on the next launch. File cleanup cannot remove copies you have shared.")
                Text("Use Settings → Delete all app data to erase local records, photos, profile, plans, snapshots, and caches. You may separately choose to remove app-created Health records. Legacy Health records without a stored link may need deletion in Health. The app cannot erase prior device backups or exported files. Changing a workout log locally does not update a previously synced Health workout.")
                Text("Optional device authentication protects access to the app UI. App-switcher content is covered when inactive. Widget/Live Activity workout details are off by default and can be enabled in Settings. These controls do not encrypt copies you deliberately share.")
                Link("GitHub privacy policy", destination: URL(string: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement")!)
                Link("Contact / report a privacy concern", destination: URL(string: "https://github.com/ParhamRahimi/Workout-Plus/security/advisories/new")!)
                Text("Do not attach personal workouts, photos, exports, or Health records to public issues. This policy must be reviewed before a release changes data handling.").font(.footnote)
            }.padding()
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}
