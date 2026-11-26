// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation

/// Complete protection on iOS. The native macOS check runner uses its normal
/// file system; iOS data-protection flags are not supported on every Mac volume.
nonisolated enum PrivateFiles {
    static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
    static var directoryAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.complete]
        #else
        [:]
        #endif
    }
}
