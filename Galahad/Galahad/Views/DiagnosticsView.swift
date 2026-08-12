import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Identity")
                    .font(.headline)
                LabeledContent("playerId", value: model.identity.playerId)
                LabeledContent("sessionId", value: model.identity.sessionId)
                LabeledContent("control", value: model.controlState.rawValue)
                LabeledContent("last error", value: model.status.lastError ?? model.lastError ?? "-")

                Text("Logs")
                    .font(.headline)
                ScrollView {
                    Text(model.logs.suffix(80).joined(separator: "\n"))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Copy diagnostics") {
                    UIPasteboard.general.string = model.diagnosticsText
                    model.appendLog("diagnostics copied")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Diagnostics")
        }
    }
}
