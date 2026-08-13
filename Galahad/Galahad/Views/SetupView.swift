import MediaCore
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var justSaved = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "New stream")

                    SectionCaption("Destination")
                    destinationCard

                    SectionCaption("Preset")
                    presetCards

                    SectionCaption("Source")
                    sourceSelector

                    SectionCaption("Transport")
                    transportCard

                    SectionCaption("Identity")
                    identityCard

                    SectionCaption("Control channel")
                    controlCard

                    saveButton
                        .padding(.top, 6)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Destination

    private var destinationConfigured: Bool {
        !model.config.destinationHost.isEmpty && model.config.destinationPort > 0
    }

    private var destinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(destinationConfigured ? Theme.accent : Theme.secondaryText)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardElevated)
                )

            VStack(spacing: 8) {
                TextField("Host (SRT receiver)", text: $model.config.destinationHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.weight(.medium))
                TextField("Port", value: $model.config.destinationPort, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "cellularbars")
                    .foregroundStyle(destinationConfigured ? Theme.accent : Theme.tertiaryText)
                Text(destinationConfigured ? "Ready" : "Not set")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(destinationConfigured ? Theme.accent : Theme.tertiaryText)
            }
        }
        .padding(14)
        .card()
    }

    // MARK: Preset

    private var codecShortName: String {
        model.config.videoCodec == .h264 ? "H.264" : "HEVC"
    }

    private var presetCards: some View {
        VStack(spacing: 10) {
            ForEach(model.selectablePresets) { item in
                let selected = model.config.presetId == item.preset.id
                Button {
                    model.config.presetId = item.preset.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.preset.label.replacingOccurrences(of: " ", with: ""))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(String(format: "%.1f Mbps · %@%@",
                                        Double(item.preset.hevcKbps) / 1000.0,
                                        codecShortName,
                                        item.isProductionStartable ? "" : " · lab"))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected ? Theme.accent : Theme.tertiaryText)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
                .card(selected: selected)
            }
        }
    }

    // MARK: Source

    private var sourceSelector: some View {
        HStack(spacing: 10) {
            sourceButton(.frontCamera, icon: "person.crop.rectangle", label: "Front")
            sourceButton(.rearCamera, icon: "camera.fill", label: "Rear")
            sourceButton(.screen, icon: "display", label: "Screen")
        }
    }

    private func sourceButton(_ source: VideoSource, icon: String, label: String) -> some View {
        let selected = model.config.videoSource == source
        return Button {
            model.config.videoSource = source
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(selected ? .white : Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .card(selected: selected)
    }

    // MARK: Transport

    private var transportCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Latency")
                    .foregroundStyle(.white)
                Spacer()
                // 200-600 suits LAN/metro links; 1000-2500 buys retransmission
                // headroom for cross-country 5G/4G/LTE (SRT wants ~4x RTT).
                Picker("Latency", selection: $model.config.latencyMs) {
                    ForEach([UInt32(200), 400, 600, 800, 1000, 1500, 2000, 2500], id: \.self) { ms in
                        Text("\(ms) ms").tag(ms)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().overlay(Theme.stroke)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { model.config.videoCodec == .h264 },
                    set: { model.config.videoCodec = $0 ? .h264 : .hevc }
                )) {
                    Text("H.264 mode")
                        .foregroundStyle(.white)
                }
                .tint(Theme.accent)
                Text("Easier-to-decode stream for unstable 5G/4G/LTE. Off = H.265 (best quality).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(14)
        }
        .card()
    }

    // MARK: Identity / control

    private var identityCard: some View {
        HStack {
            TextField("Display name", text: $model.config.displayName)
                .font(.body.weight(.medium))
            Spacer()
            Text(model.config.playerId)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(14)
        .card()
    }

    private var controlCard: some View {
        TextField("WebSocket URL (optional)", text: Binding(
            get: { model.config.controlChannelURL ?? "" },
            set: { model.config.controlChannelURL = $0.isEmpty ? nil : $0 }
        ))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.subheadline)
        .padding(14)
        .card()
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            Task {
                await model.saveConfig()
                withAnimation(.easeOut(duration: 0.2)) { justSaved = true }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { justSaved = false }
            }
        } label: {
            HStack(spacing: 8) {
                if justSaved {
                    Image(systemName: "checkmark")
                }
                Text(justSaved ? "Saved" : (destinationConfigured ? "Ready to stream" : "Save setup"))
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(justSaved ? Theme.good : Theme.accent)
            )
        }
        .buttonStyle(.plain)
    }
}
