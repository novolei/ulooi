# M1.2 Presence Slice Smoke Test Checklist

## Simulator

- [ ] Fresh install starts in onboarding when no pairing is stored.
- [ ] Tap "Find Looi" starts scan without blocking the UI.
- [ ] Tap "Use phone mode" exits onboarding into Standalone App Mode.
- [ ] Settings opens from onboarding and standalone mode.
- [ ] Settings -> Developer opens the existing DevTools tabs.
- [ ] DevTools can be closed with the visible Done button.
- [ ] Face Mode visual layout is inspected with the `EmbodiedHomeView` / `GeometricFaceView` SwiftUI previews; simulator runtime cannot enter true Face Mode without a ready Looi session.

## Real Looi

- [ ] Pair/connect reaches `LooiSession.state == .ready`.
- [ ] Landscape shows large face, connected pill, and three actions.
- [ ] Rotating back to portrait returns to Standalone App Mode.
- [ ] Touching Looi changes face line/expression and does not require DevTools.
- [ ] Wave runs head/light/motion then returns motion to stop.
- [ ] Cancelling or disconnecting during Wave returns motion to stop and attempts to center head with a dim warm light.
- [ ] Look at me centers head and sets warm light.
- [ ] Sleep centers head, stops motion, and turns light off.
- [ ] Lifting the front makes motion unsafe and shows cautious safety copy.
- [ ] Walking away or disconnecting leaves a coherent Standalone App Mode.
