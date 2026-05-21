import SwiftUI

struct GeometricFaceView: View {
    let model: FaceModel

    @AppStorage("ulooi_face_theme") private var currentThemeRaw: String = FaceTheme.classicWallE.rawValue
    
    var currentTheme: FaceTheme {
        FaceTheme(rawValue: currentThemeRaw) ?? .classicWallE
    }

    // State to track transitions for spring physics
    @State private var previousExpression: FaceExpression = .idle
    @State private var currentExpression: FaceExpression = .idle
    @State private var expressionChangedAt: TimeInterval = Date.now.timeIntervalSinceReferenceDate

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let breath = breathingValue(phase)
            let scan = scanningValue(phase)

            Canvas { context, size in
                drawFace(in: &context, size: size, breath: breath, scan: scan, phase: phase)
            }
            .background(stageBackground(breath: breath, phase: phase, theme: currentTheme, baseGlow: model.glow))
        }
        .onAppear {
            currentExpression = model.expression
            previousExpression = model.expression
            expressionChangedAt = Date.now.timeIntervalSinceReferenceDate
        }
        .onChange(of: model.expression) { oldValue, newValue in
            previousExpression = oldValue
            currentExpression = newValue
            expressionChangedAt = Date.now.timeIntervalSinceReferenceDate
        }
    }

    // --- Spring Physics Mathematical Model (Analytical Damped Spring) ---
    private func springValue(elapsed: Double, duration: Double = 0.55, omegaN: Double = 13.0, damping: Double = 0.58) -> Double {
        let t = max(0, elapsed)
        if t >= duration { return 1.0 }
        
        let zeta = damping
        if zeta >= 1.0 {
            // Critically or over-damped
            return 1.0 - exp(-omegaN * t) * (1.0 + omegaN * t)
        } else {
            // Under-damped (overshoot!)
            let wd = omegaN * sqrt(1.0 - zeta * zeta)
            let cosPart = cos(wd * t)
            let sinPart = sin(wd * t)
            let factor = exp(-zeta * omegaN * t)
            return 1.0 - factor * (cosPart + (zeta * omegaN / wd) * sinPart)
        }
    }

    // --- Saccadic Eye Movements (Continuous Gaze Drift) ---
    private struct SaccadeOffset {
        let x: Double
        let y: Double
    }

    private func calculateSaccade(at phase: Double) -> SaccadeOffset {
        let interval = 2.8
        let intervalIndex = Int(phase / interval)
        let elapsed = phase.truncatingRemainder(dividingBy: interval)
        
        // Seeded random target for the current interval
        let seed1 = sin(Double(intervalIndex) * 7891.23) * 1000.0
        let rand1 = seed1 - floor(seed1)
        let seed2 = cos(Double(intervalIndex) * 3219.87) * 1000.0
        let rand2 = seed2 - floor(seed2)
        
        let currentTargetX = (rand1 * 2.0 - 1.0) * 8.0 // max offset +-8pt
        let currentTargetY = (rand2 * 2.0 - 1.0) * 5.0 // max offset +-5pt
        
        // Seeded random target for the previous interval
        let prevIndex = intervalIndex - 1
        let pSeed1 = sin(Double(prevIndex) * 7891.23) * 1000.0
        let pRand1 = pSeed1 - floor(pSeed1)
        let pSeed2 = cos(Double(prevIndex) * 3219.87) * 1000.0
        let pRand2 = pSeed2 - floor(pSeed2)
        
        let prevTargetX = (pRand1 * 2.0 - 1.0) * 8.0
        let prevTargetY = (pRand2 * 2.0 - 1.0) * 5.0
        
        // Saccades are rapid jumps (omegaN = 25.0, damping = 0.52 for overshoot)
        let t = springValue(elapsed: elapsed, duration: 0.22, omegaN: 25.0, damping: 0.52)
        
        let x = prevTargetX + (currentTargetX - prevTargetX) * t
        let y = prevTargetY + (currentTargetY - prevTargetY) * t
        
        return SaccadeOffset(x: x, y: y)
    }

    // --- Stochastic Blink Generator (Single, Double, or Half Blinks) ---
    private struct BlinkEvent {
        let isBlinking: Bool
        let scaleX: Double
        let scaleY: Double
    }

    private func calculateBlink(at phase: Double) -> BlinkEvent {
        let interval = 3.6
        let intervalIndex = Int(phase / interval)
        let startTimeInInterval = phase.truncatingRemainder(dividingBy: interval)
        
        let seed = sin(Double(intervalIndex) * 4567.89) * 1000.0
        let rand = seed - floor(seed)
        
        // 25% chance of no blink in this interval
        if rand < 0.25 {
            return BlinkEvent(isBlinking: false, scaleX: 1.0, scaleY: 1.0)
        }
        
        // Blink start offset in interval (between 0.4s and 2.6s)
        let blinkStart = 0.4 + rand * 2.2
        let t = startTimeInInterval - blinkStart
        
        let typeSeed = sin(Double(intervalIndex) * 9876.54) * 1000.0
        let typeRand = typeSeed - floor(typeSeed)
        
        let isDoubleBlink = typeRand > 0.70
        let isHalfBlink = typeRand < 0.12
        
        let duration = 0.22
        
        if isDoubleBlink {
            let doubleDuration = duration * 2.0 + 0.08
            if t >= 0 && t < doubleDuration {
                let tLocal: Double
                if t < duration {
                    tLocal = t
                } else if t >= duration && t < duration + 0.08 {
                    // transition open overshoot
                    return BlinkEvent(isBlinking: true, scaleX: 1.12, scaleY: 1.12)
                } else {
                    tLocal = t - duration - 0.08
                }
                return evaluateSingleBlink(t: tLocal, duration: duration, isHalf: false)
            }
        } else {
            if t >= 0 && t < duration {
                return evaluateSingleBlink(t: t, duration: duration, isHalf: isHalfBlink)
            }
        }
        
        return BlinkEvent(isBlinking: false, scaleX: 1.0, scaleY: 1.0)
    }

    private func evaluateSingleBlink(t: Double, duration: Double, isHalf: Bool) -> BlinkEvent {
        let progress = t / duration
        let peak = 0.42 // Peak closure at 42% of duration
        
        if progress < peak {
            // Closing: Squash height, stretch width (Squash & Stretch cartoon physics)
            let localProgress = progress / peak
            let maxSquashX = isHalf ? 0.65 : 0.15 // flatten horizontally
            let maxStretchY = isHalf ? 1.15 : 1.45 // stretch vertically
            
            let scaleX = 1.0 - (1.0 - maxSquashX) * localProgress
            let scaleY = 1.0 + (maxStretchY - 1.0) * localProgress
            return BlinkEvent(isBlinking: true, scaleX: scaleX, scaleY: scaleY)
        } else {
            // Opening: Spring back with bouncy overshoot
            let localProgress = (progress - peak) / (1.0 - peak)
            let overshootX = 1.18
            
            let scaleX: Double
            let scaleY: Double
            
            if localProgress < 0.5 {
                let p = localProgress / 0.5
                let minSquashX = isHalf ? 0.65 : 0.15
                let maxStretchY = isHalf ? 1.15 : 1.45
                scaleX = minSquashX + (overshootX - minSquashX) * p
                scaleY = maxStretchY - (maxStretchY - 1.0) * p
            } else {
                let p = (localProgress - 0.5) / 0.5
                scaleX = overshootX - (overshootX - 1.0) * p
                scaleY = 1.0
            }
            return BlinkEvent(isBlinking: true, scaleX: scaleX, scaleY: scaleY)
        }
    }

    // --- Expression Coordinates & Sizing Dynamics ---
    private struct EyeState {
        var baseSize: CGSize
        var scaleX: Double
        var scaleY: Double
        var tilt: Double
        var color: Color
        var gazeOffset: CGSize
        var eyebrowAngle: Double // radians
        var eyebrowOffset: Double // pt
    }

    private enum EyeSide {
        case left
        case right
    }

    private func evaluateExpressionDynamics(
        expression: FaceExpression,
        side: EyeSide,
        phase: Double,
        size: CGSize,
        shortestSide: Double
    ) -> EyeState {
        let baseWidth = shortestSide * 0.22
        var state = EyeState(
            baseSize: CGSize(width: baseWidth, height: shortestSide * 0.14),
            scaleX: 1.0,
            scaleY: 1.0,
            tilt: 0.0,
            color: .yellow,
            gazeOffset: .zero,
            eyebrowAngle: 0.0,
            eyebrowOffset: 0.0
        )

        // Color mapping
        switch expression {
        case .offline: state.color = .white.opacity(0.36)
        case .cautious: state.color = .pink.opacity(0.92)
        case .sleepy: state.color = .cyan.opacity(0.72)
        case .surprised: state.color = .mint.opacity(0.95)
        case .looking: state.color = .cyan.opacity(0.92)
        case .happy: state.color = .yellow
        case .idle: state.color = .yellow.opacity(0.96)
        case .celebration: state.color = .orange
        case .victory: state.color = .yellow
        case .drinking: state.color = Color(red: 1.0, green: 0.45, blue: 0.45)
        case .cool: state.color = .white
        case .cute: state.color = Color(red: 1.0, green: 0.55, blue: 0.75)
        case .fear: state.color = Color(red: 0.3, green: 0.5, blue: 1.0)
        case .ashamed: state.color = Color(red: 0.35, green: 0.75, blue: 0.95)
        case .shy: state.color = Color(red: 1.0, green: 0.65, blue: 0.65)
        }

        // Base sizing
        switch expression {
        case .sleepy:
            state.baseSize = CGSize(width: baseWidth * 1.05, height: shortestSide * 0.055)
        case .cautious:
            state.baseSize = CGSize(width: baseWidth, height: shortestSide * 0.105)
        case .surprised:
            state.baseSize = CGSize(width: baseWidth * 1.03, height: shortestSide * 0.20)
        case .offline:
            state.baseSize = CGSize(width: baseWidth * 0.96, height: shortestSide * 0.095)
        case .happy:
            state.baseSize = CGSize(width: baseWidth * 1.08, height: shortestSide * 0.155)
        case .looking:
            state.baseSize = CGSize(width: baseWidth, height: shortestSide * 0.145)
        case .idle:
            state.baseSize = CGSize(width: baseWidth, height: shortestSide * 0.14)
        case .celebration:
            state.baseSize = CGSize(width: baseWidth * 1.12, height: shortestSide * 0.17)
        case .victory:
            state.baseSize = CGSize(width: baseWidth * 1.10, height: shortestSide * 0.16)
        case .drinking:
            state.baseSize = CGSize(width: baseWidth * 1.05, height: shortestSide * 0.15)
        case .cool:
            state.baseSize = CGSize(width: baseWidth * 1.02, height: shortestSide * 0.13)
        case .cute:
            state.baseSize = CGSize(width: baseWidth * 1.08, height: shortestSide * 0.15)
        case .fear:
            state.baseSize = CGSize(width: baseWidth * 0.95, height: shortestSide * 0.18)
        case .ashamed:
            state.baseSize = CGSize(width: baseWidth * 0.98, height: shortestSide * 0.10)
        case .shy:
            state.baseSize = CGSize(width: baseWidth * 1.05, height: shortestSide * 0.135)
        }

        // Eye specific side dynamics
        let sideSign = side == .left ? 1.0 : -1.0
        
        switch expression {
        case .idle:
            // Concerned curious tilt (Pixar optical angle)
            let tiltAmp = 0.06 + 0.03 * sin(phase * 1.1)
            state.tilt = sideSign * tiltAmp
            
            // Saccadic drift gaze
            let saccade = calculateSaccade(at: phase)
            state.gazeOffset = CGSize(width: saccade.x, height: saccade.y)
            
            // Iris breathing
            let irisBreath = sin(phase * 1.1 + (side == .left ? 0.0 : 0.8)) * 0.04
            state.scaleX += irisBreath
            state.scaleY += irisBreath

        case .happy:
            // Inward playful tilt
            let wiggle = sin(phase * 4.5) * 0.045
            state.tilt = sideSign * 0.105 + wiggle
            
            // Playful vertical bouncing
            let bounce = sin(phase * 5.0) * 0.05
            state.scaleY += bounce
            state.scaleX -= bounce * 0.5

        case .surprised:
            // Outward tilt
            let tremble = sin(phase * 48.0) * 0.02
            state.tilt = -sideSign * 0.052 + tremble
            
            // High frequency tremble shake (excited trembling)
            let shakeX = sin(phase * 50.0) * 1.5
            let shakeY = cos(phase * 52.0) * 1.5
            state.gazeOffset = CGSize(width: shakeX, height: -shortestSide * 0.015 + shakeY)
            
            // Wide-eye stretch (Squash & Stretch)
            state.scaleY = 1.18
            state.scaleX = 0.92

        case .sleepy:
            // Evaluates the continuous sleepy dozing sequence
            let cycle = 12.0
            let tSleep = phase.truncatingRemainder(dividingBy: cycle)
            
            if tSleep < 4.0 {
                // Doze off: slowly close to 20% height
                let p = tSleep / 4.0
                state.scaleY = 1.0 - p * 0.80
                state.tilt = -sideSign * 0.07 // tilt outward
            } else if tSleep < 4.5 {
                // Snap back open partially
                let p = (tSleep - 4.0) / 0.5
                state.scaleY = 0.20 + p * 0.45
                state.tilt = -sideSign * 0.04
            } else if tSleep < 7.0 {
                // Yawn squash tight!
                let p = (tSleep - 4.5) / 2.5
                state.scaleY = 0.65 - p * 0.60
                state.scaleX = 1.0 + p * 0.32
                state.tilt = sideSign * 0.12 // squeeze angle
            } else {
                // Deep sleep lines
                state.scaleY = 0.05
                state.scaleX = 1.12
                state.tilt = -sideSign * 0.02
            }
            
            // Slow sleepy breathing
            let sleepBreath = sin(phase * 0.8) * 0.03
            state.scaleX += sleepBreath
            state.scaleY += sleepBreath
            state.gazeOffset = CGSize(width: 0, height: shortestSide * 0.02)

        case .cautious:
            // Intense inward squint angle
            state.tilt = sideSign * (side == .left ? 0.192 : -0.227)
            state.scaleY = 0.35
            state.scaleX = 1.15
            
            // Rapid scanning left-right
            let scanX = sin(phase * 4.8) * (shortestSide * 0.055)
            state.gazeOffset = CGSize(width: scanX, height: 0)
            
            // Sharp angled brows
            state.eyebrowAngle = -sideSign * 0.28
            state.eyebrowOffset = shortestSide * 0.015

        case .looking:
            // Focus tracking tilt
            state.tilt = sideSign * 0.04 + sin(phase * 1.5) * 0.03
            
            // Smooth infinity-shaped sweep
            let sweepX = cos(phase * 1.8) * (shortestSide * 0.055)
            let sweepY = sin(phase * 3.6) * (shortestSide * 0.022)
            state.gazeOffset = CGSize(width: sweepX, height: sweepY)
            
            // Focusing size dilation
            let focus = sin(phase * 2.2) * 0.06
            state.scaleX += focus
            state.scaleY -= focus

        case .offline:
            state.tilt = 0.0
            state.scaleY = 0.95
            state.scaleX = 0.95

        case .celebration:
            // Dynamic rapid victory tilt
            let wiggle = sin(phase * 6.0) * 0.08
            state.tilt = sideSign * 0.12 + wiggle
            // Excited vertical stretch-bounce
            let bounce = sin(phase * 8.0) * 0.12
            state.scaleY += bounce
            state.scaleX -= bounce * 0.4
            state.gazeOffset = CGSize(width: 0, height: -shortestSide * 0.01 + sin(phase * 10.0) * 3.0)

        case .victory:
            state.tilt = sideSign * 0.05
            let bounce = sin(phase * 4.0) * 0.04
            state.scaleY += bounce
            state.gazeOffset = CGSize(width: 0, height: -shortestSide * 0.015)
            // Confident brows
            state.eyebrowAngle = -sideSign * 0.12
            state.eyebrowOffset = shortestSide * 0.01

        case .drinking:
            // Slow, tipsy sway
            let sway = sin(phase * 2.0) * 0.06
            state.tilt = sideSign * 0.05 + sway
            // Tipsy half-closed eyes
            state.scaleY = 0.75 + 0.1 * cos(phase * 2.0)
            state.gazeOffset = CGSize(width: sin(phase * 1.5) * 4.0, height: shortestSide * 0.015)

        case .cool:
            state.tilt = 0.0
            state.scaleY = 0.65 // cool squint
            state.scaleX = 1.05
            state.gazeOffset = CGSize(width: 0, height: -shortestSide * 0.005)

        case .cute:
            // Extremely cute inward tilt
            state.tilt = sideSign * 0.18 + sin(phase * 3.0) * 0.03
            let pulse = sin(phase * 4.5) * 0.08
            state.scaleX += pulse
            state.scaleY += pulse
            state.gazeOffset = CGSize(width: -sideSign * 2.0, height: -shortestSide * 0.005)

        case .fear:
            // Trembling tilt
            state.tilt = sideSign * 0.02 + sin(phase * 60.0) * 0.035
            // High frequency panic shake
            let shakeX = sin(phase * 55.0) * 4.0
            let shakeY = cos(phase * 58.0) * 4.0
            state.gazeOffset = CGSize(width: shakeX, height: shakeY)
            state.scaleY = 1.25 // wide open with fear
            state.scaleX = 0.90
            // Terrified brows: slanted high and outwards
            state.eyebrowAngle = sideSign * 0.25
            state.eyebrowOffset = shortestSide * 0.025

        case .ashamed:
            // Drooping outward tilt
            state.tilt = -sideSign * 0.10
            state.scaleY = 0.45 // ashamed droop
            // Looking down
            state.gazeOffset = CGSize(width: -sideSign * 3.0, height: shortestSide * 0.02)
            // Sad slanting brows
            state.eyebrowAngle = sideSign * 0.15
            state.eyebrowOffset = -shortestSide * 0.005

        case .shy:
            // Shy tilted eyes
            state.tilt = sideSign * 0.08
            state.scaleY = 0.85
            // Darting look away
            let lookDart = sin(phase * 1.8) > 0.0 ? sideSign * 6.0 : -sideSign * 2.0
            state.gazeOffset = CGSize(width: lookDart, height: shortestSide * 0.01)
            state.eyebrowAngle = -sideSign * 0.05
        }

        return state
    }

    // --- Main Rendering and Orchestration ---
    private func drawFace(
        in context: inout GraphicsContext,
        size: CGSize,
        breath: Double,
        scan: Double,
        phase: Double
    ) {
        let theme = currentTheme
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        
        let baseGaze = gazeOffset(model.gaze, size: size)
        
        // 3D Parallax: 25% of the base gaze shifts the entire eye socket (simulating head tilt/rotation)
        let headGazeX = baseGaze.width * 0.25
        let headGazeY = baseGaze.height * 0.25
        
        let eyeSpacing = shortestSide * 0.32
        let eyeY = faceCenter.y - shortestSide * 0.04 + headGazeY

        // Background decorative elements
        if theme == .cyberpunkMatrix {
            drawCyberpunkGrid(in: &context, size: size, phase: phase)
        } else if theme == .nebulaCosmic {
            drawCosmicStarfield(in: &context, size: size, phase: phase)
        }

        // Happy sunrays (disabled for minimalist)
        if (currentExpression == .happy || (previousExpression == .happy && (phase - expressionChangedAt < 0.6))) && theme != .minimalistIron {
            let happyProgress = springValue(elapsed: phase - expressionChangedAt)
            let opacityMult = currentExpression == .happy ? happyProgress : (1.0 - happyProgress)
            drawHappySunrays(in: &context, size: size, phase: phase, opacity: opacityMult, theme: theme)
        }

        drawHalo(in: &context, size: size, center: faceCenter, breath: breath, theme: theme, baseGlow: model.glow)
        drawScanLine(in: &context, size: size, scan: scan, theme: theme, baseGlow: model.glow)
        drawSafetyAccent(in: &context, size: size, breath: breath, phase: phase, theme: theme, baseGlow: model.glow)

        // Render Left and Right Eyes with independent coordinate systems
        for side in [EyeSide.left, EyeSide.right] {
            let sideSign = side == .left ? -1.0 : 1.0
            let eyeCenterBase = CGPoint(x: faceCenter.x + sideSign * eyeSpacing + headGazeX, y: eyeY)

            // Asymmetric micro-delay (0.045s delay on the right eye for organic ocular delay)
            let sidePhase = side == .left ? phase : (phase - 0.045)
            let elapsed = sidePhase - expressionChangedAt

            // Spring-damped state interpolation (overshoot & settle)
            let progress = springValue(elapsed: elapsed)

            let statePrev = evaluateExpressionDynamics(
                expression: previousExpression,
                side: side,
                phase: sidePhase,
                size: size,
                shortestSide: shortestSide
            )
            let stateNew = evaluateExpressionDynamics(
                expression: currentExpression,
                side: side,
                phase: sidePhase,
                size: size,
                shortestSide: shortestSide
            )

            // Interpolate states using physical spring progress
            let eyeSize = CGSize(
                width: statePrev.baseSize.width + (stateNew.baseSize.width - statePrev.baseSize.width) * progress,
                height: statePrev.baseSize.height + (stateNew.baseSize.height - statePrev.baseSize.height) * progress
            )
            var scaleX = statePrev.scaleX + (stateNew.scaleX - statePrev.scaleX) * progress
            var scaleY = statePrev.scaleY + (stateNew.scaleY - statePrev.scaleY) * progress
            let tilt = statePrev.tilt + (stateNew.tilt - statePrev.tilt) * progress
            let eyebrowAngle = statePrev.eyebrowAngle + (stateNew.eyebrowAngle - statePrev.eyebrowAngle) * progress
            let eyebrowOffset = statePrev.eyebrowOffset + (stateNew.eyebrowOffset - statePrev.eyebrowOffset) * progress

            let colorPrev = statePrev.color
            let colorNew = stateNew.color
            let color = progress >= 0.5 ? colorNew : colorPrev

            let extraGaze = CGSize(
                width: statePrev.gazeOffset.width + (stateNew.gazeOffset.width - statePrev.gazeOffset.width) * progress,
                height: statePrev.gazeOffset.height + (stateNew.gazeOffset.height - statePrev.gazeOffset.height) * progress
            )

            // 3D Parallax: Combine remaining 75% of head gaze with high-frequency saccadic eye drift for the pupil
            let pupilGazeX = baseGaze.width * 0.75 + extraGaze.width
            let pupilGazeY = baseGaze.height * 0.75 + extraGaze.height
            let pupilGaze = CGSize(width: pupilGazeX, height: pupilGazeY)

            // Evaluate stochastic blinks
            let blink = calculateBlink(at: sidePhase)
            if blink.isBlinking {
                scaleX *= blink.scaleX
                scaleY *= blink.scaleY
            }

            // Draw Eye under isolated coordinates (eyeball center is stationary)
            drawEye(
                in: &context,
                center: eyeCenterBase,
                size: eyeSize,
                gazeOffset: pupilGaze,
                scaleX: scaleX,
                scaleY: scaleY,
                tilt: tilt,
                color: color,
                breath: breath,
                phase: sidePhase,
                expression: currentExpression,
                theme: theme
            )

            // Draw Eyebrow details relative to Eye Center
            drawEyebrow(
                in: &context,
                eyeCenter: eyeCenterBase,
                eyeSize: eyeSize,
                angle: eyebrowAngle,
                offset: eyebrowOffset,
                side: side,
                theme: theme
            )
        }

        // Draw general expressions overlay (mouths, smiles, etc.)
        drawExpressionDetails(in: &context, size: size, phase: phase, theme: theme)
    }

    // --- High-Fidelity Vector Rendering Helpers ---

    private func drawCosmicStarfield(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let starCount = 35
        for i in 0..<starCount {
            // Deterministic pseudo-random generation using sin/cos of the index
            let seedX = sin(Double(i) * 1234.56) * 0.5 + 0.5 // [0, 1]
            let seedY = cos(Double(i) * 7890.12) * 0.5 + 0.5 // [0, 1]
            let speed = 15.0 + (sin(Double(i) * 345.67) * 5.0) // drift speed
            let sizeMultiplier = 1.0 + (cos(Double(i) * 890.12) * 0.5 + 0.5) * 2.0 // star size 1.0 to 3.0 pt
            
            // Dynamic drifting positions
            let driftX = sin(phase * 0.15 + Double(i)) * 10.0
            let driftY = -phase * speed // floating upwards
            
            var x = (seedX * size.width) + driftX
            var y = (seedY * size.height) + driftY
            
            // Wrap coordinates so stars stay on screen
            x = x.truncatingRemainder(dividingBy: size.width)
            if x < 0 { x += size.width }
            y = y.truncatingRemainder(dividingBy: size.height)
            if y < 0 { y += size.height }
            
            let starRect = CGRect(x: x, y: y, width: sizeMultiplier, height: sizeMultiplier)
            
            // Twinkling opacity
            let twinkle = 0.35 + 0.65 * (sin(phase * 2.2 + Double(i)) * 0.5 + 0.5)
            
            // Pastel cosmic colors for starlight: purple, magenta, cyan, white
            let colorIndex = i % 4
            let starColor: Color
            if colorIndex == 0 {
                starColor = Color(red: 0.72, green: 0.34, blue: 1.0).opacity(twinkle)
            } else if colorIndex == 1 {
                starColor = Color(red: 1.0, green: 0.42, blue: 0.85).opacity(twinkle)
            } else if colorIndex == 2 {
                starColor = Color(red: 0.35, green: 0.85, blue: 1.0).opacity(twinkle)
            } else {
                starColor = Color.white.opacity(twinkle)
            }
            
            context.fill(Path(ellipseIn: starRect), with: .color(starColor))
        }
    }

    private func drawCyberpunkGrid(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let step: CGFloat = 20.0
        var gridPath = Path()
        
        // Vertical grid lines
        var x: CGFloat = 0
        while x < size.width {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        
        // Horizontal grid lines
        var y: CGFloat = 0
        while y < size.height {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        
        // Pulse intensity
        let gridPulse = 0.012 + 0.008 * sin(phase * 1.5)
        context.stroke(
            gridPath,
            with: .color(Color(red: 0.0, green: 1.0, blue: 0.2).opacity(gridPulse)),
            style: StrokeStyle(lineWidth: 0.5)
        )
        
        // Add glowing sweeping bar
        let sweepY = (phase * 120.0).truncatingRemainder(dividingBy: size.height + 200.0) - 100.0
        let sweepRect = CGRect(x: 0, y: sweepY, width: size.width, height: 80.0)
        context.fill(
            Path(sweepRect),
            with: .linearGradient(
                Gradient(colors: [.clear, Color(red: 0.0, green: 1.0, blue: 0.2).opacity(0.04), .clear]),
                startPoint: CGPoint(x: 0, y: sweepY),
                endPoint: CGPoint(x: 0, y: sweepY + 80.0)
            )
        )
    }

    private func drawHappySunrays(in context: inout GraphicsContext, size: CGSize, phase: Double, opacity: Double, theme: FaceTheme) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let maxRadius = max(size.width, size.height)
        let rayCount = 8
        let rotationAngle = phase * 0.16 // Slow majestic rotation
        
        let rayColor: Color
        switch theme {
        case .classicWallE:
            rayColor = .yellow
        case .cyberpunkMatrix:
            rayColor = Color(red: 0.0, green: 1.0, blue: 0.25)
        case .nebulaCosmic:
            rayColor = Color(red: 0.85, green: 0.2, blue: 1.0)
        case .holographicAurora:
            rayColor = Color(red: 0.15, green: 0.85, blue: 1.0)
        case .minimalistIron:
            return
        }
        
        for i in 0..<rayCount {
            let baseAngle = Double(i) * (.pi * 2.0 / Double(rayCount)) + rotationAngle
            let widthAngle = 0.14 + sin(phase * 1.6 + Double(i)) * 0.035 // Shimmering ray width
            
            var path = Path()
            path.move(to: center)
            path.addArc(
                center: center,
                radius: maxRadius,
                startAngle: Angle(radians: baseAngle - widthAngle),
                endAngle: Angle(radians: baseAngle + widthAngle),
                clockwise: false
            )
            path.closeSubpath()
            
            // Ambient shimmering pulse
            let rayOpacity = (0.035 + 0.015 * sin(phase * 2.4 + Double(i))) * opacity
            context.fill(path, with: .color(rayColor.opacity(rayOpacity)))
        }
    }

    private func drawHalo(in context: inout GraphicsContext, size: CGSize, center: CGPoint, breath: Double, theme: FaceTheme, baseGlow: Color) {
        guard theme != .minimalistIron else { return } // Minimalist has zero distracting halo!

        let haloMultiplier: Double
        let colors: [Color]
        
        switch theme {
        case .classicWallE:
            haloMultiplier = 0.86
            colors = [baseGlow.opacity(0.22 + breath * 0.18), .clear]
        case .cyberpunkMatrix:
            haloMultiplier = 0.75
            colors = [Color(red: 0.0, green: 1.0, blue: 0.25).opacity(0.14 + breath * 0.10), .clear]
        case .nebulaCosmic:
            // Large magical cosmic dust halo
            haloMultiplier = 1.05
            colors = [
                Color(red: 0.85, green: 0.2, blue: 1.0).opacity(0.24 + breath * 0.20),
                Color(red: 0.18, green: 0.02, blue: 0.45).opacity(0.08 + breath * 0.06),
                .clear
            ]
        case .holographicAurora:
            // Multi-layered iridescent neon aura halo
            haloMultiplier = 0.95
            colors = [
                Color(red: 1.0, green: 0.2, blue: 0.85).opacity(0.22 + breath * 0.16),
                Color(red: 0.15, green: 0.85, blue: 1.0).opacity(0.12 + breath * 0.10),
                .clear
            ]
        case .minimalistIron:
            return
        }

        let haloSize = min(size.width, size.height) * (haloMultiplier + breath * 0.06)
        let rect = CGRect(
            x: center.x - haloSize / 2,
            y: center.y - haloSize / 2,
            width: haloSize,
            height: haloSize
        )

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: colors),
                center: center,
                startRadius: 0,
                endRadius: haloSize * 0.52
            )
        )
    }

    private func drawScanLine(in context: inout GraphicsContext, size: CGSize, scan: Double, theme: FaceTheme, baseGlow: Color) {
        guard model.expression != .sleepy else { return }
        // Scanlines only appear for Wall-E and Cyberpunk Matrix
        guard theme == .classicWallE || theme == .cyberpunkMatrix else { return }

        let y = size.height * (0.26 + scan * 0.36)
        let start = CGPoint(x: size.width * 0.23, y: y)
        let end = CGPoint(x: size.width * 0.77, y: y)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let color = theme == .cyberpunkMatrix ? Color(red: 0.0, green: 1.0, blue: 0.25) : baseGlow
        let opacity = theme == .cyberpunkMatrix ? (0.46 + sin(scan * .pi) * 0.2) : 0.34

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(opacity), .clear]),
                startPoint: start,
                endPoint: end
            ),
            style: StrokeStyle(lineWidth: max(1.2, size.height * 0.0035), lineCap: .round)
        )
    }

    private func drawSafetyAccent(in context: inout GraphicsContext, size: CGSize, breath: Double, phase: Double, theme: FaceTheme, baseGlow: Color) {
        guard model.expression == .cautious || model.expression == .offline else { return }

        let width = min(size.width, size.height) * (theme == .minimalistIron ? 0.25 : 0.34)
        let height = theme == .minimalistIron ? max(2, size.height * 0.005) : max(3, size.height * 0.008)
        let rect = CGRect(
            x: size.width * 0.5 - width / 2,
            y: size.height * 0.76,
            width: width,
            height: height
        )

        let opacity: Double
        if model.expression == .cautious {
            // Heartbeat triple pulse formula (110 BPM anxious heartbeat)
            let heartTime = phase * 2.0 * .pi * (110.0 / 60.0)
            let pulse = pow(sin(heartTime), 4.0) + 0.45 * pow(sin(heartTime + 0.28), 4.0)
            opacity = 0.25 + 0.65 * pulse
        } else {
            opacity = 0.36 + breath * 0.24
        }

        let accentColor: Color
        switch theme {
        case .classicWallE:
            accentColor = baseGlow
        case .cyberpunkMatrix:
            accentColor = Color(red: 0.0, green: 1.0, blue: 0.25)
        case .nebulaCosmic:
            accentColor = Color(red: 0.85, green: 0.2, blue: 1.0)
        case .holographicAurora:
            accentColor = Color(red: 0.15, green: 0.85, blue: 1.0)
        case .minimalistIron:
            accentColor = .white
        }

        context.fill(
            Path(roundedRect: rect, cornerRadius: rect.height / 2),
            with: .color(accentColor.opacity(theme == .minimalistIron ? opacity * 0.65 : opacity))
        )
    }

    private func drawEye(
        in context: inout GraphicsContext,
        center: CGPoint,
        size: CGSize,
        gazeOffset: CGSize,
        scaleX: Double,
        scaleY: Double,
        tilt: Double,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        theme: FaceTheme
    ) {
        var eyeContext = context
        eyeContext.translateBy(x: center.x, y: center.y)
        eyeContext.rotate(by: Angle(radians: tilt))

        // We define the normal un-squashed eyeball rect (always a constant size)
        let rect = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )

        // Calculate the eyelid aperture. During blinking or expressions, the eyelids close 
        // by squashing the vertical aperture (scaleY) and stretching width (scaleX) 
        // to implement the Squash & Stretch cartoon physics.
        // We define this as an elliptical clipping path:
        let visibleEyePath = Path(ellipseIn: CGRect(
            x: -size.width * 0.5 * scaleX,
            y: -size.height * 0.5 * scaleY,
            width: size.width * scaleX,
            height: size.height * scaleY
        ))

        // First, clip to the eyelid aperture so nothing drawn inside bleeds out!
        eyeContext.clip(to: visibleEyePath)

        // Render Eye Details based on Theme procedurally (100% transparent backgrounds)
        switch theme {
        case .classicWallE:
            drawDisneyProceduralEye(
                in: &eyeContext,
                rect: rect,
                size: size,
                gazeOffset: gazeOffset,
                color: color,
                breath: breath,
                phase: phase,
                expression: expression,
                scaleX: scaleX,
                scaleY: scaleY
            )
            
        case .nebulaCosmic:
            drawGhibliProceduralEye(
                in: &eyeContext,
                rect: rect,
                size: size,
                gazeOffset: gazeOffset,
                color: color,
                breath: breath,
                phase: phase,
                expression: expression,
                scaleX: scaleX,
                scaleY: scaleY
            )
            
        case .cyberpunkMatrix:
            drawCyberpunkProceduralEye(
                in: &eyeContext,
                rect: rect,
                size: size,
                gazeOffset: gazeOffset,
                color: color,
                breath: breath,
                phase: phase,
                expression: expression,
                scaleX: scaleX,
                scaleY: scaleY
            )
            
        case .holographicAurora:
            drawAuroraProceduralEye(
                in: &eyeContext,
                rect: rect,
                size: size,
                gazeOffset: gazeOffset,
                color: color,
                breath: breath,
                phase: phase,
                expression: expression,
                scaleX: scaleX,
                scaleY: scaleY
            )
            
        case .minimalistIron:
            drawMinimalistProceduralEye(
                in: &eyeContext,
                rect: rect,
                size: size,
                gazeOffset: gazeOffset,
                color: color,
                breath: breath,
                phase: phase,
                expression: expression,
                scaleX: scaleX,
                scaleY: scaleY
            )
        }
    }

    private func drawDisneyProceduralEye(
        in context: inout GraphicsContext,
        rect: CGRect,
        size: CGSize,
        gazeOffset: CGSize,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        scaleX: Double,
        scaleY: Double
    ) {
        // Soft ambient glow surrounding the lens (OLED optimized)
        if expression != .offline {
            let glowColor = Color.orange.opacity(0.32 + breath * 0.15)
            context.addFilter(.shadow(color: glowColor, radius: 22.0 + breath * 8.0))
        }

        if expression == .offline {
            context.opacity = 0.35
        }

        if expression == .happy || expression == .celebration || expression == .victory || expression == .cute {
            // Apply smiling crescent mask inside the eyelids
            var happyClip = Path()
            happyClip.move(to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY))
            happyClip.addQuadCurve(
                to: CGPoint(x: size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.72 * scaleY)
            )
            happyClip.addQuadCurve(
                to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.18 * scaleY)
            )
            context.clip(to: happyClip)
        }

        // 1. Draw Deep Sclera/Socket base with a metallic radial gradient
        let outerEyeball = Path(ellipseIn: rect)
        let scleraGradient = Gradient(colors: [
            Color(white: 0.16),
            Color(white: 0.08),
            Color(white: 0.01)
        ])
        context.fill(
            outerEyeball,
            with: .radialGradient(
                scleraGradient,
                center: .zero,
                startRadius: 0,
                endRadius: min(size.width, size.height) * 0.5
            )
        )

        // 2. Slide the inner camera Iris & Pupil layer based on gaze (3D Parallax!)
        var parallaxContext = context
        parallaxContext.translateBy(x: gazeOffset.width * 0.35, y: gazeOffset.height * 0.35)

        let minDimension = min(size.width, size.height)
        let irisRadius = minDimension * 0.45
        let irisRect = CGRect(x: -irisRadius, y: -irisRadius, width: irisRadius * 2, height: irisRadius * 2)

        // Fill Iris Base with gorgeous copper-amber gradient
        let irisGradient = Gradient(colors: [
            Color(red: 1.0, green: 0.52, blue: 0.05).opacity(0.96),
            Color(red: 0.65, green: 0.22, blue: 0.01).opacity(0.85),
            .black
        ])
        parallaxContext.fill(
            Path(ellipseIn: irisRect),
            with: .radialGradient(
                irisGradient,
                center: .zero,
                startRadius: 0,
                endRadius: irisRadius
            )
        )

        // 3. Draw 24-ray Shimmering Camera Lens Iris Fibers
        let numRays = 24
        let pupilScale: Double
        switch expression {
        case .surprised: pupilScale = 0.72
        case .sleepy: pupilScale = 0.25
        case .offline: pupilScale = 0.15
        case .cautious: pupilScale = 0.35
        case .happy: pupilScale = 0.50
        case .celebration: pupilScale = 0.52
        case .victory: pupilScale = 0.54
        case .drinking: pupilScale = 0.45
        case .cool: pupilScale = 0.42
        case .cute: pupilScale = 0.58
        case .fear: pupilScale = 0.20
        case .ashamed: pupilScale = 0.32
        case .shy: pupilScale = 0.48
        case .idle, .looking:
            // Gentle biological pupil pupil breathing oscillation
            pupilScale = 0.46 + 0.03 * sin(phase * 2.2)
        }
        let pupilRadius = irisRadius * pupilScale

        for i in 0..<numRays {
            let theta = Double(i) * (2.0 * .pi / Double(numRays))
            let rayPhase = phase * 3.5 + Double(i) * 0.45
            let rayShimmer = 0.32 * sin(rayPhase) + 0.68
            
            let rayStart = CGPoint(x: cos(theta) * (pupilRadius * 1.05), y: sin(theta) * (pupilRadius * 1.05))
            let rayEnd = CGPoint(x: cos(theta) * (irisRadius * 0.95), y: sin(theta) * (irisRadius * 0.95))
            
            var rayPath = Path()
            rayPath.move(to: rayStart)
            rayPath.addLine(to: rayEnd)
            
            parallaxContext.stroke(
                rayPath,
                with: .color(Color(red: 1.0, green: 0.75, blue: 0.2).opacity(breath * 0.38 * rayShimmer)),
                lineWidth: 1.2
            )
        }

        // Draw Black Metal Aperture Ring
        parallaxContext.stroke(
            Path(ellipseIn: irisRect),
            with: .color(Color(white: 0.05)),
            lineWidth: 2.0
        )

        // 4. Draw Pupil Core
        let pupilRect = CGRect(x: -pupilRadius, y: -pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2)
        let pupilPath = Path(ellipseIn: pupilRect)
        parallaxContext.fill(pupilPath, with: .color(.black))

        // Draw delicate inner shutter detailing inside the pupil
        let innerRim = pupilRect.insetBy(dx: max(1, pupilRadius * 0.12), dy: max(1, pupilRadius * 0.12))
        parallaxContext.stroke(
            Path(ellipseIn: innerRim),
            with: .color(Color(white: 0.12)),
            lineWidth: 1.0
        )

        // 5. Draw stationary 3D Spherical Specular Glass Highlights (curved dome reflection)
        if expression != .offline && expression != .sleepy {
            drawGlassHighlight(in: &context, size: size, theme: .classicWallE)
        }
    }

    private func drawGhibliProceduralEye(
        in context: inout GraphicsContext,
        rect: CGRect,
        size: CGSize,
        gazeOffset: CGSize,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        scaleX: Double,
        scaleY: Double
    ) {
        // Soft purple/magenta breathing aura
        if expression != .offline {
            let glowColor = Color(red: 0.85, green: 0.35, blue: 1.0).opacity(0.38 + breath * 0.18)
            context.addFilter(.shadow(color: glowColor, radius: 28.0 + breath * 10.0))
        }

        if expression == .offline {
            context.opacity = 0.35
        }

        if expression == .happy || expression == .celebration || expression == .victory || expression == .cute {
            // Smiling crescent mask
            var happyClip = Path()
            happyClip.move(to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY))
            happyClip.addQuadCurve(
                to: CGPoint(x: size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.72 * scaleY)
            )
            happyClip.addQuadCurve(
                to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.18 * scaleY)
            )
            context.clip(to: happyClip)
        }

        // 1. Cozy deep-plum watercolor base
        let outerEyeball = Path(ellipseIn: rect)
        let watercolorBaseGradient = Gradient(colors: [
            Color(red: 0.12, green: 0.06, blue: 0.22),
            Color(red: 0.05, green: 0.02, blue: 0.10)
        ])
        context.fill(
            outerEyeball,
            with: .radialGradient(
                watercolorBaseGradient,
                center: .zero,
                startRadius: 0,
                endRadius: min(size.width, size.height) * 0.5
            )
        )

        // 2. Watercolor hand-painted Iris Core with organic wiggling edges (via Perturbed Bezier)
        var parallaxContext = context
        parallaxContext.translateBy(x: gazeOffset.width * 0.35, y: gazeOffset.height * 0.35)

        let minDimension = min(size.width, size.height)
        let baseIrisRadius = minDimension * 0.44
        
        // Let's draw an organically perturbed iris path
        var irisPath = Path()
        let numPoints = 16
        for i in 0..<numPoints {
            let theta = Double(i) * (2.0 * .pi / Double(numPoints))
            let wave = sin(phase * 1.8 + Double(i) * 1.1) * (baseIrisRadius * 0.02)
            let r = baseIrisRadius + wave
            let pt = CGPoint(x: cos(theta) * r, y: sin(theta) * r)
            if i == 0 {
                irisPath.move(to: pt)
            } else {
                irisPath.addLine(to: pt)
            }
        }
        irisPath.closeSubpath()

        let irisGradient = Gradient(colors: [
            Color(red: 0.85, green: 0.40, blue: 0.95).opacity(0.95),
            Color(red: 0.45, green: 0.15, blue: 0.70).opacity(0.85),
            Color(red: 0.15, green: 0.02, blue: 0.30)
        ])
        parallaxContext.fill(
            irisPath,
            with: .radialGradient(
                irisGradient,
                center: .zero,
                startRadius: 0,
                endRadius: baseIrisRadius
            )
        )

        // 3. Real-Time Particle Simulation: Drifting Nebula Stardust
        for i in 0..<6 {
            let seedY = Double(i) * 0.18
            let t = (phase * 0.06 + seedY).truncatingRemainder(dividingBy: 1.0)
            
            // Drift upward
            let y = baseIrisRadius * 0.8 - t * (baseIrisRadius * 1.6)
            let waveX = sin(phase * 1.3 + Double(i) * 2.3) * (baseIrisRadius * 0.12)
            let x = -baseIrisRadius * 0.6 + Double(i) * (baseIrisRadius * 1.2 / 5.0) + waveX
            
            // Render only if particle is within the circular iris boundary
            if (x*x + y*y) < baseIrisRadius * baseIrisRadius {
                let alpha = sin(t * .pi) * (0.35 + 0.18 * sin(phase * 2.5 + Double(i)))
                let pRadius = 2.0 + 1.2 * sin(phase * 1.5 + Double(i))
                
                let pRect = CGRect(x: x - pRadius, y: y - pRadius, width: pRadius * 2, height: pRadius * 2)
                
                let pColor = i % 2 == 0 ?
                    Color(red: 1.0, green: 0.88, blue: 0.45).opacity(alpha) :
                    Color(red: 1.0, green: 0.65, blue: 0.90).opacity(alpha)
                
                parallaxContext.fill(Path(ellipseIn: pRect), with: .color(pColor))
            }
        }

        // 4. Warm Firefly Glow Around Pupil
        let pupilScale: Double
        switch expression {
        case .surprised: pupilScale = 0.68
        case .sleepy: pupilScale = 0.22
        case .offline: pupilScale = 0.12
        case .cautious: pupilScale = 0.32
        case .happy: pupilScale = 0.48
        case .celebration: pupilScale = 0.50
        case .victory: pupilScale = 0.52
        case .drinking: pupilScale = 0.42
        case .cool: pupilScale = 0.40
        case .cute: pupilScale = 0.56
        case .fear: pupilScale = 0.18
        case .ashamed: pupilScale = 0.30
        case .shy: pupilScale = 0.45
        case .idle, .looking:
            pupilScale = 0.44 + 0.02 * sin(phase * 1.8)
        }
        let pupilRadius = baseIrisRadius * pupilScale

        // Draw soft glow around pupil
        let glowHaloRadius = pupilRadius * (1.28 + 0.08 * sin(phase * 2.5))
        let glowHaloRect = CGRect(x: -glowHaloRadius, y: -glowHaloRadius, width: glowHaloRadius * 2, height: glowHaloRadius * 2)
        let glowHaloGradient = Gradient(colors: [
            Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.35 * breath),
            Color(red: 1.0, green: 0.52, blue: 0.15).opacity(0.0)
        ])
        parallaxContext.fill(
            Path(ellipseIn: glowHaloRect),
            with: .radialGradient(
                glowHaloGradient,
                center: .zero,
                startRadius: pupilRadius * 0.7,
                endRadius: glowHaloRadius
            )
        )

        // Draw Pupil Core (Hand-painted style, slightly organic circle)
        var pupilPath = Path()
        for i in 0..<12 {
            let theta = Double(i) * (2.0 * .pi / 12.0)
            let wave = sin(phase * 2.2 + Double(i) * 1.5) * (pupilRadius * 0.015)
            let r = pupilRadius + wave
            let pt = CGPoint(x: cos(theta) * r, y: sin(theta) * r)
            if i == 0 {
                pupilPath.move(to: pt)
            } else {
                pupilPath.addLine(to: pt)
            }
        }
        pupilPath.closeSubpath()
        parallaxContext.fill(pupilPath, with: .color(Color(white: 0.05)))

        // 5. Draw hand-drawn look glass window reflections
        if expression != .offline && expression != .sleepy {
            drawGhibliGlassHighlight(in: &context, size: size)
        }
    }

    private func drawGhibliGlassHighlight(in context: inout GraphicsContext, size: CGSize) {
        // Two soft-drawn, dreamy highlight blobs positioned like window panes in a Ghibli movie
        let primaryRect = CGRect(
            x: -size.width * 0.26,
            y: -size.height * 0.34,
            width: size.width * 0.28,
            height: size.height * 0.18
        )
        context.fill(
            Path(ellipseIn: primaryRect),
            with: .color(.white.opacity(0.40))
        )

        let secondaryRect = CGRect(
            x: -size.width * 0.10,
            y: -size.height * 0.38,
            width: size.width * 0.12,
            height: size.height * 0.08
        )
        context.fill(
            Path(ellipseIn: secondaryRect),
            with: .color(.white.opacity(0.22))
        )
    }

    private func drawCyberpunkProceduralEye(
        in context: inout GraphicsContext,
        rect: CGRect,
        size: CGSize,
        gazeOffset: CGSize,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        scaleX: Double,
        scaleY: Double
    ) {
        let elapsedSinceChange = phase - expressionChangedAt
        let isGlitching = elapsedSinceChange < 0.16
        
        // High-frequency horizontal digital jitter tremor
        var jitterX = 0.0
        if isGlitching {
            jitterX = sin(phase * 150.0) * 4.5
        }
        
        // Add random high frequency grid-flicker brightness
        let terminalStaticFlicker = 0.85 + 0.15 * sin(phase * 80.0)

        // Soft neon-green breathing aura
        if expression != .offline {
            let glowColor = Color(red: 0.0, green: 1.0, blue: 0.35).opacity((0.35 + breath * 0.15) * terminalStaticFlicker)
            context.addFilter(.shadow(color: glowColor, radius: 18.0 + breath * 8.0))
        }

        if expression == .offline {
            context.opacity = 0.35
        }

        if expression == .happy || expression == .celebration || expression == .victory || expression == .cute {
            // Smiling crescent mask
            var happyClip = Path()
            happyClip.move(to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY))
            happyClip.addQuadCurve(
                to: CGPoint(x: size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.72 * scaleY)
            )
            happyClip.addQuadCurve(
                to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.18 * scaleY)
            )
            context.clip(to: happyClip)
        }

        // Apply horizontal jitter tremor to the drawing context
        var glitchContext = context
        glitchContext.translateBy(x: jitterX, y: 0)

        // We divide the eye bounding box into a 12x12 retro LED block grid
        let cols = 12
        let rows = 12
        let blockW = size.width / Double(cols)
        let blockH = size.height / Double(rows)

        let minDimension = min(size.width, size.height)
        let irisRadius = minDimension * 0.44
        let pupilScale: Double
        switch expression {
        case .surprised: pupilScale = 0.65
        case .sleepy: pupilScale = 0.20
        case .offline: pupilScale = 0.10
        case .cautious: pupilScale = 0.30
        case .happy: pupilScale = 0.45
        case .celebration: pupilScale = 0.48
        case .victory: pupilScale = 0.50
        case .drinking: pupilScale = 0.40
        case .cool: pupilScale = 0.38
        case .cute: pupilScale = 0.52
        case .fear: pupilScale = 0.16
        case .ashamed: pupilScale = 0.28
        case .shy: pupilScale = 0.42
        case .idle, .looking: pupilScale = 0.40
        }
        let pupilRadius = irisRadius * pupilScale

        // Pupil/Iris center shifted by gaze offset (3D Parallax!)
        let pupilCenter = CGPoint(
            x: gazeOffset.width * 0.35,
            y: gazeOffset.height * 0.35
        )

        for r in 0..<rows {
            for c in 0..<cols {
                let bx = -size.width / 2.0 + (Double(c) + 0.5) * blockW
                let by = -size.height / 2.0 + (Double(r) + 0.5) * blockH

                // Check if this grid block is inside the current squashed eyelid ellipse
                let normalizedX = bx / (size.width * 0.5 * scaleX)
                let normalizedY = by / (size.height * 0.5 * scaleY)
                let isInsideEyelids = (normalizedX*normalizedX + normalizedY*normalizedY) <= 1.0

                if isInsideEyelids {
                    let dx = bx - pupilCenter.x
                    let dy = by - pupilCenter.y
                    let dist = sqrt(dx*dx + dy*dy)

                    let inset = 0.8
                    let blockRect = CGRect(
                        x: bx - blockW * 0.5 + inset,
                        y: by - blockH * 0.5 + inset,
                        width: blockW - inset * 2,
                        height: blockH - inset * 2
                    )

                    let blockPath = Path(roundedRect: blockRect, cornerRadius: 1.5)

                    if dist <= pupilRadius {
                        glitchContext.fill(
                            blockPath,
                            with: .color(Color(white: 0.05).opacity(0.85))
                        )
                    } else if dist <= irisRadius {
                        let perPixelFlicker = 0.88 + 0.12 * sin(phase * 40.0 + Double(c) * 1.5 + Double(r))
                        let irisColor = Color(red: 0.0, green: 1.0, blue: 0.3).opacity((0.92 * perPixelFlicker) * terminalStaticFlicker)
                        glitchContext.fill(blockPath, with: .color(irisColor))
                    } else {
                        let scanlineRowGlow = 0.06 + 0.04 * sin(phase * 8.0 + Double(r) * 0.8)
                        glitchContext.fill(
                            blockPath,
                            with: .color(Color(red: 0.0, green: 0.25, blue: 0.08).opacity(scanlineRowGlow))
                        )
                    }
                }
            }
        }
    }

    private func drawAuroraProceduralEye(
        in context: inout GraphicsContext,
        rect: CGRect,
        size: CGSize,
        gazeOffset: CGSize,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        scaleX: Double,
        scaleY: Double
    ) {
        if expression != .offline {
            let glowColor = Color(red: 0.15, green: 0.85, blue: 1.0).opacity(0.35 + breath * 0.15)
            context.addFilter(.shadow(color: glowColor, radius: 20.0 + breath * 8.0))
        }

        if expression == .offline {
            context.opacity = 0.35
        }

        if expression == .happy || expression == .celebration || expression == .victory || expression == .cute {
            var happyClip = Path()
            happyClip.move(to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY))
            happyClip.addQuadCurve(
                to: CGPoint(x: size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.72 * scaleY)
            )
            happyClip.addQuadCurve(
                to: CGPoint(x: -size.width * 0.55 * scaleX, y: size.height * 0.22 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.18 * scaleY)
            )
            context.clip(to: happyClip)
        }

        context.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.04)))

        var parallaxContext = context
        parallaxContext.translateBy(x: gazeOffset.width * 0.35, y: gazeOffset.height * 0.35)

        let minDimension = min(size.width, size.height)
        let irisRadius = minDimension * 0.44
        let irisRect = CGRect(x: -irisRadius, y: -irisRadius, width: irisRadius * 2, height: irisRadius * 2)

        let gradAngle = phase * 0.9
        let startPoint = CGPoint(x: cos(gradAngle) * irisRadius, y: sin(gradAngle) * irisRadius)
        let endPoint = CGPoint(x: -cos(gradAngle) * irisRadius, y: -sin(gradAngle) * irisRadius)

        let auroraGradient = Gradient(colors: [
            Color(red: 1.0, green: 0.2, blue: 0.85),
            Color(red: 0.5, green: 0.1, blue: 0.95),
            Color(red: 0.15, green: 0.85, blue: 1.0)
        ])

        parallaxContext.fill(
            Path(ellipseIn: irisRect),
            with: .linearGradient(
                auroraGradient,
                startPoint: startPoint,
                endPoint: endPoint
            )
        )

        let pupilScale: Double
        switch expression {
        case .surprised: pupilScale = 0.60
        case .sleepy: pupilScale = 0.18
        case .offline: pupilScale = 0.10
        case .cautious: pupilScale = 0.28
        case .happy: pupilScale = 0.42
        case .celebration: pupilScale = 0.45
        case .victory: pupilScale = 0.48
        case .drinking: pupilScale = 0.38
        case .cool: pupilScale = 0.35
        case .cute: pupilScale = 0.50
        case .fear: pupilScale = 0.15
        case .ashamed: pupilScale = 0.25
        case .shy: pupilScale = 0.40
        case .idle, .looking: pupilScale = 0.35
        }
        let pupilRadius = irisRadius * pupilScale

        for i in 0..<3 {
            let progress = (phase * 0.33 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
            let ringR = pupilRadius + progress * (irisRadius - pupilRadius)
            let opacity = (1.0 - progress) * 0.72
            let ringRect = CGRect(x: -ringR, y: -ringR, width: ringR * 2, height: ringR * 2)
            
            parallaxContext.stroke(
                Path(ellipseIn: ringRect),
                with: .color(Color(red: 0.15, green: 0.85, blue: 1.0).opacity(opacity)),
                style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
            )
        }

        let pupilRect = CGRect(x: -pupilRadius, y: -pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2)
        parallaxContext.fill(Path(ellipseIn: pupilRect), with: .color(Color(white: 0.05)))

        let coreHighlight = CGRect(
            x: -pupilRadius * 0.15,
            y: -pupilRadius * 0.15,
            width: pupilRadius * 0.30,
            height: pupilRadius * 0.30
        )
        parallaxContext.fill(Path(ellipseIn: coreHighlight), with: .color(.white.opacity(0.85)))

        if expression != .offline && expression != .sleepy {
            drawGlassHighlight(in: &context, size: size, theme: .holographicAurora)
        }
    }

    private func drawMinimalistProceduralEye(
        in context: inout GraphicsContext,
        rect: CGRect,
        size: CGSize,
        gazeOffset: CGSize,
        color: Color,
        breath: Double,
        phase: Double,
        expression: FaceExpression,
        scaleX: Double,
        scaleY: Double
    ) {
        if expression == .offline {
            context.opacity = 0.35
        }

        if expression == .happy || expression == .celebration || expression == .victory || expression == .cute {
            var arc = Path()
            arc.move(to: CGPoint(x: -size.width * 0.52 * scaleX, y: size.height * 0.12 * scaleY))
            arc.addQuadCurve(
                to: CGPoint(x: size.width * 0.52 * scaleX, y: size.height * 0.12 * scaleY),
                control: CGPoint(x: 0, y: -size.height * 0.68 * scaleY)
            )
            
            let strokeWidth = size.height * 0.24
            let strokeColor = Color.white
            
            var happyEyeContext = context
            happyEyeContext.translateBy(x: gazeOffset.width * 0.3, y: gazeOffset.height * 0.3)
            
            happyEyeContext.stroke(
                arc,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
        } else {
            let shape = Path(ellipseIn: rect)
            
            context.stroke(
                shape,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )
            
            let pupilLineY = -size.height * 0.1 + gazeOffset.height * 0.3
            var pupilPath = Path()
            pupilPath.move(to: CGPoint(x: -size.width * 0.25 + gazeOffset.width * 0.3, y: pupilLineY))
            pupilPath.addLine(to: CGPoint(x: size.width * 0.25 + gazeOffset.width * 0.3, y: pupilLineY))
            context.stroke(
                pupilPath,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
        }
    }

    private func drawGlassHighlight(in context: inout GraphicsContext, size: CGSize, theme: FaceTheme) {
        // Draw a gorgeous, glossy glass glare reflection that stays perfectly still on the eyeball's spherical surface.
        // As the inner pupil slides around, this glare stays pinned to the top-left, making the eye look wet, shiny, and spherical!
        
        let highlightWidth = size.width * 0.32
        let highlightHeight = size.height * 0.20
        let highlightRect = CGRect(
            x: -size.width * 0.25,
            y: -size.height * 0.35,
            width: highlightWidth,
            height: highlightHeight
        )
        
        let highlightPath = Path(ellipseIn: highlightRect)
        
        // Slightly change highlight opacity/style based on theme for maximum matching aesthetic
        let opacityMax: Double
        let opacityMin: Double
        switch theme {
        case .classicWallE:
            opacityMax = 0.55
            opacityMin = 0.05
        case .nebulaCosmic:
            opacityMax = 0.45 // softer highlight for Ghibli hand-painted style
            opacityMin = 0.02
        case .cyberpunkMatrix:
            opacityMax = 0.60 // crisp glow highlight for neon matrix
            opacityMin = 0.10
        default:
            opacityMax = 0.45
            opacityMin = 0.05
        }
        
        context.fill(
            highlightPath,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(opacityMax), .white.opacity(opacityMin)]),
                startPoint: CGPoint(x: highlightRect.midX, y: highlightRect.minY),
                endPoint: CGPoint(x: highlightRect.midX, y: highlightRect.maxY)
            )
        )
        
        // Add a secondary subtle pin-point reflection dot on the opposite side to make the glass sphere feel incredibly real
        let dotSize = size.width * 0.06
        let dotRect = CGRect(
            x: size.width * 0.18,
            y: size.height * 0.18,
            width: dotSize,
            height: dotSize
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(opacityMax * 0.4)))
    }

    private func drawEyebrow(
        in context: inout GraphicsContext,
        eyeCenter: CGPoint,
        eyeSize: CGSize,
        angle: Double,
        offset: Double,
        side: EyeSide,
        theme: FaceTheme
    ) {
        guard angle != 0.0 || offset != 0.0 else { return }

        var browContext = context
        // Position eyebrow relative to eye center
        browContext.translateBy(x: eyeCenter.x, y: eyeCenter.y - eyeSize.height * 0.95 - offset)
        browContext.rotate(by: Angle(radians: angle))

        let browWidth = eyeSize.width * 0.72
        var brow = Path()
        brow.move(to: CGPoint(x: -browWidth / 2, y: 0))
        brow.addLine(to: CGPoint(x: browWidth / 2, y: 0))

        let color: Color
        switch theme {
        case .classicWallE:
            color = .white.opacity(0.55)
        case .cyberpunkMatrix:
            color = Color(red: 0.0, green: 1.0, blue: 0.25).opacity(0.65)
        case .nebulaCosmic:
            color = Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.65)
        case .holographicAurora:
            color = Color(red: 0.15, green: 0.85, blue: 1.0).opacity(0.7)
        case .minimalistIron:
            color = .white.opacity(0.8)
        }

        let lineWidth = theme == .minimalistIron ? 2.5 : 4.0

        browContext.stroke(
            brow,
            with: .color(color),
            style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round)
        )
    }

    private func drawExpressionDetails(in context: inout GraphicsContext, size: CGSize, phase: Double, theme: FaceTheme) {
        switch model.expression {
        case .happy:
            drawSmile(in: &context, size: size, happy: true, phase: phase, theme: theme)
            drawCheekBlushes(in: &context, size: size, phase: phase)
            
        case .looking:
            drawSmile(in: &context, size: size, happy: false, phase: phase, theme: theme)
            
        case .surprised:
            drawTinyMouth(in: &context, size: size, phase: phase, theme: theme)
            
        case .celebration:
            drawSmile(in: &context, size: size, happy: true, phase: phase, theme: theme)
            drawCheekBlushes(in: &context, size: size, phase: phase)
            drawCelebrationSparkles(in: &context, size: size, phase: phase)
            
        case .victory:
            drawSmile(in: &context, size: size, happy: true, phase: phase, theme: theme)
            drawVictoryCrown(in: &context, size: size, phase: phase)
            
        case .drinking:
            drawSmile(in: &context, size: size, happy: true, phase: phase, theme: theme)
            drawWineGlass(in: &context, size: size, phase: phase)
            
        case .cool:
            drawSmile(in: &context, size: size, happy: false, phase: phase, theme: theme)
            drawCoolSunglasses(in: &context, size: size, phase: phase)
            
        case .cute:
            drawSmile(in: &context, size: size, happy: true, phase: phase, theme: theme)
            drawCheekBlushes(in: &context, size: size, phase: phase)
            drawFloatingHearts(in: &context, size: size, phase: phase)
            
        case .fear:
            drawTinyMouth(in: &context, size: size, phase: phase, theme: theme)
            drawSweatDrop(in: &context, size: size, phase: phase)
            
        case .ashamed:
            drawSmile(in: &context, size: size, happy: false, sad: true, phase: phase, theme: theme)
            drawSweatDrop(in: &context, size: size, phase: phase)
            
        case .shy:
            drawSmile(in: &context, size: size, happy: false, phase: phase, theme: theme)
            drawCheekBlushes(in: &context, size: size, phase: phase)
            
        default:
            break
        }
    }

    private func drawSmile(in context: inout GraphicsContext, size: CGSize, happy: Bool, sad: Bool = false, phase: Double, theme: FaceTheme) {
        var smile = Path()
        let breathOffset = sin(phase * 1.5) * 1.5
        
        let startY = size.height * 0.65 + breathOffset
        smile.move(to: CGPoint(x: size.width * 0.42, y: startY))
        
        let controlY: Double
        if sad {
            controlY = size.height * 0.59 + breathOffset
        } else {
            controlY = size.height * (happy ? 0.71 : 0.68) + breathOffset
        }
        smile.addQuadCurve(
            to: CGPoint(x: size.width * 0.58, y: startY),
            control: CGPoint(x: size.width * 0.5, y: controlY)
        )
        
        let smileColor: Color
        switch theme {
        case .classicWallE:
            smileColor = .white.opacity((happy || sad) ? 0.84 : 0.42)
        case .cyberpunkMatrix:
            smileColor = Color(red: 0.0, green: 1.0, blue: 0.25).opacity((happy || sad) ? 0.9 : 0.45)
        case .nebulaCosmic:
            smileColor = Color(red: 0.35, green: 0.85, blue: 1.0).opacity((happy || sad) ? 0.9 : 0.45)
        case .holographicAurora:
            smileColor = Color(red: 0.15, green: 0.85, blue: 1.0).opacity((happy || sad) ? 0.92 : 0.46)
        case .minimalistIron:
            smileColor = .white.opacity((happy || sad) ? 0.85 : 0.4)
        }
        
        let lineWidth = theme == .minimalistIron ? max(2.2, size.height * 0.005) : max(3, size.height * 0.007)

        context.stroke(
            smile,
            with: .color(smileColor),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }

    private func drawTinyMouth(in context: inout GraphicsContext, size: CGSize, phase: Double, theme: FaceTheme) {
        let mouthPulse = sin(phase * 12.0) * 1.2
        let mouthSize = min(size.width, size.height) * 0.052 + mouthPulse
        let rect = CGRect(
            x: size.width * 0.5 - mouthSize / 2,
            y: size.height * 0.64 - mouthSize / 2,
            width: mouthSize,
            height: mouthSize
        )
        
        let color: Color
        switch theme {
        case .classicWallE:
            color = .white.opacity(0.58)
        case .cyberpunkMatrix:
            color = Color(red: 0.0, green: 1.0, blue: 0.25).opacity(0.68)
        case .nebulaCosmic:
            color = Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.68)
        case .holographicAurora:
            color = Color(red: 0.15, green: 0.85, blue: 1.0).opacity(0.7)
        case .minimalistIron:
            color = .white.opacity(0.7)
        }
        
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: theme == .minimalistIron ? 2 : 3)
    }

    private func drawCheekBlushes(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let eyeSpacing = shortestSide * 0.32
        let blushY = faceCenter.y + shortestSide * 0.08
        let blushW = shortestSide * 0.08
        let blushH = shortestSide * 0.04
        
        let blushOpacity = 0.55 + 0.15 * sin(phase * 4.0)
        
        for sideSign in [-1.0, 1.0] {
            let blushCenter = CGPoint(x: faceCenter.x + sideSign * eyeSpacing, y: blushY)
            let rect = CGRect(
                x: blushCenter.x - blushW * 0.5,
                y: blushCenter.y - blushH * 0.5,
                width: blushW,
                height: blushH
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.pink.opacity(blushOpacity))
            )
        }
    }

    private func drawCoolSunglasses(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let eyeSpacing = shortestSide * 0.32
        let eyeY = faceCenter.y - shortestSide * 0.04
        
        let glassW = shortestSide * 0.28
        let glassH = shortestSide * 0.09
        
        for sideSign in [-1.0, 1.0] {
            let lensCenter = CGPoint(x: faceCenter.x + sideSign * eyeSpacing, y: eyeY)
            
            var lensPath = Path()
            lensPath.move(to: CGPoint(x: lensCenter.x - glassW * 0.5, y: lensCenter.y - glassH * 0.4))
            lensPath.addLine(to: CGPoint(x: lensCenter.x + glassW * 0.5, y: lensCenter.y - glassH * 0.5))
            lensPath.addLine(to: CGPoint(x: lensCenter.x + glassW * 0.4, y: lensCenter.y + glassH * 0.5))
            lensPath.addLine(to: CGPoint(x: lensCenter.x - glassW * 0.4, y: lensCenter.y + glassH * 0.3))
            lensPath.closeSubpath()
            
            context.fill(lensPath, with: .color(Color.black.opacity(0.92)))
            context.stroke(lensPath, with: .color(Color.white.opacity(0.8)), lineWidth: 2)
            
            var glarePath = Path()
            glarePath.move(to: CGPoint(x: lensCenter.x - glassW * 0.3, y: lensCenter.y - glassH * 0.3))
            glarePath.addLine(to: CGPoint(x: lensCenter.x - glassW * 0.1, y: lensCenter.y - glassH * 0.35))
            glarePath.addLine(to: CGPoint(x: lensCenter.x - glassW * 0.25, y: lensCenter.y + glassH * 0.2))
            glarePath.addLine(to: CGPoint(x: lensCenter.x - glassW * 0.4, y: lensCenter.y + glassH * 0.15))
            glarePath.closeSubpath()
            context.fill(glarePath, with: .color(Color.white.opacity(0.5)))
        }
        
        var bridge = Path()
        bridge.move(to: CGPoint(x: faceCenter.x - eyeSpacing + glassW * 0.3, y: eyeY - glassH * 0.3))
        bridge.addLine(to: CGPoint(x: faceCenter.x + eyeSpacing - glassW * 0.3, y: eyeY - glassH * 0.3))
        context.stroke(bridge, with: .color(Color.white.opacity(0.85)), lineWidth: 3)
    }

    private func drawFloatingHearts(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        
        for i in 0..<3 {
            let hPhase = phase * 2.0 + Double(i) * 1.5
            let progress = hPhase.truncatingRemainder(dividingBy: 3.0) / 3.0
            
            let scale = 0.5 + (1.0 - progress) * 0.6
            let opacity = sin(progress * .pi) * 0.85
            
            let heartY = faceCenter.y - shortestSide * 0.18 - progress * shortestSide * 0.25
            let swayX = sin(hPhase * 1.5) * shortestSide * 0.08
            let heartX = faceCenter.x + swayX + Double(i - 1) * shortestSide * 0.15
            
            var heartCtx = context
            heartCtx.translateBy(x: heartX, y: heartY)
            heartCtx.scaleBy(x: scale, y: scale)
            
            let heartSize = shortestSide * 0.045
            
            var heart = Path()
            heart.move(to: CGPoint(x: 0, y: heartSize * 0.45))
            heart.addCurve(to: CGPoint(x: 0, y: -heartSize * 0.25),
                           control1: CGPoint(x: -heartSize * 0.7, y: -heartSize * 0.25),
                           control2: CGPoint(x: -heartSize * 0.35, y: -heartSize * 0.75))
            heart.addCurve(to: CGPoint(x: 0, y: heartSize * 0.45),
                           control1: CGPoint(x: heartSize * 0.35, y: -heartSize * 0.75),
                           control2: CGPoint(x: heartSize * 0.7, y: -heartSize * 0.25))
            
            heartCtx.fill(heart, with: .color(Color.pink.opacity(opacity)))
        }
    }

    private func drawCelebrationSparkles(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        
        let sparkleOffsets = [
            CGPoint(x: -shortestSide * 0.4, y: -shortestSide * 0.2),
            CGPoint(x: shortestSide * 0.4, y: -shortestSide * 0.25),
            CGPoint(x: -shortestSide * 0.38, y: shortestSide * 0.15),
            CGPoint(x: shortestSide * 0.38, y: shortestSide * 0.1)
        ]
        
        for (index, offset) in sparkleOffsets.enumerated() {
            let sPhase = phase * 3.5 + Double(index) * 1.5
            let scale = 0.4 + abs(sin(sPhase)) * 0.6
            let opacity = 0.3 + abs(sin(sPhase)) * 0.7
            
            var sCtx = context
            sCtx.translateBy(x: faceCenter.x + offset.x, y: faceCenter.y + offset.y)
            sCtx.scaleBy(x: scale, y: scale)
            
            let r = shortestSide * 0.04
            
            var star = Path()
            star.move(to: CGPoint(x: 0, y: -r))
            star.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: r), control: .zero)
            star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: .zero)
            
            let color = index % 2 == 0 ? Color.yellow : Color.orange
            sCtx.fill(star, with: .color(color.opacity(opacity)))
        }
    }

    private func drawVictoryCrown(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        
        let crownY = faceCenter.y - shortestSide * 0.22 + sin(phase * 4.0) * 4.0
        let crownW = shortestSide * 0.18
        let crownH = shortestSide * 0.09
        
        var crownCtx = context
        crownCtx.translateBy(x: faceCenter.x, y: crownY)
        
        var crownPath = Path()
        crownPath.move(to: CGPoint(x: -crownW * 0.5, y: crownH * 0.4))
        crownPath.addLine(to: CGPoint(x: -crownW * 0.5, y: -crownH * 0.2))
        crownPath.addQuadCurve(to: CGPoint(x: -crownW * 0.25, y: crownH * 0.1), control: CGPoint(x: -crownW * 0.37, y: crownH * 0.2))
        crownPath.addLine(to: CGPoint(x: 0, y: -crownH * 0.5))
        crownPath.addLine(to: CGPoint(x: crownW * 0.25, y: crownH * 0.1))
        crownPath.addQuadCurve(to: CGPoint(x: crownW * 0.5, y: -crownH * 0.2), control: CGPoint(x: crownW * 0.37, y: crownH * 0.2))
        crownPath.addLine(to: CGPoint(x: crownW * 0.5, y: crownH * 0.4))
        crownPath.addLine(to: CGPoint(x: -crownW * 0.5, y: crownH * 0.4))
        crownPath.closeSubpath()
        
        let bandRect = CGRect(x: -crownW * 0.5, y: crownH * 0.4, width: crownW, height: crownH * 0.15)
        
        crownCtx.fill(crownPath, with: .color(.yellow))
        crownCtx.stroke(crownPath, with: .color(Color.orange), lineWidth: 1.5)
        
        crownCtx.fill(Path(bandRect), with: .color(Color.orange))
        
        let jewelRadius = crownW * 0.05
        let peaks = [
            CGPoint(x: -crownW * 0.5, y: -crownH * 0.25),
            CGPoint(x: 0, y: -crownH * 0.55),
            CGPoint(x: crownW * 0.5, y: -crownH * 0.25)
        ]
        for peak in peaks {
            let jewelRect = CGRect(x: peak.x - jewelRadius, y: peak.y - jewelRadius, width: jewelRadius * 2, height: jewelRadius * 2)
            crownCtx.fill(Path(ellipseIn: jewelRect), with: .color(.red))
        }
    }

    private func drawWineGlass(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        
        let glassX = faceCenter.x + shortestSide * 0.35
        let glassY = faceCenter.y + shortestSide * 0.15
        
        let glassTilt = sin(phase * 2.5) * 0.25
        
        var glassCtx = context
        glassCtx.translateBy(x: glassX, y: glassY)
        glassCtx.rotate(by: Angle(radians: glassTilt))
        
        let w = shortestSide * 0.07
        let h = shortestSide * 0.10
        
        var bowl = Path()
        bowl.move(to: CGPoint(x: -w, y: -h * 0.4))
        bowl.addQuadCurve(to: CGPoint(x: 0, y: h * 0.1), control: CGPoint(x: -w, y: h * 0.1))
        bowl.addQuadCurve(to: CGPoint(x: w, y: -h * 0.4), control: CGPoint(x: w, y: h * 0.1))
        
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: h * 0.1))
        stem.addLine(to: CGPoint(x: 0, y: h * 0.4))
        
        var base = Path()
        base.move(to: CGPoint(x: -w * 0.6, y: h * 0.4))
        base.addLine(to: CGPoint(x: w * 0.6, y: h * 0.4))
        
        let liquidLevel = -h * 0.15
        let gravitySlope = -glassTilt * 0.55
        
        var liquidPath = Path()
        liquidPath.move(to: CGPoint(x: -w * 0.85, y: liquidLevel + gravitySlope * w * 0.85))
        liquidPath.addQuadCurve(to: CGPoint(x: 0, y: h * 0.1), control: CGPoint(x: -w * 0.8, y: h * 0.1))
        liquidPath.addQuadCurve(to: CGPoint(x: w * 0.85, y: liquidLevel - gravitySlope * w * 0.85), control: CGPoint(x: w * 0.8, y: h * 0.1))
        liquidPath.closeSubpath()
        
        glassCtx.fill(liquidPath, with: .color(Color(red: 0.9, green: 0.1, blue: 0.25).opacity(0.85)))
        
        let bubbleCount = 4
        for i in 0..<bubbleCount {
            let bPhase = phase * 4.0 + Double(i) * 2.0
            let bProg = bPhase.truncatingRemainder(dividingBy: 1.0)
            let bx = -w * 0.5 + Double(i) * (w * 0.3)
            let by = h * 0.05 - bProg * (h * 0.15)
            let bRadius = 1.0 + bProg * 2.0
            
            let bubbleRect = CGRect(x: bx - bRadius, y: by - bRadius, width: bRadius * 2, height: bRadius * 2)
            glassCtx.fill(Path(ellipseIn: bubbleRect), with: .color(.white.opacity(0.6)))
        }
        
        glassCtx.stroke(bowl, with: .color(.white.opacity(0.72)), lineWidth: 2)
        glassCtx.stroke(stem, with: .color(.white.opacity(0.72)), lineWidth: 2.5)
        glassCtx.stroke(base, with: .color(.white.opacity(0.72)), lineWidth: 2.5)
    }

    private func drawSweatDrop(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let eyeSpacing = shortestSide * 0.32
        let eyeY = faceCenter.y - shortestSide * 0.04
        
        let dripX = faceCenter.x - eyeSpacing - shortestSide * 0.14
        let dripStartVal = eyeY - shortestSide * 0.12
        let dripRange = shortestSide * 0.18
        
        let prog = (phase * 1.5).truncatingRemainder(dividingBy: 1.0)
        let dripY = dripStartVal + prog * dripRange
        
        let scale = 0.5 + sin(prog * .pi) * 0.5
        let opacity = sin(prog * .pi) * 0.85
        
        var dripCtx = context
        dripCtx.translateBy(x: dripX, y: dripY)
        dripCtx.scaleBy(x: scale, y: scale)
        
        let dropW = shortestSide * 0.02
        let dropH = shortestSide * 0.035
        
        var dropPath = Path()
        dropPath.move(to: CGPoint(x: 0, y: -dropH * 0.5))
        dropPath.addCurve(
            to: CGPoint(x: 0, y: dropH * 0.5),
            control1: CGPoint(x: -dropW * 0.8, y: -dropH * 0.1),
            control2: CGPoint(x: -dropW * 0.8, y: dropH * 0.5)
        )
        dropPath.addCurve(
            to: CGPoint(x: 0, y: -dropH * 0.5),
            control1: CGPoint(x: dropW * 0.8, y: dropH * 0.5),
            control2: CGPoint(x: dropW * 0.8, y: -dropH * 0.1)
        )
        dropPath.closeSubpath()
        
        dripCtx.fill(dropPath, with: .color(Color(red: 0.15, green: 0.85, blue: 1.0).opacity(opacity)))
        dripCtx.stroke(dropPath, with: .color(.white.opacity(0.8 * opacity)), lineWidth: 1.0)
    }

    private func stageBackground(breath: Double, phase: Double, theme: FaceTheme, baseGlow: Color) -> some View {
        ZStack {
            // Absolute pure black base to turn off OLED pixels completely at the edges
            Color.black
            
            switch theme {
            case .classicWallE:
                RadialGradient(
                    colors: [baseGlow.opacity(0.38 + breath * 0.20), .black],
                    center: .center,
                    startRadius: 10,
                    endRadius: 500
                )
            case .cyberpunkMatrix:
                RadialGradient(
                    colors: [Color(red: 0.0, green: 0.25, blue: 0.05).opacity(0.18 + breath * 0.12), .black],
                    center: .center,
                    startRadius: 20,
                    endRadius: 520
                )
            case .nebulaCosmic:
                RadialGradient(
                    colors: [
                        Color(red: 0.18, green: 0.02, blue: 0.35).opacity(0.32 + breath * 0.18),
                        Color(red: 0.04, green: 0.0, blue: 0.12).opacity(0.7),
                        .black
                    ],
                    center: .center,
                    startRadius: 5,
                    endRadius: 580
                )
            case .holographicAurora:
                let xOffset = sin(phase * 0.45) * 0.15
                let yOffset = cos(phase * 0.35) * 0.15
                RadialGradient(
                    colors: [
                        Color(red: 0.45, green: 0.05, blue: 0.38).opacity(0.24 + breath * 0.14),
                        Color(red: 0.02, green: 0.25, blue: 0.32).opacity(0.18 + breath * 0.12),
                        .black
                    ],
                    center: UnitPoint(x: 0.5 + xOffset, y: 0.5 + yOffset),
                    startRadius: 10,
                    endRadius: 540
                )
            case .minimalistIron:
                // Pure black flat backdrop for titanium minimal look
                Color.black
            }
        }
    }

    private func breathingValue(_ phase: TimeInterval) -> Double {
        (sin(phase * 1.6) + 1) / 2
    }

    private func scanningValue(_ phase: TimeInterval) -> Double {
        (sin(phase * 0.82) + 1) / 2
    }

    private func gazeOffset(_ gaze: FaceGaze, size: CGSize) -> CGSize {
        let shortestSide = min(size.width, size.height)
        let horizontal = shortestSide * 0.045
        let vertical = shortestSide * 0.034

        switch gaze {
        case .center:
            return .zero
        case .left:
            return CGSize(width: -horizontal, height: 0)
        case .right:
            return CGSize(width: horizontal, height: 0)
        case .up:
            return CGSize(width: 0, height: -vertical)
        case .down:
            return CGSize(width: 0, height: vertical)
        }
    }
}

#Preview {
    GeometricFaceView(
        model: FaceModel(expression: .happy, gaze: .center, glow: .yellow.opacity(0.7), line: "小身体已就位。")
    )
}
