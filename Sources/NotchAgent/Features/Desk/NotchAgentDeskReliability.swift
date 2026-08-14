import Foundation

struct DeskReliabilityAcceptance: Sendable, Equatable {
    var minimumFreeHeapBytes: UInt32 = 120 * 1_024
    // The current 480x320 QSPI panel performs a full rotated flush at ~7.46 FPS.
    // A 7 FPS floor preserves measurable regression headroom without rejecting
    // healthy production hardware.
    var minimumFramesPerSecond: Double = 7
    var maximumTouchLatencyMs: Double = 100
    var maximumInvalidFrames: UInt32 = 0
}

struct DeskReliabilityAssessment: Sendable, Equatable {
    var passed: Bool
    var failures: [String]

    static func assess(
        _ telemetry: DeskDeviceTelemetry,
        acceptance: DeskReliabilityAcceptance = .init()
    ) -> Self {
        var failures: [String] = []
        if telemetry.minimumFreeHeapBytes < acceptance.minimumFreeHeapBytes {
            failures.append("minimum_heap_below_threshold")
        }
        if telemetry.framesPerSecond < acceptance.minimumFramesPerSecond {
            failures.append("fps_below_threshold")
        }
        if telemetry.touchCount > 0,
           telemetry.maximumTouchLatencyMs > acceptance.maximumTouchLatencyMs {
            failures.append("touch_latency_above_threshold")
        }
        if (telemetry.touchReadErrorCount ?? 0) > 0 {
            failures.append("touch_read_errors_detected")
        }
        if telemetry.touchControllerPresent == false {
            failures.append("touch_controller_unavailable")
        }
        if telemetry.invalidFrameCount > acceptance.maximumInvalidFrames {
            failures.append("invalid_frames_detected")
        }
        if ["panic", "interrupt_watchdog", "task_watchdog", "watchdog", "brownout"]
            .contains(telemetry.resetReason) {
            failures.append("unsafe_reset_reason")
        }
        return Self(passed: failures.isEmpty, failures: failures)
    }
}

struct DeskTouchContinuityMonitor: Sendable {
    private var previous: DeskDeviceTelemetry?
    private var saturatedPollingIntervals = 0

    mutating func assess(_ telemetry: DeskDeviceTelemetry) -> String? {
        defer { previous = telemetry }
        guard let previous,
              let attempts = telemetry.touchPollAttemptCount,
              let previousAttempts = previous.touchPollAttemptCount,
              let touches = telemetry.touchPollTouchCount,
              let previousTouches = previous.touchPollTouchCount,
              let interrupts = telemetry.touchInterruptCount,
              let previousInterrupts = previous.touchInterruptCount,
              attempts >= previousAttempts,
              touches >= previousTouches,
              interrupts >= previousInterrupts else {
            saturatedPollingIntervals = 0
            return nil
        }
        let attemptDelta = attempts - previousAttempts
        let touchDelta = touches - previousTouches
        let interruptDelta = interrupts - previousInterrupts
        let uptimeDelta = telemetry.uptimeSeconds >= previous.uptimeSeconds
            ? telemetry.uptimeSeconds - previous.uptimeSeconds
            : 0
        // The failed 0.6.5 candidate produced 64 IRQs in one five-second
        // telemetry interval while untouched. Normalize the limit by device
        // uptime so the same storm cannot hide inside a shorter sample window.
        // A physical gesture observed on this controller stays below 12 IRQ/s.
        if uptimeDelta > 0, uptimeDelta <= 10,
           interruptDelta >= uptimeDelta * 12 {
            saturatedPollingIntervals = 0
            return "touch_irq_storm"
        }
        guard attemptDelta > 0 else { return nil }
        if attemptDelta >= 20, touchDelta == attemptDelta, interruptDelta == 0 {
            saturatedPollingIntervals += 1
        } else {
            saturatedPollingIntervals = 0
        }
        return saturatedPollingIntervals >= 3 ? "touch_contact_stuck" : nil
    }
}
