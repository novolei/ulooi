import Foundation
import Observation
import LooiKit

enum UlooiSurface: Equatable {
    case onboarding
    case faceMode
    case standalone
    case developer
}

enum UlooiOrientation: Equatable {
    case portrait
    case landscape
}

@MainActor
@Observable
final class ModeController {
    var onboardingComplete: Bool
    var developerOpen = false

    init(onboardingComplete: Bool = UserDefaults.standard.bool(forKey: "ulooi.onboarding.complete")) {
        self.onboardingComplete = onboardingComplete
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "ulooi.onboarding.complete")
    }

    func resetOnboardingForTesting() {
        onboardingComplete = false
        UserDefaults.standard.set(false, forKey: "ulooi.onboarding.complete")
    }

    func surface(session: LooiSession, orientation: UlooiOrientation) -> UlooiSurface {
        if developerOpen { return .developer }
        if !onboardingComplete && session.pairedPeripheralID == nil { return .onboarding }
        if session.state == .ready && orientation == .landscape { return .faceMode }
        return .standalone
    }
}
