// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation
import Observation

@Observable
final class ImagePrefetcher {
    var isDownloading = false
    var completed = 0
    var total = 0

    /// How many downloads run at once. Serial was roughly 60 round trips end to
    /// end on gym Wi-Fi; six at a time turns that into about ten.
    private static let concurrency = 6

    /// Downloads every image URL in the plan into the disk cache.
    /// @MainActor on the method rather than the type, so constructing one in a
    /// `@State` property initialiser stays non-isolated.
    @MainActor
    func downloadAll(for plan: Plan) async {
        let urls: [URL] = plan.workouts
            .flatMap { $0.exercises }
            .flatMap { $0.imageURLs }
            .compactMap { URL(string: $0) }

        total = urls.count
        completed = 0
        isDownloading = true

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            // Prime the pump, then top the group up as each one lands, so
            // exactly `concurrency` requests are ever in flight.
            while next < min(Self.concurrency, urls.count) {
                let url = urls[next]
                group.addTask { _ = await DiskImageCache.shared.image(for: url) }
                next += 1
            }
            while await group.next() != nil {
                completed += 1
                if next < urls.count {
                    let url = urls[next]
                    group.addTask { _ = await DiskImageCache.shared.image(for: url) }
                    next += 1
                }
            }
        }

        isDownloading = false
    }
}
