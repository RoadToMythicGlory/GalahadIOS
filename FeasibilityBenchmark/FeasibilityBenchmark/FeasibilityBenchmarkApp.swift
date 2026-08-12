import SwiftUI
import MediaCore

@main
struct FeasibilityBenchmarkApp: App {
    var body: some Scene {
        WindowGroup {
            BenchmarkRootView()
        }
    }
}

/// Minimal operator UI for Phase 2 only — not the product Galahad shell.
struct BenchmarkRootView: View {
    @StateObject private var model = BenchmarkViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Environment") {
                    LabeledContent("OS", value: model.environment.osName)
                    LabeledContent("Arch", value: model.environment.arch)
                    LabeledContent("Xcode", value: model.environment.hasXcode ? "yes" : "no")
                    LabeledContent("Physical iPhone", value: model.environment.hasPhysicaliPhone ? "yes" : "no")
                    Text(model.environment.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Plugin probe") {
                    LabeledContent("gst_init", value: model.pluginOK ? "ok" : "unavailable")
                    Text(model.pluginDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Gate profiles") {
                    ForEach(VideoProfile.gateCandidates) { profile in
                        LabeledContent(profile.id, value: model.classification(for: profile.id))
                    }
                }

                Section("Actions") {
                    Button("Run harness wiring (stub encoder)") {
                        Task { await model.runStubHarness() }
                    }
                    Button("Export GO/NO-GO JSON") {
                        model.exportReport()
                    }
                    Button("Mark DEVICE VALIDATION REQUIRED") {
                        model.emitDeviceValidationRequired()
                    }
                }

                if let path = model.lastReportPath {
                    Section("Last report") {
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                Section("Log") {
                    Text(model.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Galahad Phase 2 Gate")
            .onAppear { model.bootstrap() }
        }
    }
}
