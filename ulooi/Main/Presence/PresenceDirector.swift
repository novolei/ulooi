import Foundation
import Observation
import LooiKit
import SwiftUI
import UIKit

@MainActor
@Observable
final class PresenceDirector {
    private let session: LooiSession
    private let gestures: GestureLibrary
    private static let bodyNotConnectedLine = "Looi 的小身体还没连上。"

    @ObservationIgnored private var gestureTask: Task<Void, Never>?
    @ObservationIgnored private var gestureGeneration = 0
    @ObservationIgnored private var lastProcessedState: PresenceState? = nil

    private(set) var activeGesture: GestureKind?
    private(set) var isSleeping = false
    private(set) var lastErrorLine: String?
    private(set) var latestAgentState: AgentState? = nil
    private var touchTimeoutGeneration = 0

    var testExpressionOverride: FaceExpression? = nil {
        didSet {
            if let testExpressionOverride {
                playVocalizationAndHaptics(for: testExpressionOverride)
            }
        }
    }

    init(session: LooiSession) {
        self.session = session
        self.gestures = GestureLibrary(motion: session.motion, head: session.head, light: session.light)
        
        // Register message listener to bring Looi's face alive when receiving state payloads from UCLAW Desktop
        TransportManager.shared.registerHandler { [weak self] envelope in
            guard let self = self else { return }
            if envelope.kind == "agent.state", case let .agentState(agentState) = envelope.payload {
                Task { @MainActor in
                    self.latestAgentState = agentState
                }
            }
        }
    }

    var state: PresenceState {
        let derived = PresenceState.derive(
            sessionState: session.state,
            cliffState: session.sensor.cliffState,
            lastTouchDate: session.sensor.lastTouchEvent?.timestamp,
            now: Date(),
            sleeping: isSleeping,
            activeGesture: activeGesture
        )
        // Automatically play vocal sweeps and matching haptics on state transition
        playVocalizationAndHaptics(for: derived)
        return derived
    }

    var face: FaceModel {
        _ = touchTimeoutGeneration // Register reactive dependency tracking
        if let testExpressionOverride {
            let (glow, line) = FaceModel.overrideDynamics(for: testExpressionOverride)
            return FaceModel(expression: testExpressionOverride, gaze: .center, glow: glow, line: line)
        }
        if let agentState = latestAgentState {
            switch agentState.state {
            case "thinking":
                return FaceModel(
                    expression: .looking,
                    gaze: .center,
                    glow: .cyan.opacity(0.85),
                    line: agentState.contextSummary ?? "Thinking..."
                )
            case "speaking":
                return FaceModel(
                    expression: .happy,
                    gaze: .center,
                    glow: .orange.opacity(0.85),
                    line: agentState.contextSummary ?? "Speaking..."
                )
            case "listening":
                return FaceModel(
                    expression: .surprised,
                    gaze: .up,
                    glow: .mint.opacity(0.85),
                    line: agentState.contextSummary ?? "Listening..."
                )
            default:
                break // Fallback to standard
            }
        }

        if session.state == .ready && lastErrorLine == Self.bodyNotConnectedLine {
            return FaceModel.from(state)
        }

        if let lastErrorLine {
            return FaceModel.from(.errorRecoverable(lastErrorLine))
        }
        return FaceModel.from(state)
    }

    func wake() {
        isSleeping = false
        lastErrorLine = nil
    }

    func reconcileSessionState() {
        latestAgentState = nil
        
        guard session.state != .ready else {
            if lastErrorLine == Self.bodyNotConnectedLine {
                lastErrorLine = nil
            }
            return
        }

        gestureGeneration += 1
        gestureTask?.cancel()
        gestureTask = nil
        session.motion.stop()
        activeGesture = nil
        isSleeping = false
        lastErrorLine = nil
    }

    func perform(_ kind: GestureKind) {
        reconcileSessionState()

        guard activeGesture == nil, gestureTask == nil else {
            return
        }

        guard session.state == .ready else {
            lastErrorLine = Self.bodyNotConnectedLine
            return
        }

        gestureGeneration += 1
        let generation = gestureGeneration
        activeGesture = kind
        lastErrorLine = nil

        gestureTask = Task { @MainActor in
            guard generation == gestureGeneration else { return }

            defer {
                if generation == gestureGeneration {
                    activeGesture = nil
                    gestureTask = nil
                }
            }

            do {
                try await gestures.perform(kind)
                guard generation == gestureGeneration else { return }
                isSleeping = (kind == .sleep)
            } catch is CancellationError {
                return
            } catch LooiError.cliffLocked {
                guard generation == gestureGeneration else { return }
                lastErrorLine = "脚下需要支撑，先不乱动。"
            } catch {
                guard generation == gestureGeneration else { return }
                lastErrorLine = "刚刚没配合好，我缓一下。"
            }
        }
    }

    // --- Coordinated Acting Engine (Voice + Haptics Coordination) ---
    private func playVocalizationAndHaptics(for newState: PresenceState) {
        guard let last = lastProcessedState else {
            lastProcessedState = newState
            return
        }
        guard last != newState else { return }
        lastProcessedState = newState

        switch newState {
        case .booting:
            SciFiAudioSynth.shared.playWallEChirp()
            triggerImpactHaptic(style: .medium)
            
        case .lookingForBody:
            SciFiAudioSynth.shared.playRadarPing()
            triggerImpactHaptic(style: .light)
            
        case .awake, .idle:
            if last == .lookingForBody {
                SciFiAudioSynth.shared.playStartupChirp()
                triggerNotificationHaptic(type: .success)
            } else if last == .touched {
                // Settle from touch back to idle
                triggerImpactHaptic(style: .light)
            }
            
        case .touched:
            SciFiAudioSynth.shared.playWallECuriosity()
            triggerImpactHaptic(style: .medium)
            
            // Increment and schedule timeout back to .idle
            touchTimeoutGeneration += 1
            let currentGen = touchTimeoutGeneration
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_250_000_000) // 1.25s
                guard let self = self, self.touchTimeoutGeneration == currentGen else { return }
                self.touchTimeoutGeneration += 1
            }
            
        case .performingGesture(let gesture):
            switch gesture {
            case .wave:
                SciFiAudioSynth.shared.playWallEChirp()
                triggerImpactHaptic(style: .rigid)
            case .sleep:
                SciFiAudioSynth.shared.playWallESleepy()
                triggerNotificationHaptic(type: .success)
            default:
                SciFiAudioSynth.shared.playWallEChirp()
                triggerImpactHaptic(style: .medium)
            }
            
        case .suspended:
            SciFiAudioSynth.shared.playWallEAlarm()
            triggerNotificationHaptic(type: .warning)
            
        case .sleeping:
            break // Managed on sleep gesture trigger
            
        case .disconnected:
            SciFiAudioSynth.shared.playWallESad()
            triggerNotificationHaptic(type: .error)
            
        case .errorRecoverable:
            SciFiAudioSynth.shared.playWallESad()
            triggerNotificationHaptic(type: .warning)
        }
    }

    func playVocalizationAndHaptics(for expression: FaceExpression) {
        switch expression {
        case .idle:
            break
        case .happy:
            SciFiAudioSynth.shared.playWallEChirp()
            triggerImpactHaptic(style: .medium)
        case .surprised:
            SciFiAudioSynth.shared.playWallECuriosity()
            triggerImpactHaptic(style: .medium)
        case .sleepy:
            SciFiAudioSynth.shared.playWallESleepy()
            triggerNotificationHaptic(type: .success)
        case .cautious:
            SciFiAudioSynth.shared.playWallEAlarm()
            triggerNotificationHaptic(type: .warning)
        case .looking:
            SciFiAudioSynth.shared.playRadarPing()
            triggerImpactHaptic(style: .light)
        case .offline:
            SciFiAudioSynth.shared.playWallESad()
            triggerNotificationHaptic(type: .error)
        case .celebration:
            SciFiAudioSynth.shared.playCelebrationChirp()
            triggerNotificationHaptic(type: .success)
        case .victory:
            SciFiAudioSynth.shared.playVictoryFanfare()
            triggerNotificationHaptic(type: .success)
        case .drinking:
            SciFiAudioSynth.shared.playDrinkingBubbles()
            triggerImpactHaptic(style: .medium)
        case .cool:
            SciFiAudioSynth.shared.playCoolSwoosh()
            triggerImpactHaptic(style: .rigid)
        case .cute:
            SciFiAudioSynth.shared.playCuteChirp()
            triggerImpactHaptic(style: .light)
        case .fear:
            SciFiAudioSynth.shared.playFearTremolo()
            triggerNotificationHaptic(type: .error)
        case .ashamed:
            SciFiAudioSynth.shared.playAshamedSigh()
            triggerImpactHaptic(style: .light)
        case .shy:
            SciFiAudioSynth.shared.playShyChirp()
            triggerImpactHaptic(style: .light)
        }
    }

    private func triggerImpactHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private func triggerNotificationHaptic(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
