#ifndef VIDEOCAPTURE_AVFOUNDATION_H
#define VIDEOCAPTURE_AVFOUNDATION_H

#include <stdbool.h>
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
int32_t vcavf_stop_capture(uint32_t deviceIndex);

bool vcavf_has_new_frame(uint32_t deviceIndex);
bool vcavf_grab_frame(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes);

uint32_t vcavf_frame_width(uint32_t deviceIndex);
uint32_t vcavf_frame_height(uint32_t deviceIndex);
uint32_t vcavf_frame_bytes_per_row(uint32_t deviceIndex);

#ifdef __cplusplus
}
#endif

#endif
