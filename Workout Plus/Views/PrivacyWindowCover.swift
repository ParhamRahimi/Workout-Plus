// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI
import UIKit

/// Covers the entire scene window, including presented sheets, for snapshots and app lock.
struct PrivacyWindowCover: UIViewRepresentable {
    var isVisible: Bool
    var canUnlock: Bool
    var onUnlock: () -> Void

    final class Anchor: UIView {
        var windowChanged: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); windowChanged?(window) }
    }
    final class Coordinator {
        weak var window: UIWindow?
        var cover: UIView?
        var visible = false
        var canUnlock = false
        var onUnlock: (() -> Void)?
        func render() {
            cover?.removeFromSuperview()
            cover = nil
            guard visible, let window else { return }
            let panel = UIView(frame: window.bounds)
            panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            panel.backgroundColor = .systemBackground
            let title = UILabel()
            title.text = "Workout Plus — Private"
            title.font = .preferredFont(forTextStyle: .title2)
            title.adjustsFontForContentSizeCategory = true
            let stack = UIStackView(arrangedSubviews: [title])
            stack.axis = .vertical; stack.alignment = .center; stack.spacing = 24
            if canUnlock {
                let button = UIButton(type: .system)
                button.setTitle("Unlock with device authentication", for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
                button.addAction(UIAction { [weak self] _ in self?.onUnlock?() }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            stack.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(stack)
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: panel.centerXAnchor), stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor), stack.leadingAnchor.constraint(greaterThanOrEqualTo: panel.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -20)])
            panel.accessibilityViewIsModal = true
            window.addSubview(panel)
            cover = panel
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.windowChanged = { [weak coordinator = context.coordinator] window in coordinator?.window = window; coordinator?.render() }
        return anchor
    }
    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.visible = isVisible
        context.coordinator.canUnlock = canUnlock
        context.coordinator.onUnlock = onUnlock
        context.coordinator.render()
    }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.cover?.removeFromSuperview() }
}
