# Introduction

Simple Objective-C library for webcam video capture on macOS with AVFoundation that exports C functions.

This was built to be used with JNA in https://github.com/eduramiba/webcam-capture-driver-native

## Capture modes

`vcavf_start_capture()` retains the original ABI and returns tightly packed
24-bit RGB frames through `vcavf_grab_frame()`.

Performance-sensitive clients can use
`vcavf_start_capture_with_format_output(..., VCAVF_OUTPUT_NATIVE)`. The native
mode exposes BGRA, NV12, YUY2, UYVY, or MJPEG without converting every frame to
RGB. If the selected device codec cannot be consumed directly, AVFoundation is
asked for NV12 as a hardware/framework conversion fallback.

Use `vcavf_set_frame_callback()` for push delivery. The plane pointers are
borrowed and remain valid only for the duration of the callback, so clients
should copy them into their own ring buffer before returning. The polling
alternative, `vcavf_grab_frame_native()`, returns the latest frame with tightly
packed planes. `vcavf_grab_frame_bgra()` performs an on-demand conversion for
photo capture or image analysis; NV12 conversion uses Accelerate/vImage.

Format descriptions have the form `WIDTHxHEIGHT;TYPE;FPS fps`. The format index
passed to `vcavf_start_capture_with_format_output()` refers to that exact entry,
including its advertised frame-rate range.

## Camera controls

The C API exposes DirectShow-compatible property IDs and auto/manual flags
through these entry points:

- `vcavf_get_video_proc_amp_range`, `vcavf_get_video_proc_amp`, and
  `vcavf_set_video_proc_amp`
- `vcavf_get_camera_control_range`, `vcavf_get_camera_control`, and
  `vcavf_set_camera_control`

On macOS, controls are discovered and operated through the public CoreMediaIO
DAL feature-control properties. This is necessary for external UVC cameras:
the custom exposure, white-balance, focus, and zoom APIs used by the old
`camera-controls` experiment are iOS APIs and are explicitly unavailable for a
macOS target. CoreMediaIO exposes the camera driver's real native range,
current value, settable state, and automatic/manual mode instead.

VideoProcAmp IDs map to CoreMediaIO brightness, contrast, hue, saturation,
sharpness, gamma, white balance/temperature, backlight compensation, and gain
controls. CameraControl IDs map to pan, tilt, roll, zoom, exposure/shutter,
iris, and focus. A camera is free to expose only a subset; absent or read-only
features return `VCAVF_ERR_CONTROL_NOT_SUPPORTED`.

CoreMediaIO represents feature values as `Float32`, while the shared C ABI uses
`int32_t`. Integer native ranges are passed through unchanged. Fractional
ranges are scaled to preserve useful precision, with a step of one in the
scaled range. Because CoreMediaIO does not publish factory defaults, the first
value observed for a device/property during the process is retained as the
session reset value.

### Dino-Lite repeated-write failure

The first CoreMediaIO implementation treated
`kCMIOFeatureControlPropertyOnOff` as an enable bit that had to be written
before every manual value. That interpretation is not portable across UVC DAL
drivers. The Dino-Lite Edge reports the selector, but its image controls are
already active; changing the selector makes its driver withdraw that feature
control from the CoreMediaIO registry. The requested value can still appear to
succeed once, then the next read reports the control as unsupported and a
second write (including restoration) fails until the camera is power-cycled.

The implementation therefore never changes `OnOff` as a side effect of a
value assignment. It changes automatic/manual mode only when the requested
mode differs from the live mode. It also caches the device-session control
object, range, selector, scale, and settable capabilities after the first
successful discovery. Live values and automatic/manual state are still read
from the driver; only stable discovery metadata is cached. This avoids
re-enumeration races with UVC drivers that temporarily stop advertising
`OwnedObjects` or settable metadata after a feature write. The caches are
cleared when the library is initialized with a refreshed device list.

## Build and test

```sh
make -j2
python3 c_api_test.py
```

The makefile builds both `arm64` and `x86_64` dylibs. The integration test needs
camera permission and checks callback delivery, native polling, on-demand BGRA
and RGB capture, undersized-buffer rejection, clean shutdown, and legacy RGB
compatibility against a real camera. When a Dino-Lite is connected, it also
enumerates both control families; changes every writable VideoProcAmp and
CameraControl feature; verifies readback and continued frame delivery; checks
that brightness changes image luminance; and restores each original value and
automatic/manual mode. An exit handler stops active capture even if an
assertion fails, so a failed test does not leave the camera session running.
