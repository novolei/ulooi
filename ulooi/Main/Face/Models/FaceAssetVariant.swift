import Foundation

struct FaceAssetVariant: Equatable, Identifiable {
    enum Transition: Equatable {
        case immediate
        case crossfade(seconds: Double)
    }

    let id: String
    let expression: FaceExpression
    let assetName: String
    let minimumDwell: TimeInterval
    let transition: Transition
    let allowsMicroMotion: Bool
    let priority: Int
}
