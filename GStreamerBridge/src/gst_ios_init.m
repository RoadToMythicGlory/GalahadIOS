/*
 * Static plugin registration list for Galahad's minimal iOS GStreamer build.
 * Encode is VideoToolbox HEVC outside GStreamer; this list is mux + SRT (+ AAC).
 *
 * Compile into app/extension targets when Vendor/GStreamer XCFramework is linked,
 * with GALAHAD_HAS_GSTREAMER defined.
 */

#include "gst_ios_init.h"

#if defined(GALAHAD_HAS_GSTREAMER)

#include <gst/gst.h>

/* Declare static plugins — names must match the official 1.28 iOS xcframework.
 * videoconvert + videoscale merged into the videoconvertscale plugin in 1.20+. */
GST_PLUGIN_STATIC_DECLARE(coreelements);
GST_PLUGIN_STATIC_DECLARE(app);
GST_PLUGIN_STATIC_DECLARE(videoconvertscale);
GST_PLUGIN_STATIC_DECLARE(videotestsrc);
GST_PLUGIN_STATIC_DECLARE(videoparsersbad); /* h265parse for the lab A/B graph */
GST_PLUGIN_STATIC_DECLARE(mpegtsmux);
GST_PLUGIN_STATIC_DECLARE(srt);
GST_PLUGIN_STATIC_DECLARE(audioconvert);
GST_PLUGIN_STATIC_DECLARE(audioresample);
/* Apple VideoToolbox/AudioToolbox elements (vtenc for the lab graph) */
GST_PLUGIN_STATIC_DECLARE(applemedia);

void galahad_gst_ios_init(void) {
    gst_init(NULL, NULL);

    GST_PLUGIN_STATIC_REGISTER(coreelements);
    GST_PLUGIN_STATIC_REGISTER(app);
    GST_PLUGIN_STATIC_REGISTER(videoconvertscale);
    GST_PLUGIN_STATIC_REGISTER(videotestsrc);
    GST_PLUGIN_STATIC_REGISTER(videoparsersbad);
    GST_PLUGIN_STATIC_REGISTER(mpegtsmux);
    GST_PLUGIN_STATIC_REGISTER(srt);
    GST_PLUGIN_STATIC_REGISTER(audioconvert);
    GST_PLUGIN_STATIC_REGISTER(audioresample);
    GST_PLUGIN_STATIC_REGISTER(applemedia);
}

#else

void galahad_gst_ios_init(void) {
    /* no-op without framework */
}

#endif
