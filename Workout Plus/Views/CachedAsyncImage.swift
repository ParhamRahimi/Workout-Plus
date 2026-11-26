// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

/// Like AsyncImage, but backed by DiskImageCache (download once, keep forever).
struct CachedAsyncImage: View {
    let url: URL?
    @AppStorage("remoteImagesEnabled") private var remoteImagesEnabled = false

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFail {
                placeholder(text: remoteImagesEnabled ? "Couldn't load image" : "Remote images are off in Settings")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(remoteImagesEnabled)") {          // re-runs whenever the URL changes
            await load()
        }
    }

    private func load() async {
        guard let url else { image = nil; loadedURL = nil; didFail = true; return }
        // Only blank the view when the URL genuinely changed. Clearing it
        // unconditionally flashed back to the spinner on every warm cache hit,
        // which on a two-frame slideshow is most of what you see.
        if loadedURL != url {
            image = nil
            didFail = false
        }
        let result = await DiskImageCache.shared.image(for: url)
        withAnimation(.easeInOut(duration: 0.25)) {
            if let result {
                image = result
                loadedURL = url
                didFail = false
            } else {
                didFail = true
            }
        }
    }

    private func placeholder(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.largeTitle)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
