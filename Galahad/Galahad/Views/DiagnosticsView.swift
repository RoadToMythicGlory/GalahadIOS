import MediaCore
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Link health")

                    gaugeCard
                    statusRowsCard

                    SectionCaption("Uplink bitrate (30 sec)")
                    bitrateCard

                    identityCard
                    logsCard

                    copyButton
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Health score

    /// Honest composite: lifecycle state sets the band, accumulated drops
    /// pull it down. Nil when idle (nothing to measure).
    private var healthPercent: Int? {
        let dropPenalty = Int(min(model.status.droppedFrames / 5, 35))
        switch model.status.state {
        case .idle: return nil
        case .starting: return 80
        case .streaming: return max(55, 98 - dropPenalty)
        case .degraded: return max(40, 65 - dropPenalty)
        case .reconnecting: return 45
        case .failed: return 10
        }
    }

    private var healthLabel: (String, Color) {
        guard let health = healthPercent else { return ("Standby", Theme.tertiaryText) }
        switch health {
        case 85...: return ("Stable", Theme.accent)
        case 55..<85: return ("Degraded", Theme.warn)
        default: return ("Unstable", Theme.bad)
        }
    }

    private var gaugeCard: some View {
        let health = healthPercent
        let (label, color) = healthLabel
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Theme.cardElevated, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * CGFloat(health ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.4), value: health)

                VStack(spacing: 2) {
                    if let health {
                        Text("\(health)")
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        + Text("%")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                    Text("Signal health")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 190, height: 190)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    // MARK: Status rows

    private var srtStatus: (String, Color) {
        switch model.status.state {
        case .streaming: return ("Good", Theme.good)
        case .starting: return ("Connecting", Theme.warn)
        case .degraded: return ("Degraded", Theme.warn)
        case .reconnecting: return ("Retrying", Theme.warn)
        case .failed: return ("Down", Theme.bad)
        case .idle: return ("Idle", Theme.tertiaryText)
        }
    }

    private var encoderStatus: (String, Color) {
        guard model.isStreaming else { return ("Ready", Theme.tertiaryText) }
        if let name = model.status.encoderName, name.contains("stub") {
            return ("Stub", Theme.warn)
        }
        return ("Good", Theme.good)
    }

    private var controlStatus: (String, Color) {
        switch model.controlState {
        case .connected: return ("Good", Theme.good)
        case .connecting: return ("Connecting", Theme.warn)
        case .reconnecting: return ("Retrying", Theme.warn)
        case .idle: return ("Off", Theme.tertiaryText)
        }
    }

    private var codecShortName: String {
        model.config.videoCodec == .h264 ? "H.264" : "HEVC"
    }

    private var statusRowsCard: some View {
        VStack(spacing: 0) {
            statusRow(icon: "antenna.radiowaves.left.and.right", name: "SRT uplink", status: srtStatus)
            Divider().overlay(Theme.stroke)
            statusRow(icon: "cpu", name: "\(codecShortName) engine", status: encoderStatus)
            Divider().overlay(Theme.stroke)
            statusRow(icon: "dot.radiowaves.up.forward", name: "Control", status: controlStatus)
        }
        .card()
    }

    private func statusRow(icon: String, name: String, status: (String, Color)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 24)
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            StatusTag(label: status.0, color: status.1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Bitrate

    private var bitrateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Sparkline(values: model.bitrateHistory)
                    .frame(height: 56)
            }
            HStack {
                Text(String(format: "%.2f Mbps now", model.status.bitrateMbps))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if !model.bitrateHistory.isEmpty {
                    let avg = model.bitrateHistory.reduce(0, +) / Double(model.bitrateHistory.count)
                    Text(String(format: "%.2f Mbps avg", avg))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(14)
        .card()
    }

    // MARK: Identity / logs

    private var identityCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Player ID")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text(model.identity.playerId)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = model.identity.playerId
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .card()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logs")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ScrollView {
                Text(model.logs.suffix(80).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
        }
        .padding(14)
        .card()
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = model.diagnosticsText
            model.appendLog("diagnostics copied")
        } label: {
            HStack(spacing: 8) {
                Text("Copy diagnostics")
                Image(systemName: "doc.on.clipboard")
            }
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
