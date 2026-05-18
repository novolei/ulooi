import SwiftUI

struct GeometricFaceView: View {
    let model: FaceModel

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let breath = breathingValue(phase)
            let scan = scanningValue(phase)

            Canvas { context, size in
                drawFace(in: &context, size: size, breath: breath, scan: scan)
            }
            .background(stageBackground(breath: breath))
        }
    }

    private func drawFace(in context: inout GraphicsContext, size: CGSize, breath: Double, scan: Double) {
        let shortestSide = min(size.width, size.height)
        let faceCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let gaze = gazeOffset(model.gaze, size: size)
        let eyeColor = eyeColor(for: model.expression)
        let eyeSize = eyeSize(for: model.expression, size: size)
        let eyeY = faceCenter.y - shortestSide * 0.04 + gaze.height
        let eyeSpacing = shortestSide * 0.32
        let leftEye = CGPoint(x: faceCenter.x - eyeSpacing, y: eyeY)
        let rightEye = CGPoint(x: faceCenter.x + eyeSpacing, y: eyeY)

        drawHalo(in: &context, size: size, center: faceCenter, breath: breath)
        drawScanLine(in: &context, size: size, scan: scan)
        drawSafetyAccent(in: &context, size: size, breath: breath)

        for center in [leftEye, rightEye] {
            drawEye(
                in: &context,
                center: CGPoint(x: center.x + gaze.width, y: center.y),
                size: eyeSize,
                color: eyeColor,
                breath: breath
            )
        }

        drawExpressionDetails(
            in: &context,
            leftEye: CGPoint(x: leftEye.x + gaze.width, y: leftEye.y),
            rightEye: CGPoint(x: rightEye.x + gaze.width, y: rightEye.y),
            eyeSize: eyeSize,
            size: size
        )
    }

    private func drawHalo(in context: inout GraphicsContext, size: CGSize, center: CGPoint, breath: Double) {
        let haloSize = min(size.width, size.height) * (0.86 + breath * 0.06)
        let rect = CGRect(
            x: center.x - haloSize / 2,
            y: center.y - haloSize / 2,
            width: haloSize,
            height: haloSize
        )

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [model.glow.opacity(0.2 + breath * 0.18), .clear]),
                center: center,
                startRadius: 0,
                endRadius: haloSize * 0.52
            )
        )
    }

    private func drawScanLine(in context: inout GraphicsContext, size: CGSize, scan: Double) {
        guard model.expression != .sleepy else { return }

        let y = size.height * (0.26 + scan * 0.36)
        let start = CGPoint(x: size.width * 0.23, y: y)
        let end = CGPoint(x: size.width * 0.77, y: y)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [.clear, model.glow.opacity(0.34), .clear]),
                startPoint: start,
                endPoint: end
            ),
            style: StrokeStyle(lineWidth: max(1, size.height * 0.003), lineCap: .round)
        )
    }

    private func drawSafetyAccent(in context: inout GraphicsContext, size: CGSize, breath: Double) {
        guard model.expression == .cautious || model.expression == .offline else { return }

        let width = min(size.width, size.height) * 0.34
        let rect = CGRect(
            x: size.width * 0.5 - width / 2,
            y: size.height * 0.76,
            width: width,
            height: max(3, size.height * 0.008)
        )

        context.fill(
            Path(roundedRect: rect, cornerRadius: rect.height / 2),
            with: .color(model.glow.opacity(0.36 + breath * 0.24))
        )
    }

    private func drawEye(
        in context: inout GraphicsContext,
        center: CGPoint,
        size: CGSize,
        color: Color,
        breath: Double
    ) {
        let rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let radius = min(size.width, size.height) * 0.5
        let shape = Path(roundedRect: rect, cornerRadius: radius)

        context.addFilter(.shadow(color: color.opacity(0.38 + breath * 0.24), radius: 18 + breath * 10))
        context.fill(shape, with: .color(color.opacity(0.9)))

        let highlight = CGRect(
            x: rect.minX + rect.width * 0.2,
            y: rect.minY + rect.height * 0.18,
            width: rect.width * 0.22,
            height: max(2, rect.height * 0.14)
        )
        context.fill(Path(ellipseIn: highlight), with: .color(.white.opacity(0.28)))
    }

    private func drawExpressionDetails(
        in context: inout GraphicsContext,
        leftEye: CGPoint,
        rightEye: CGPoint,
        eyeSize: CGSize,
        size: CGSize
    ) {
        switch model.expression {
        case .happy, .looking:
            drawSmile(in: &context, size: size, happy: model.expression == .happy)
        case .sleepy:
            drawSleepLids(in: &context, leftEye: leftEye, rightEye: rightEye, eyeSize: eyeSize)
        case .cautious:
            drawBrows(in: &context, leftEye: leftEye, rightEye: rightEye, eyeSize: eyeSize)
        case .surprised:
            drawTinyMouth(in: &context, size: size)
        case .idle, .offline:
            break
        }
    }

    private func drawSmile(in context: inout GraphicsContext, size: CGSize, happy: Bool) {
        var smile = Path()
        smile.move(to: CGPoint(x: size.width * 0.42, y: size.height * 0.65))
        smile.addQuadCurve(
            to: CGPoint(x: size.width * 0.58, y: size.height * 0.65),
            control: CGPoint(x: size.width * 0.5, y: size.height * (happy ? 0.71 : 0.68))
        )
        context.stroke(
            smile,
            with: .color(.white.opacity(happy ? 0.84 : 0.42)),
            style: StrokeStyle(lineWidth: max(3, size.height * 0.007), lineCap: .round)
        )
    }

    private func drawSleepLids(in context: inout GraphicsContext, leftEye: CGPoint, rightEye: CGPoint, eyeSize: CGSize) {
        for center in [leftEye, rightEye] {
            var lid = Path()
            lid.move(to: CGPoint(x: center.x - eyeSize.width * 0.55, y: center.y))
            lid.addQuadCurve(
                to: CGPoint(x: center.x + eyeSize.width * 0.55, y: center.y),
                control: CGPoint(x: center.x, y: center.y + eyeSize.height * 0.7)
            )
            context.stroke(lid, with: .color(.white.opacity(0.42)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private func drawBrows(in context: inout GraphicsContext, leftEye: CGPoint, rightEye: CGPoint, eyeSize: CGSize) {
        let browOffset = eyeSize.height * 0.95
        let browWidth = eyeSize.width * 0.72

        for (center, direction) in [(leftEye, -1.0), (rightEye, 1.0)] {
            var brow = Path()
            brow.move(to: CGPoint(x: center.x - browWidth / 2, y: center.y - browOffset + 8 * direction))
            brow.addLine(to: CGPoint(x: center.x + browWidth / 2, y: center.y - browOffset - 8 * direction))
            context.stroke(brow, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private func drawTinyMouth(in context: inout GraphicsContext, size: CGSize) {
        let mouthSize = min(size.width, size.height) * 0.052
        let rect = CGRect(
            x: size.width * 0.5 - mouthSize / 2,
            y: size.height * 0.64 - mouthSize / 2,
            width: mouthSize,
            height: mouthSize
        )
        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.58)), lineWidth: 3)
    }

    private func stageBackground(breath: Double) -> some View {
        ZStack {
            Color(red: 0.005, green: 0.006, blue: 0.009)
            RadialGradient(
                colors: [model.glow.opacity(0.42 + breath * 0.22), .black.opacity(0.96)],
                center: .center,
                startRadius: 12,
                endRadius: 520
            )
        }
    }

    private func breathingValue(_ phase: TimeInterval) -> Double {
        (sin(phase * 1.6) + 1) / 2
    }

    private func scanningValue(_ phase: TimeInterval) -> Double {
        (sin(phase * 0.82) + 1) / 2
    }

    private func eyeSize(for expression: FaceExpression, size: CGSize) -> CGSize {
        let shortestSide = min(size.width, size.height)
        let width = shortestSide * 0.22

        switch expression {
        case .sleepy:
            return CGSize(width: width * 1.05, height: shortestSide * 0.055)
        case .cautious:
            return CGSize(width: width, height: shortestSide * 0.105)
        case .surprised:
            return CGSize(width: width * 1.03, height: shortestSide * 0.2)
        case .offline:
            return CGSize(width: width * 0.96, height: shortestSide * 0.095)
        case .happy:
            return CGSize(width: width * 1.08, height: shortestSide * 0.155)
        case .looking:
            return CGSize(width: width, height: shortestSide * 0.145)
        case .idle:
            return CGSize(width: width, height: shortestSide * 0.14)
        }
    }

    private func eyeColor(for expression: FaceExpression) -> Color {
        switch expression {
        case .offline:
            return .white.opacity(0.36)
        case .cautious:
            return .pink.opacity(0.92)
        case .sleepy:
            return .cyan.opacity(0.72)
        case .surprised:
            return .mint.opacity(0.95)
        case .looking:
            return .cyan.opacity(0.92)
        case .happy:
            return .yellow
        case .idle:
            return .yellow.opacity(0.96)
        }
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
