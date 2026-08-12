import ReplayKit
import SwiftUI
import UIKit

/// Host embedding of Apple's system broadcast picker. Screen start always requires user confirmation.
struct BroadcastPickerView: UIViewRepresentable {
    var preferredExtension: String = "gg.galahad.ios.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = preferredExtension
    }
}
