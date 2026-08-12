#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GalahadGSTContext GalahadGSTContext;

typedef struct GalahadGSTPluginStatus {
    bool gst_init_ok;
    bool has_appsrc;
    bool has_videoconvert;
    bool has_videoscale;
    bool has_mpegtsmux;
    bool has_srtsink;
    bool has_atenc;
    char detail[512];
} GalahadGSTPluginStatus;

typedef struct GalahadGSTPipelineConfig {
    int width;
    int height;
    int fps_n;
    int fps_d;
    const char *srt_uri;   /* caller URI; may be NULL for filesink-only */
    const char *output_ts_path; /* optional local .ts path */
    int request_pkt_size;  /* preferred 1316; must still be verified */
} GalahadGSTPipelineConfig;

/// Initialize GStreamer and statically register required plugins.
/// Returns false when the XCFramework/plugins are unavailable.
/// Video encode is VideoToolbox HEVC outside this bridge (mux + SRT only).
bool galahad_gst_probe_plugins(GalahadGSTPluginStatus *out_status);

GalahadGSTContext *galahad_gst_context_create(void);
void galahad_gst_context_destroy(GalahadGSTContext *ctx);

bool galahad_gst_pipeline_start(GalahadGSTContext *ctx, const GalahadGSTPipelineConfig *config);
bool galahad_gst_push_i420_frame(
    GalahadGSTContext *ctx,
    const uint8_t *data,
    size_t length,
    int64_t pts_ns
);
bool galahad_gst_pipeline_stop(GalahadGSTContext *ctx);

/// Transport-only path: MPEG-TS bytes → GStreamer `appsrc ! srtsink` (caller).
/// `srt_uri` must be a caller URI (host/port/latency/pkt_size from SrtEndpoint).
/// No FFmpeg `srt://`, no libsrt outside GStreamer.
bool galahad_gst_srt_start(GalahadGSTContext *ctx, const char *srt_uri, int request_pkt_size);
bool galahad_gst_srt_send(GalahadGSTContext *ctx, const uint8_t *data, size_t length);
bool galahad_gst_srt_stop(GalahadGSTContext *ctx);

/// Copies up to `capacity` observed SRT/UDP payload sizes into `out_sizes`.
/// Returns the number of sizes written. Verification must use these values.
size_t galahad_gst_observed_payload_sizes(
    GalahadGSTContext *ctx,
    int *out_sizes,
    size_t capacity
);

/// Descriptive name for the product encode path (VideoToolbox HEVC, not GStreamer).
const char *galahad_gst_encoder_adapter_name(void);

#ifdef __cplusplus
}
#endif
