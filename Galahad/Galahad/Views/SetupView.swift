import MediaCore
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display name", text: $model.config.displayName)
                    LabeledContent("Player ID", value: model.config.playerId)
                }
                Section("Destination (SRT caller)") {
                    TextField("Host", text: $model.config.destinationHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $model.config.destinationPort, format: .number)
                    Picker("Latency", selection: $model.config.latencyMs) {
                        Text("200 ms").tag(UInt32(200))
                        Text("400 ms").tag(UInt32(400))
                    }
                }
                Section("Source") {
                    Picker("Video source", selection: $model.config.videoSource) {
                        Text("Front camera").tag(VideoSource.frontCamera)
                        Text("Rear camera").tag(VideoSource.rearCamera)
                        Text("Screen").tag(VideoSource.screen)
                    }
                }
                Section("Quality (H.265)") {
                    Picker("Preset", selection: $model.config.presetId) {
                        ForEach(model.selectablePresets) { item in
                            let base = "\(item.preset.label) · \(item.preset.hevcKbps) kbps"
                            Text(item.isProductionStartable ? base : "\(base) (lab)")
                                .tag(item.preset.id)
                        }
                    }
                }
                Section("Audio") {
                    ForEach($model.config.audio.sources) { $channel in
                        Toggle(channel.label ?? channel.id, isOn: $channel.enabled)
                        if channel.enabled {
                            Toggle("Muted", isOn: $channel.muted)
                            Slider(value: $channel.gain, in: 0...2)
                        }
                    }
                }
                Section("Control channel") {
                    TextField("WebSocket URL", text: Binding(
                        get: { model.config.controlChannelURL ?? "" },
                        set: { model.config.controlChannelURL = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                Button("Save") {
                    Task { await model.saveConfig() }
                }
            }
            .navigationTitle("Setup")
        }
    }
}
