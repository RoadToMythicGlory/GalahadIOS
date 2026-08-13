import SwiftUI

struct RootView: View {
    init() {
        // Themed tab bar: dark card background, muted unselected items.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.tertiaryText)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.tertiaryText)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
            LiveView()
                .tabItem { Label("Live", systemImage: "bolt.fill") }
            DiagnosticsView()
                .tabItem { Label("Health", systemImage: "waveform.path.ecg") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
