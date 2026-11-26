// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import UIKit
import os
import CryptoKit
import ImageIO

/// Downloads images once and stores them permanently on disk.
/// Load order is memory → disk → network, so after the first fetch
/// an image is served with no internet connection at all.
///
/// These files are deliberately INCLUDED in iCloud/device backups. The usual
/// rule is that re-downloadable content shouldn't be — but these are hotlinked
/// from a GitHub repo that could move or disappear, the whole set is a few
/// megabytes, and the point of the cache is that the pictures survive a dead
/// link, a new phone and a change of plan. Continuity beats tidiness here.
actor DiskImageCache {
    static let shared = DiskImageCache()

    // In-memory cache so repeated views in one session skip even the disk read.
    // Bounded: a decoded bitmap is several times the size of the JPEG it came
    // from, and an unbounded cache of them is a memory-warning waiting to
    // happen on a long session.
    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80              // a plan is ~60 images
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Rough decoded size, so the cost limit means something.
    private func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    private var generation = 0
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: ImageRedirectPolicy(), delegateQueue: nil)
    }()
    private let folderURL: URL

    private init() {
        // Application Support is durable — unlike Caches, the system never purges it.
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        folderURL = base.appendingPathComponent("ExerciseImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var excluded = folderURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    /// Turns a remote URL into a stable, unique filename on disk.
    /// Stable, unique filename derived from the URL via SHA-256.
    private func fileURL(for remote: URL) -> URL {
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = remote.pathExtension.isEmpty ? "img" : remote.pathExtension
        return folderURL.appendingPathComponent(hex + "." + ext)
    }

    /// Returns an image, loading from memory → disk → network (in that order).
    /// Only the very first call for a given URL touches the network.
    func image(for remote: URL) async -> UIImage? {
        let key = remote.absoluteString as NSString

        guard PlanValidator.isAllowedImageURL(remote.absoluteString) else { return nil }
        // 1. Memory
        if let cached = memory.object(forKey: key) { return cached }

        // 2. Disk
        let file = fileURL(for: remote)
        if let data = try? Data(contentsOf: file), let img = Self.decode(data) {
            memory.setObject(img, forKey: key, cost: cost(of: img))
            return img
        }

        // 3. Network (first time only) → save to disk for next time
        guard RemoteImages.enabled else { return nil }
        let startedGeneration = generation
        do {
            let (stream, response) = try await session.bytes(from: remote)
            guard response.expectedContentLength <= 12 * 1024 * 1024 else { return nil }
            var data = Data()
            for try await byte in stream {
                if Task.isCancelled || !RemoteImages.enabled { return nil }
                guard data.count < 12 * 1024 * 1024 else { return nil }
                data.append(byte)
            }
            // A plan is just JSON somebody handed you: verify what came back is
            // actually an image, and cap the size, before writing it to disk.
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else { return nil }
                let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                guard type.isEmpty || type.hasPrefix("image/") else {
                    Log.images.error("Refused non-image response")
                    return nil
                }
            }
            guard generation == startedGeneration, RemoteImages.enabled, data.count <= 12 * 1024 * 1024 else { return nil }
            guard let img = Self.decode(data) else { return nil }
            trim(to: 100 * 1024 * 1024 - data.count)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            memory.setObject(img, forKey: key, cost: cost(of: img))
            return img
        } catch {
            return nil   // offline and not yet cached → caller shows a placeholder
        }
    }

    private nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12000, height <= 12000,
              Double(width) * Double(height) <= 40_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private func trim(to limit: Int) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        for file in files where total > limit {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if (try? fm.removeItem(at: file)) != nil { total -= size }
        }
    }

    func eraseAllForDeletion() {
        try? eraseAll()
    }

    func eraseAll() throws {
        generation += 1
        memory.removeAllObjects()
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        if FileManager.default.fileExists(atPath: folderURL.path) { try FileManager.default.removeItem(at: folderURL) }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    /// Is this URL already saved on disk?
    func isCached(_ remote: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: remote).path)
    }

    /// Mark-and-sweep cleanup: deletes any cached image NOT referenced by the
    /// given "live" URLs. Dormant for now; called in Milestone 6 after a plan
    /// is imported/edited/deleted so orphans can never accumulate.
    func removeOrphans(keeping liveURLs: [URL]) {
        let liveFilenames = Set(liveURLs.map { fileURL(for: $0).lastPathComponent })
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL,
                                                      includingPropertiesForKeys: nil)
        else { return }
        for file in files where !liveFilenames.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    /// Downloads a batch concurrently. Actors are reentrant, so each call
    /// releases the actor while it waits on the network and the requests really
    /// do overlap.
    nonisolated static func warm(_ urls: [URL], concurrency: Int = 5) async {
        guard !urls.isEmpty, RemoteImages.enabled else { return }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            while next < min(concurrency, urls.count) {
                let url = urls[next]
                group.addTask { _ = await DiskImageCache.shared.image(for: url) }
                next += 1
            }
            while await group.next() != nil {
                if next < urls.count {
                    let url = urls[next]
                    group.addTask { _ = await DiskImageCache.shared.image(for: url) }
                    next += 1
                }
            }
        }
    }

    /// How much is actually on disk, for the Settings screen.
    func stats() -> (count: Int, bytes: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.fileSizeKey])
        else { return (0, 0) }
        var bytes = 0
        for file in files {
            // `try?` already flattens to Int?; the old `as? Int` was a no-op.
            bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return (files.count, bytes)
    }
}
