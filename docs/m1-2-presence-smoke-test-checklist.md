# M1.2 Presence Slice Smoke Test Checklist

## Simulator

- [ ] Fresh install starts in onboarding when no pairing is stored.
- [ ] Tap "寻找附近的 Looi" starts scan and completes onboarding state.
- [ ] Portrait layout shows Standalone App Mode.
- [ ] Landscape layout with a ready session shows Looi Face Mode.
- [ ] Settings opens from both standalone and face modes.
- [ ] Settings -> Developer opens the existing DevTools tabs.

## Real Looi

- [ ] Pair/connect reaches `LooiSession.state == .ready`.
- [ ] Landscape shows large face, connected pill, and three actions.
- [ ] Touching Looi changes face line/expression and does not require DevTools.
- [ ] Wave runs head/light/motion then returns motion to stop.
- [ ] Look at me centers head and sets warm light.
- [ ] Sleep centers head, stops motion, and turns light off.
- [ ] Lifting the front makes motion unsafe and shows cautious safety copy.
- [ ] Walking away or disconnecting leaves a coherent Standalone App Mode.
