import Foundation

/// Generates deterministic I420-like frames for the feasibility harness.
public struct TestPatternGenerator: Sendable {
    public let profile: VideoProfile

    public init(profile: VideoProfile) {
        self.profile = profile
    }

    public var frameByteCount: Int {
        // I420: Y + U + V = w*h + w*h/4 + w*h/4
        let y = profile.width * profile.height
        return y + y / 2
    }

    public func frame(index: UInt64) -> Data {
        var data = Data(count: frameByteCount)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let yCount = profile.width * profile.height
            for i in 0..<yCount {
                let x = i % profile.width
                let y = i / profile.width
                base[i] = UInt8((x + y + Int(index)) & 0xFF)
            }
            for i in yCount..<frameByteCount {
                base[i] = UInt8((i + Int(index * 3)) & 0x7F)
            }
        }
        return data
    }
}
