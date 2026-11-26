// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import UIKit
import ImageIO
import os

/// Saves user progress photos to the Documents directory (backed up, permanent).
/// Distinct from DiskImageCache, which holds re-downloadable exercise images.
enum PhotoStore {

    private static var folderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        return url
    }

    /// Saves JPEG data, returns the filename to store in SwiftData.
    static func save(_ image: UIImage) -> String? {
        let scale = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = folderURL.appendingPathComponent(name)
        do {
            // Progress photos are the most sensitive thing this app holds.
            // .completeFileProtection means they are unreadable whenever the
            // device is locked, even to a process running on the device.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return name
        } catch {
            Log.data.error("Saving a progress photo failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    static func eraseAll() throws {
        if FileManager.default.fileExists(atPath: folderURL.path) { try FileManager.default.removeItem(at: folderURL) }
    }

    /// Loads an image by filename (nil-safe).
    static func load(_ filename: String?, maximumPixelSize: Int = 2400) -> UIImage? {
        guard let filename, filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".jpg") else { return nil }
        let url = folderURL.appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Deletes a photo file (call when its BodyStat is deleted).
    static func delete(_ filename: String?) {
        guard let filename, filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".jpg") else { return }
        let url = folderURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
