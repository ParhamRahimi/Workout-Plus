// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

// Original geometric app icon; no personal imagery or external assets.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 1024 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.16, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 32) {
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
context.setFillColor(CGColor(red: 0.28, green: 0.91, blue: 0.70, alpha: 1))
block(280, 462, 464, 100, 30)
context.setFillColor(CGColor(gray: 1, alpha: 1))
block(220, 292, 110, 440)
block(694, 292, 110, 440)
block(140, 362, 65, 300, 24)
block(819, 362, 65, 300, 24)
let path = CommandLine.arguments.dropFirst().first ?? "Workout Plus/Assets.xcassets/AppIcon.appiconset/icon.png"
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
