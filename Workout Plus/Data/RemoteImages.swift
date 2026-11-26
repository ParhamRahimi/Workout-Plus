// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import Foundation

nonisolated enum RemoteImages {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "remoteImagesEnabled") }
}

/// Redirects are checked at the network boundary, not only during plan import.
nonisolated final class ImageRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { PlanValidator.isAllowedImageURL($0.absoluteString) } == true && RemoteImages.enabled ? request : nil)
    }
}
