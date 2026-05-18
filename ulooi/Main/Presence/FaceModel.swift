import SwiftUI
import LooiKit

enum FaceExpression: Equatable {
    case idle
    case happy
    case surprised
    case sleepy
    case cautious
    case looking
    case offline
}

enum FaceGaze: Equatable {
    case center
    case left
    case right
    case up
    case down
}

struct FaceModel {
    var expression: FaceExpression
    var gaze: FaceGaze
    var glow: Color
    var line: String

    static func from(_ state: PresenceState) -> FaceModel {
        switch state {
        case .booting, .lookingForBody:
            return FaceModel(expression: .looking, gaze: .center, glow: .cyan.opacity(0.65), line: "小身体在附近吗？")
        case .awake, .idle:
            return FaceModel(expression: .idle, gaze: .center, glow: .yellow.opacity(0.62), line: "我在。电量也还体面。")
        case .touched:
            return FaceModel(expression: .surprised, gaze: .up, glow: .mint.opacity(0.75), line: "欸，我醒着呢。")
        case .performingGesture(.wave):
            return FaceModel(expression: .happy, gaze: .center, glow: .orange.opacity(0.7), line: "小身体已就位。")
        case .performingGesture(.lookAtMe):
            return FaceModel(expression: .happy, gaze: .center, glow: .yellow.opacity(0.72), line: "看着你啦。")
        case .performingGesture(.sleep), .sleeping:
            return FaceModel(expression: .sleepy, gaze: .down, glow: .blue.opacity(0.45), line: "我先眯一下，有事轻轻叫我。")
        case .performingGesture:
            return FaceModel(expression: .happy, gaze: .center, glow: .orange.opacity(0.7), line: "小身体已就位。")
        case .suspended:
            return FaceModel(expression: .cautious, gaze: .down, glow: .pink.opacity(0.65), line: "脚下突然很哲学。先别让我开车。")
        case .disconnected:
            return FaceModel(expression: .offline, gaze: .center, glow: .gray.opacity(0.55), line: "Looi 不在附近。")
        case .errorRecoverable(let message):
            return FaceModel(expression: .cautious, gaze: .center, glow: .red.opacity(0.55), line: message)
        }
    }
}
