#import "GalahadGSTBridge.h"
#import "gst_ios_init.h"

#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(GALAHAD_HAS_GSTREAMER)
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#endif

/*
 * GStreamer mux/SRT bridge.
 *
 * Product path (galahad_gst_srt_*): MediaCore's MpegTsStreamMuxer produces
 * MPEG-TS bytes; this bridge pushes them through `appsrc ! srtsink` (caller).
 * Video encode is VideoToolbox HEVC outside this bridge.
 *
 * The implementation below is complete but compiles only when
 * GALAHAD_HAS_GSTREAMER is defined by the iOS XCFramework build
 * (Scripts/build-gstreamer-ios.sh). On hosts without the framework, every
 * entry point reports unavailability so callers surface
 * DEVICE VALIDATION REQUIRED instead of inventing success.
 */

struct GalahadGSTContext {
    bool running = false;
    bool srtOnly = false;
    GalahadGSTPipelineConfig config {};
    std::string srtUri;
    std::vector<int> payloadSizes;
    std::mutex mutex;
#if defined(GALAHAD_HAS_GSTREAMER)
    GstElement *pipeline = nullptr;   // owned; unref on stop/destroy
    GstElement *appsrc = nullptr;     // borrowed from pipeline
#endif
};

static void set_detail(GalahadGSTPluginStatus *status, const char *text) {
    if (!status) return;
    std::snprintf(status->detail, sizeof(status->detail), "%s", text ? text : "");
}

#if defined(GALAHAD_HAS_GSTREAMER)

static const size_t kMaxObservedSizes = 256;
static const int kDefaultPayloadBytes = 1316;

static std::once_flag g_gst_init_flag;

static void galahad_ensure_gst_init(void) {
    std::call_once(g_gst_init_flag, [] {
        galahad_gst_ios_init(); // gst_init + static plugin registration
    });
}

static bool galahad_has_element(const char *factory_name) {
    GstElementFactory *factory = gst_element_factory_find(factory_name);
    if (!factory) return false;
    gst_object_unref(factory);
    return true;
}

/* Records SRT payload sizes as srtsink consumes buffers. srtsink sends each
 * buffer's bytes in payload-size (default 1316) messages, so buffer sizes are
 * decomposed the same way libsrt will packetize them. */
static GstPadProbeReturn galahad_srt_sink_probe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data) {
    (void)pad;
    auto *ctx = static_cast<GalahadGSTContext *>(user_data);
    GstBuffer *buffer = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!ctx || !buffer) return GST_PAD_PROBE_OK;

    gsize total = gst_buffer_get_size(buffer);
    int payload = ctx->config.request_pkt_size > 0 ? ctx->config.request_pkt_size : kDefaultPayloadBytes;

    std::lock_guard<std::mutex> lock(ctx->mutex);
    while (total > 0) {
        int chunk = total >= static_cast<gsize>(payload) ? payload : static_cast<int>(total);
        if (ctx->payloadSizes.size() >= kMaxObservedSizes) {
            ctx->payloadSizes.erase(ctx->payloadSizes.begin());
        }
        ctx->payloadSizes.push_back(chunk);
        total -= chunk;
    }
    return GST_PAD_PROBE_OK;
}

/* Tears down ctx->pipeline. Caller must hold no GStreamer locks. */
static void galahad_teardown_pipeline(GalahadGSTContext *ctx) {
    if (!ctx->pipeline) return;
    gst_element_set_state(ctx->pipeline, GST_STATE_NULL);
    gst_object_unref(ctx->pipeline);
    ctx->pipeline = nullptr;
    ctx->appsrc = nullptr;
    ctx->running = false;
}

#endif /* GALAHAD_HAS_GSTREAMER */

bool galahad_gst_probe_plugins(GalahadGSTPluginStatus *out_status) {
    if (!out_status) return false;
    std::memset(out_status, 0, sizeof(*out_status));

#if defined(GALAHAD_HAS_GSTREAMER)
    galahad_ensure_gst_init();

    out_status->gst_init_ok = gst_is_initialized();
    out_status->has_appsrc = galahad_has_element("appsrc");
    out_status->has_videoconvert = galahad_has_element("videoconvert");
    out_status->has_videoscale = galahad_has_element("videoscale");
    out_status->has_mpegtsmux = galahad_has_element("mpegtsmux");
    out_status->has_srtsink = galahad_has_element("srtsink");
    out_status->has_atenc = galahad_has_element("atenc");

    if (!out_status->gst_init_ok) {
        set_detail(out_status, "gst_init failed");
        return false;
    }
    if (!out_status->has_appsrc || !out_status->has_srtsink) {
        set_detail(out_status,
                   "GStreamer initialized but required elements missing "
                   "(appsrc/srtsink); check static plugin registration in gst_ios_init.m");
        return false;
    }
    set_detail(out_status, "GStreamer runtime OK (appsrc + srtsink registered)");
    return true;
#else
    set_detail(
        out_status,
        "GStreamer XCFramework not linked. Build Scripts/build-gstreamer-ios.sh on macOS, "
        "then run FeasibilityBenchmark on a physical iPhone."
    );
    return false;
#endif
}

GalahadGSTContext *galahad_gst_context_create(void) {
    return new GalahadGSTContext();
}

void galahad_gst_context_destroy(GalahadGSTContext *ctx) {
    if (!ctx) return;
#if defined(GALAHAD_HAS_GSTREAMER)
    galahad_teardown_pipeline(ctx);
#endif
    delete ctx;
}

/* Legacy feasibility-harness path: raw I420 frames in, HEVC/TS out via
 * GStreamer's own encoder. The product app does NOT use this graph (encode is
 * VideoToolbox in Swift); it exists for A/B lab comparison on device. */
bool galahad_gst_pipeline_start(GalahadGSTContext *ctx, const GalahadGSTPipelineConfig *config) {
    if (!ctx || !config) return false;
#if !defined(GALAHAD_HAS_GSTREAMER)
    (void)config;
    return false;
#else
    galahad_ensure_gst_init();

    std::lock_guard<std::mutex> lock(ctx->mutex);
    galahad_teardown_pipeline(ctx);
    ctx->config = *config;
    ctx->payloadSizes.clear();
    ctx->srtOnly = false;

    const char *encoder = galahad_has_element("vtenc_h265_hw") ? "vtenc_h265_hw"
                        : galahad_has_element("vtenc_h265")    ? "vtenc_h265"
                                                               : nullptr;
    if (!encoder || !galahad_has_element("h265parse") || !galahad_has_element("mpegtsmux")) {
        return false;
    }

    gchar *sink_desc = nullptr;
    if (config->srt_uri && config->srt_uri[0] != '\0') {
        sink_desc = g_strdup_printf("srtsink name=galahadsink uri=\"%s\" wait-for-connection=false", config->srt_uri);
    } else if (config->output_ts_path && config->output_ts_path[0] != '\0') {
        sink_desc = g_strdup_printf("filesink location=\"%s\"", config->output_ts_path);
    } else {
        return false;
    }

    gchar *desc = g_strdup_printf(
        "appsrc name=galahadsrc is-live=true format=time do-timestamp=false "
        "caps=video/x-raw,format=I420,width=%d,height=%d,framerate=%d/%d "
        "! videoconvert ! %s realtime=true ! h265parse ! mpegtsmux ! %s",
        config->width, config->height,
        config->fps_n > 0 ? config->fps_n : 30,
        config->fps_d > 0 ? config->fps_d : 1,
        encoder, sink_desc);
    g_free(sink_desc);

    GError *error = nullptr;
    GstElement *pipeline = gst_parse_launch(desc, &error);
    g_free(desc);
    if (!pipeline || error) {
        if (error) g_error_free(error);
        if (pipeline) gst_object_unref(pipeline);
        return false;
    }

    ctx->pipeline = pipeline;
    ctx->appsrc = gst_bin_get_by_name(GST_BIN(pipeline), "galahadsrc");
    if (ctx->appsrc) gst_object_unref(ctx->appsrc); // keep borrowed reference

    if (gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        galahad_teardown_pipeline(ctx);
        return false;
    }
    ctx->running = true;
    return true;
#endif
}

bool galahad_gst_push_i420_frame(
    GalahadGSTContext *ctx,
    const uint8_t *data,
    size_t length,
    int64_t pts_ns
) {
    if (!ctx || !data || length == 0) return false;
#if !defined(GALAHAD_HAS_GSTREAMER)
    (void)pts_ns;
    return false;
#else
    std::lock_guard<std::mutex> lock(ctx->mutex);
    if (!ctx->running || ctx->srtOnly || !ctx->appsrc) return false;

    GstBuffer *buffer = gst_buffer_new_allocate(nullptr, length, nullptr);
    if (!buffer) return false;
    gst_buffer_fill(buffer, 0, data, length);
    GST_BUFFER_PTS(buffer) = pts_ns >= 0 ? static_cast<GstClockTime>(pts_ns) : GST_CLOCK_TIME_NONE;

    return gst_app_src_push_buffer(GST_APP_SRC(ctx->appsrc), buffer) == GST_FLOW_OK;
#endif
}

bool galahad_gst_pipeline_stop(GalahadGSTContext *ctx) {
    if (!ctx) return false;
    std::lock_guard<std::mutex> lock(ctx->mutex);
#if defined(GALAHAD_HAS_GSTREAMER)
    if (ctx->appsrc && ctx->running && !ctx->srtOnly) {
        gst_app_src_end_of_stream(GST_APP_SRC(ctx->appsrc));
    }
    galahad_teardown_pipeline(ctx);
#endif
    ctx->running = false;
    return true;
}

/* Product transport path: MPEG-TS bytes → appsrc ! srtsink (caller mode).
 * `srt_uri` carries host/port/latency/mode from SrtEndpoint.callerURL.
 * No FFmpeg srt:// and no libsrt outside GStreamer. */
bool galahad_gst_srt_start(GalahadGSTContext *ctx, const char *srt_uri, int request_pkt_size) {
    if (!ctx || !srt_uri || srt_uri[0] == '\0') return false;
#if !defined(GALAHAD_HAS_GSTREAMER)
    (void)request_pkt_size;
    return false;
#else
    galahad_ensure_gst_init();

    std::lock_guard<std::mutex> lock(ctx->mutex);
    galahad_teardown_pipeline(ctx);

    ctx->srtUri = srt_uri;
    ctx->config.srt_uri = ctx->srtUri.c_str();
    ctx->config.request_pkt_size = request_pkt_size > 0 ? request_pkt_size : kDefaultPayloadBytes;
    ctx->payloadSizes.clear();
    ctx->srtOnly = true;

    GstElement *pipeline = gst_pipeline_new("galahad-srt");
    GstElement *appsrc = gst_element_factory_make("appsrc", "galahadsrc");
    GstElement *srtsink = gst_element_factory_make("srtsink", "galahadsink");
    if (!pipeline || !appsrc || !srtsink) {
        if (appsrc) gst_object_unref(appsrc);
        if (srtsink) gst_object_unref(srtsink);
        if (pipeline) gst_object_unref(pipeline);
        return false;
    }

    GstCaps *caps = gst_caps_new_simple(
        "video/mpegts",
        "systemstream", G_TYPE_BOOLEAN, TRUE,
        "packetsize", G_TYPE_INT, 188,
        nullptr);
    g_object_set(appsrc,
                 "caps", caps,
                 "is-live", TRUE,
                 "format", GST_FORMAT_TIME,
                 "do-timestamp", TRUE,
                 "block", FALSE,
                 /* ~2 s of TS at 10 Mbps; drop-on-overrun handled by flow return */
                 "max-bytes", static_cast<guint64>(2 * 1024 * 1024),
                 nullptr);
    gst_caps_unref(caps);

    g_object_set(srtsink,
                 "uri", srt_uri,
                 "wait-for-connection", FALSE,
                 nullptr);

    gst_bin_add_many(GST_BIN(pipeline), appsrc, srtsink, nullptr);
    if (!gst_element_link(appsrc, srtsink)) {
        gst_object_unref(pipeline); // sinks the added elements
        return false;
    }

    GstPad *sinkpad = gst_element_get_static_pad(srtsink, "sink");
    if (sinkpad) {
        gst_pad_add_probe(sinkpad, GST_PAD_PROBE_TYPE_BUFFER, galahad_srt_sink_probe, ctx, nullptr);
        gst_object_unref(sinkpad);
    }

    if (gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        return false;
    }

    ctx->pipeline = pipeline;
    ctx->appsrc = appsrc; // borrowed: pipeline owns it
    ctx->running = true;
    return true;
#endif
}

bool galahad_gst_srt_send(GalahadGSTContext *ctx, const uint8_t *data, size_t length) {
    if (!ctx || !data || length == 0) return false;
#if !defined(GALAHAD_HAS_GSTREAMER)
    return false;
#else
    std::lock_guard<std::mutex> lock(ctx->mutex);
    if (!ctx->running || !ctx->srtOnly || !ctx->appsrc || !ctx->pipeline) return false;

    /* Fail fast if the pipeline died (srtsink posts errors on the bus). */
    GstBus *bus = gst_element_get_bus(ctx->pipeline);
    if (bus) {
        GstMessage *msg = gst_bus_pop_filtered(bus, GST_MESSAGE_ERROR);
        gst_object_unref(bus);
        if (msg) {
            gst_message_unref(msg);
            galahad_teardown_pipeline(ctx);
            return false;
        }
    }

    GstBuffer *buffer = gst_buffer_new_allocate(nullptr, length, nullptr);
    if (!buffer) return false;
    gst_buffer_fill(buffer, 0, data, length);

    return gst_app_src_push_buffer(GST_APP_SRC(ctx->appsrc), buffer) == GST_FLOW_OK;
#endif
}

bool galahad_gst_srt_stop(GalahadGSTContext *ctx) {
    if (!ctx) return false;
    std::lock_guard<std::mutex> lock(ctx->mutex);
#if defined(GALAHAD_HAS_GSTREAMER)
    if (ctx->appsrc && ctx->running) {
        gst_app_src_end_of_stream(GST_APP_SRC(ctx->appsrc));
    }
    galahad_teardown_pipeline(ctx);
#endif
    ctx->running = false;
    ctx->srtOnly = false;
    ctx->config.srt_uri = nullptr;
    ctx->srtUri.clear();
    return true;
}

size_t galahad_gst_observed_payload_sizes(
    GalahadGSTContext *ctx,
    int *out_sizes,
    size_t capacity
) {
    if (!ctx || !out_sizes || capacity == 0) return 0;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    size_t n = std::min(capacity, ctx->payloadSizes.size());
    for (size_t i = 0; i < n; ++i) {
        out_sizes[i] = ctx->payloadSizes[i];
    }
    return n;
}

const char *galahad_gst_encoder_adapter_name(void) {
    return "videotoolbox-hevc";
}
