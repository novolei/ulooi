import SwiftUI
import LooiKit

enum FaceTheme: String, CaseIterable, Identifiable {
    case classicWallE = "Classic WALL-E"
    case cyberpunkMatrix = "Cyberpunk Matrix"
    case nebulaCosmic = "Nebula Cosmic"
    case minimalistIron = "Minimalist Iron"
    case holographicAurora = "Holographic Aurora"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        self.rawValue
    }
    
    var description: String {
        switch self {
        case .classicWallE: return "Cinematic 3D glass camera lenses with deep metallic reflections and glossy copper finishes."
        case .cyberpunkMatrix: return "Retro 8-bit arcade pixelated lenses glowing with high-contrast neon matrix grids."
        case .nebulaCosmic: return "Nostalgic Studio Ghibli watercolor eyes with glowing warm cores on drifting stardust."
        case .minimalistIron: return "Clean white vector lines, zero glow, and pure high-contrast elegance."
        case .holographicAurora: return "Iridescent shifting magenta-teal waves with shimmering concentric aura rings."
        }
    }
    
    var previewColors: [Color] {
        switch self {
        case .classicWallE: return [Color.orange, Color.yellow]
        case .cyberpunkMatrix: return [Color(red: 0.0, green: 1.0, blue: 0.4), Color(red: 0.0, green: 0.2, blue: 0.1)]
        case .nebulaCosmic: return [Color(red: 0.85, green: 0.4, blue: 1.0), Color(red: 0.35, green: 0.85, blue: 1.0)]
        case .minimalistIron: return [.white, .gray]
        case .holographicAurora: return [Color(red: 1.0, green: 0.35, blue: 0.85), Color(red: 0.15, green: 0.85, blue: 1.0)]
        }
    }
}

enum FaceExpression: Equatable {
    case idle
    case happy
    case surprised
    case sleepy
    case cautious
    case looking
    case offline
    
    // New expanded expressions
    case celebration
    case victory
    case drinking
    case cool
    case cute
    case fear
    case ashamed
    case shy
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

    static func overrideDynamics(for expression: FaceExpression) -> (Color, String) {
        switch expression {
        case .idle: return (.yellow.opacity(0.96), "我在。电量也还体面。")
        case .happy: return (.yellow, "小身体已就位。")
        case .surprised: return (.mint.opacity(0.95), "欸，我醒着呢。")
        case .sleepy: return (.blue.opacity(0.45), "我先眯一下，有事轻轻叫我。")
        case .cautious: return (.pink.opacity(0.65), "脚下突然很哲学。先别让我开车。")
        case .looking: return (.cyan.opacity(0.65), "小身体在附近吗？")
        case .offline: return (.gray.opacity(0.55), "Looi 不在附近。")
        case .celebration: return (.orange.opacity(0.85), "哇！太棒啦！🎉")
        case .victory: return (.yellow.opacity(0.9), "耶！我们赢了！🏆")
        case .drinking: return (Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.85), "干杯！庆祝一下！🍷")
        case .cool: return (.white.opacity(0.75), "帅气登场，保持低调。😎")
        case .cute: return (Color(red: 1.0, green: 0.55, blue: 0.75).opacity(0.85), "喵呜～给你个小心心❤️")
        case .fear: return (Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.85), "好、好可怕……😨")
        case .ashamed: return (Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.8), "对不起，是我没做好……😓")
        case .shy: return (Color(red: 1.0, green: 0.65, blue: 0.65).opacity(0.85), "被你看着，突然有点害羞呢……")
        }
    }

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
