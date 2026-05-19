enum FaceAssetCatalog {
    static let idle = "face_idle"
    static let happy = "face_happy"
    static let sleepy = "face_sleepy"
    static let cautious = "face_cautious"
    static let offline = "face_offline"
    static let blink = "face_blink"

    static func primaryAssetName(for expression: FaceExpression) -> String {
        switch expression {
        case .idle, .looking:
            return idle
        case .happy, .surprised:
            return happy
        case .sleepy:
            return sleepy
        case .cautious:
            return cautious
        case .offline:
            return offline
        }
    }
}
