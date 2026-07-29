import AppKit
import SwiftUI

enum TrackpadGesture: Equatable {
    case previousPage
    case nextPage
    case dismiss
}

struct TrackpadGestureClassifier {
    private var horizontalDistance: CGFloat = 0
    private var verticalDistance: CGFloat = 0
    private var hasRecognizedGesture = false
    private let threshold: CGFloat = 46

    mutating func consume(
        horizontal: CGFloat,
        vertical: CGFloat,
        reversesPageDirection: Bool = false
    ) -> TrackpadGesture? {
        guard !hasRecognizedGesture else { return nil }
        horizontalDistance += horizontal
        verticalDistance += vertical

        if abs(horizontalDistance) >= threshold, abs(horizontalDistance) > abs(verticalDistance) * 1.5 {
            hasRecognizedGesture = true
            let nativeGesture: TrackpadGesture = horizontalDistance > 0 ? .nextPage : .previousPage
            guard reversesPageDirection else { return nativeGesture }
            return nativeGesture == .nextPage ? .previousPage : .nextPage
        }
        if verticalDistance <= -threshold, abs(verticalDistance) > abs(horizontalDistance) * 1.5 {
            hasRecognizedGesture = true
            return .dismiss
        }
        return nil
    }

    mutating func reset() {
        horizontalDistance = 0
        verticalDistance = 0
        hasRecognizedGesture = false
    }
}

struct TrackpadGestureMonitor: NSViewRepresentable {
    let reversesPageDirection: Bool
    let handleGesture: (TrackpadGesture) -> Bool
    let onOptionPressed: () -> Void
    let handleKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            reversesPageDirection: reversesPageDirection,
            handleGesture: handleGesture,
            onOptionPressed: onOptionPressed,
            handleKeyDown: handleKeyDown
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.reversesPageDirection = reversesPageDirection
        context.coordinator.handleGesture = handleGesture
        context.coordinator.onOptionPressed = onOptionPressed
        context.coordinator.handleKeyDown = handleKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var hostView: NSView?
        var reversesPageDirection: Bool
        var handleGesture: (TrackpadGesture) -> Bool
        var onOptionPressed: () -> Void
        var handleKeyDown: (NSEvent) -> Bool
        private var classifier = TrackpadGestureClassifier()
        private var monitor: Any?

        init(
            reversesPageDirection: Bool,
            handleGesture: @escaping (TrackpadGesture) -> Bool,
            onOptionPressed: @escaping () -> Void,
            handleKeyDown: @escaping (NSEvent) -> Bool
        ) {
            self.reversesPageDirection = reversesPageDirection
            self.handleGesture = handleGesture
            self.onOptionPressed = onOptionPressed
            self.handleKeyDown = handleKeyDown
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .flagsChanged, .keyDown]) { [weak self] event in
                guard let self, event.window === self.hostView?.window else { return event }
                switch event.type {
                case .scrollWheel:
                    return self.handleScroll(event)
                case .flagsChanged:
                    if event.modifierFlags.contains(.option) { self.onOptionPressed() }
                    return event
                case .keyDown:
                    return self.handleKeyDown(event) ? nil : event
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard event.hasPreciseScrollingDeltas else { return event }
            if !event.momentumPhase.isEmpty {
                if event.momentumPhase.contains(.ended) { classifier.reset() }
                return event
            }
            if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
                classifier.reset()
            }
            if event.phase.contains(.cancelled) {
                classifier.reset()
                return event
            }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            let gesture = classifier.consume(
                horizontal: event.scrollingDeltaX * direction,
                vertical: event.scrollingDeltaY * direction,
                reversesPageDirection: reversesPageDirection
            )
            guard let gesture else { return event }
            return handleGesture(gesture) ? nil : event
        }
    }
}
