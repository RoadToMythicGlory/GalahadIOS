import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
            LiveView()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
    }
}
