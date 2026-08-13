import AVFoundation
import MediaCore
import SwiftUI
import UIKit

struct LiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                onAirHeader

                if model.config.videoSource == .screen {
                    screenSharePanel
                } else {
                    cameraPreview
                }

                statsCard
                badgeRow
                controls

                if let err = model.lastError ?? model.status.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var stateColor: Color {
        switch model.status.state {
        case .streaming: return Theme.accent
        case .degraded, .reconnecting, .starting: return Theme.warn
        case .failed: return Theme.bad
        case .idle: return Theme.tertiaryText
        }
    }

    private var stateTitle: String {
        switch model.status.state {
        case .streaming: return "On air"
        case .starting: return "Starting"
        case .degraded: return "Degraded"
        case .reconnecting: return "Reconnecting"
        case .failed: return "Failed"
        case .idle: return "Standby"
        }
    }

    private var onAirHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if model.isStreaming, let start = model.streamStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.elapsedString(since: start))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "cellularbars")
                .foregroundStyle(model.isStreaming ? Theme.accent : Theme.tertiaryText)
        }
        .padding(.top, 4)
    }

    private static func elapsedString(since start: Date) -> String {
        let s = max(Int(Date().timeIntervalSince(start)), 0)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: Preview

    private var cameraPreview: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let layer = model.camera.previewLayer {
                CameraPreviewRepresentable(layer: layer)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.title)
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Preview starts with the stream")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !model.config.destinationHost.isEmpty {
                Text(model.config.destinationHost)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(model.isStreaming ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1)
        )
    }

    private var screenSharePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen share requires Apple's confirmation sheet. Tap the broadcast control to start; the upload extension streams on its own.")
                .font(.subheadline)
                .foregroundStyle(.white)
            BroadcastPickerView()
                .frame(width: 60, height: 60)
            Text("Protected content may render blank or silent.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    // MARK: Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(String(format: "%.1f", model.status.fps), "FPS", .white)
            divider
            statCell(String(format: "%.2f", model.status.bitrateMbps), "Mbps", .white)
            divider
            statCell(
                String(format: "%02d", min(model.status.droppedFrames, 99)),
                "Drops",
                model.status.droppedFrames > 0 ? Theme.bad : .white
            )
        }
        .padding(.vertical, 14)
        .card()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 34)
    }

    private func statCell(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Badges

    private var codecShortName: String {
        model.config.videoCodec == .h264 ? "H.264" : "HEVC"
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            Text("\(codecShortName) · \(model.config.qualityPreset.label.replacingOccurrences(of: " ", with: ""))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.card))

            if model.isStreaming {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
            }

            if model.status.thermalState != .nominal {
                Text("Thermal: \(model.status.thermalState.rawValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.status.thermalState == .fair ? Theme.warn : Theme.bad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.card))
            }

            Spacer()
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            if model.config.videoSource != .screen {
                Button {
                    Task {
                        if model.isStreaming {
                            await model.stopStream()
                        } else {
                            await model.startCameraStream()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.isStreaming ? "stop.fill" : "dot.radiowaves.left.and.right")
                        Text(model.isStreaming ? "Stop stream" : "Go live")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(model.isStreaming ? Theme.bad : Theme.accent)
                    )
                }
                .buttonStyle(.plain)

                if model.isStreaming {
                    Button {
                        Task { await model.switchCamera() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .card()
                }
            }
        }
    }
}

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer = layer
    }

    final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                if let previewLayer {
                    previewLayer.frame = bounds
                    layer.addSublayer(previewLayer)
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
