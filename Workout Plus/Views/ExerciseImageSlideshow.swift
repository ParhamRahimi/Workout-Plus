// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import SwiftUI

/// Cross-fades between an exercise's frames. Three gestures, all on the same
/// surface:
///
///   • hold anywhere            → freeze on the current frame
///   • swipe left / right       → step a frame by hand (and stop auto-advance)
///   • tap the play/pause chip  → toggle auto-advance for good
///
/// A page `TabView` gives you the swipe for free but slides rather than fades,
/// and it swallows the press-and-hold. Two frames of the same movement read far
/// better as a dissolve than as a slide, so this does the transition itself and
/// adds the gestures back.
struct ExerciseImageSlideshow: View {
    let imageURLs: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var interval: TimeInterval = 1.2      // seconds per frame

    @State private var index = 0
    @State private var isHeld = false
    @State private var autoAdvance = true
    /// Cancels the pending advance when you interact, so a frame you just
    /// swiped to doesn't get replaced a moment later.
    @State private var tick = 0

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 240

    private var validURLs: [URL] {
        imageURLs.compactMap { URL(string: $0) }
    }

    private var isPaused: Bool { isHeld || !autoAdvance || reduceMotion }

    var body: some View {
        Group {
            if validURLs.isEmpty {
                placeholder(text: "No image available")
            } else {
                ZStack {
                    // Every frame stays mounted and only its opacity changes:
                    // that's what makes it a dissolve instead of a cut, and it
                    // keeps all frames warm in the image cache.
                    ForEach(validURLs.indices, id: \.self) { i in
                        CachedAsyncImage(url: validURLs[i])
                            .opacity(i == index ? 1 : 0)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: index)
                .overlay(alignment: .bottom) { pageDots }
                .overlay(alignment: .topLeading) { heldBadge }
                .overlay(alignment: .topTrailing) { playPauseChip }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .contentShape(.rect)
        .gesture(holdAndSwipe)
        .animation(.easeInOut(duration: 0.2), value: isHeld)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise demonstration, frame \(index + 1) of \(max(validURLs.count, 1))")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Next frame") { step(1) }
        .accessibilityAction(named: "Previous frame") { step(-1) }
        // `tick` restarts the wait from zero after any manual interaction, and
        // `isPaused` is in the id on purpose: holding a finger down or hitting
        // pause CANCELS this task rather than leaving it waking once a second
        // to decide to do nothing.
        .task(id: "\(validURLs.count)-\(tick)-\(isPaused)") {
            guard validURLs.count > 1, !isPaused else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                index = (index + 1) % validURLs.count
            }
        }
    }

    // MARK: Gestures

    /// One gesture handles both: a finger that stays put pauses, a finger that
    /// travels far enough steps a frame on release.
    private var holdAndSwipe: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Any real horizontal travel means "swipe", not "hold".
                if abs(value.translation.width) > 12 {
                    if isHeld { isHeld = false }
                } else if !isHeld {
                    isHeld = true
                }
            }
            .onEnded { value in
                isHeld = false
                let dx = value.translation.width
                guard abs(dx) > 40 else { return }
                step(dx < 0 ? 1 : -1)
                autoAdvance = false          // you've taken manual control
            }
    }

    private func step(_ delta: Int) {
        guard validURLs.count > 1 else { return }
        index = (index + delta + validURLs.count) % validURLs.count
        tick &+= 1
    }

    // MARK: Chrome

    @ViewBuilder
    private var pageDots: some View {
        if validURLs.count > 1 {
            HStack(spacing: 6) {
                ForEach(validURLs.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: i == index ? 16 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.3), value: index)
            .padding(6)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var heldBadge: some View {
        if isHeld && validURLs.count > 1 {
            Label("Held", systemImage: "hand.raised.fill")
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(8)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var playPauseChip: some View {
        if validURLs.count > 1 {
            Button {
                autoAdvance.toggle()
                tick &+= 1
            } label: {
                Image(systemName: autoAdvance ? "pause.fill" : "play.fill")
                    .font(.caption2.bold())
                    .padding(7)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(autoAdvance ? "Pause the demonstration" : "Play the demonstration")
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

// Safe array subscript so a bad index can never crash the app.
extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

#Preview {
    ExerciseImageSlideshow(imageURLs: SeedData.workoutA.exercises[0].imageURLs)
        .padding()
}
