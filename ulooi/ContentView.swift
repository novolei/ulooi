import SwiftUI

// M0.5 — root is the DevTools probe surface.
// M1 will demote this to Settings → Developer; production UI takes over here.

struct ContentView: View {
    var body: some View {
        DevToolsRootView()
    }
}

#Preview {
    ContentView()
}
