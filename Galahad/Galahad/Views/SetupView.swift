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
                    // 200-600 suits LAN/metro links; 1000-2500 buys retransmission
                    // headroom for cross-country 5G/4G/LTE (SRT wants ~4x RTT).
                    Picker("Latency", selection: $model.config.latencyMs) {
                        ForEach([UInt32(200), 400, 600, 800, 1000, 1500, 2000, 2500], id: \.self) { ms in
                            Text("\(ms) ms").tag(ms)
                        }
                    }
                }
                Section("Source") {
                    Picker("Video source", selection: $model.config.videoSource) {
                        Text("Front camera").tag(VideoSource.frontCamera)
                        Text("Rear camera").tag(VideoSource.rearCamera)
                        Text("Screen").tag(VideoSource.screen)
                    }
                }
                Section {
                    Picker("Preset", selection: $model.config.presetId) {
                        ForEach(model.selectablePresets) { item in
                            let base = "\(item.preset.label) · \(item.preset.hevcKbps) kbps"
                            Text(item.isProductionStartable ? base : "\(base) (lab)")
                                .tag(item.preset.id)
                        }
                    }
                    Toggle("H.264 mode", isOn: Binding(
                        get: { model.config.videoCodec == .h264 },
                        set: { model.config.videoCodec = $0 ? .h264 : .hevc }
                    ))
                } header: {
                    Text("Quality")
                } footer: {
                    Text("H.264 trades some image quality for an easier-to-decode stream — try it when 5G/4G/LTE is unstable. Off = H.265 (best quality).")
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
