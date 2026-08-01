#ifndef VIDEOCAPTURE_AVFOUNDATION_H
#define VIDEOCAPTURE_AVFOUNDATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool vcavf_initialize(void);

int32_t vcavf_has_videocapture_auth(void);
void vcavf_ask_videocapture_auth(void);

uint32_t vcavf_devices_count(void);

void vcavf_get_device_unique_id(uint32_t deviceIndex, char *buf, uint32_t length);
void vcavf_get_device_model_id(uint32_t deviceIndex, char *buf, uint32_t length);
void vcavf_get_device_name(uint32_t deviceIndex, char *buf, uint32_t length);

uint32_t vcavf_get_device_formats_count(uint32_t deviceIndex);
void vcavf_get_device_format(uint32_t deviceIndex, uint32_t formatIndex, char *buf, uint32_t length);

int32_t vcavf_start_capture(uint32_t deviceIndex, uint32_t width, uint32_t height);
int32_t vcavf_start_capture_with_format_output(uint32_t deviceIndex, uint32_t formatIndex, int32_t outputMode);
int32_t vcavf_stop_capture(uint32_t deviceIndex);

bool vcavf_has_new_frame(uint32_t deviceIndex);
bool vcavf_grab_frame(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes);

uint32_t vcavf_frame_width(uint32_t deviceIndex);
uint32_t vcavf_frame_height(uint32_t deviceIndex);
uint32_t vcavf_frame_bytes_per_row(uint32_t deviceIndex);
uint32_t vcavf_frame_data_size(uint32_t deviceIndex);
int32_t vcavf_frame_pixel_format(uint32_t deviceIndex);
uint32_t vcavf_frame_plane_count(uint32_t deviceIndex);
uint32_t vcavf_frame_plane_offset(uint32_t deviceIndex, uint32_t planeIndex);
uint32_t vcavf_frame_plane_stride(uint32_t deviceIndex, uint32_t planeIndex);

enum {
    VCAVF_OUTPUT_RGB = 0,
    VCAVF_OUTPUT_NATIVE = 1,
};

enum {
    VCAVF_PIXEL_FORMAT_RGB = 0,
    VCAVF_PIXEL_FORMAT_BGRA = 1,
    VCAVF_PIXEL_FORMAT_NV12 = 2,
    VCAVF_PIXEL_FORMAT_YUY2 = 3,
    VCAVF_PIXEL_FORMAT_MJPEG = 4,
    VCAVF_PIXEL_FORMAT_I420 = 6,
    VCAVF_PIXEL_FORMAT_UYVY = 7,
};

typedef void (*vcavf_frame_callback)(
    uint32_t deviceIndex,
    int32_t pixelFormat,
    uint32_t width,
    uint32_t height,
    uint32_t planeCount,
    const uint8_t *plane0,
    size_t plane0Bytes,
    uint32_t plane0Stride,
    const uint8_t *plane1,
    size_t plane1Bytes,
    uint32_t plane1Stride,
    int64_t timestampNanoseconds,
    void *userData);

int32_t vcavf_set_frame_callback(
    uint32_t deviceIndex,
    vcavf_frame_callback callback,
    void *userData,
    bool exclusive);
bool vcavf_grab_frame_native(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes);
bool vcavf_grab_frame_bgra(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes);

#ifdef __cplusplus
}
#endif

#endif
