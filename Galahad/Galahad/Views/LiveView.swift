import AVFoundation
import MediaCore
import SwiftUI
import UIKit

struct LiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusPill

                if model.config.videoSource == .screen {
                    screenSharePanel
                } else {
                    cameraPreview
                }

                metricsRow

                HStack {
                    if model.config.videoSource != .screen {
                        Button(model.isStreaming ? "Stop" : "Start") {
                            Task {
                                if model.isStreaming {
                                    await model.stopStream()
                                } else {
                                    await model.startCameraStream()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if model.isStreaming {
                            Button("Switch camera") {
                                Task { await model.switchCamera() }
                            }
                        }
                    }
                }

                if let err = model.lastError ?? model.status.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Live")
        }
    }

    private var statusPill: some View {
        Text(model.status.state.rawValue.uppercased())
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(statusColor.opacity(0.2)))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch model.status.state {
        case .streaming: return .green
        case .degraded, .reconnecting, .starting: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var cameraPreview: some View {
        ZStack {
            Color.black
            if let layer = model.camera.previewLayer {
                CameraPreviewRepresentable(layer: layer)
            } else {
                Text("Camera preview")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var screenSharePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen share requires Apple’s confirmation sheet. Tap the broadcast control to start. The upload extension runs Normalize → Encode → Mux → GStreamer SRT on its own.")
                .font(.subheadline)
            BroadcastPickerView()
                .frame(width: 60, height: 60)
            Text("Protected content may render blank/silent. There is no Windows-style per-app audio picker on iOS.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var metricsRow: some View {
        HStack {
            metric("FPS", String(format: "%.1f", model.status.fps))
            metric("Mbps", String(format: "%.2f", model.status.bitrateMbps))
            metric("Drops", "\(model.status.droppedFrames)")
            metric("Thermal", model.status.thermalState.rawValue)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
