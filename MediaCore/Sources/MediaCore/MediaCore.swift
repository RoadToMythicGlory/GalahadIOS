/// MediaCore — layered media contracts for Galahad iOS.
///
/// Layers:
/// 1. Capture (host AVFoundation / ReplayKit extension)
/// 2. Frame normalization
/// 3. H.265 / HEVC encode (`VideoEncoder` abstraction; VideoToolbox is the product adapter)
/// 4. MPEG-TS mux (`MpegTsStreamMuxer` — real PAT/PMT/PES/PCR in pure Swift)
/// 5. SRT caller transport (GStreamer `srtsink`; owns reconnect — no FFmpeg)
///
/// Control WebSocket is independent of the media path.
public enum MediaCoreModule {
    public static let version = "0.4.0-hevc"
    public static let authorizedPhases = "1-7"
}
