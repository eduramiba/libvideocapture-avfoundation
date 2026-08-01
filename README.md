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

## Build and test

```sh
make -j2
python3 c_api_test.py
```

The makefile builds both `arm64` and `x86_64` dylibs. The integration test needs
camera permission and checks callback delivery, native polling, on-demand BGRA
and RGB capture, undersized-buffer rejection, clean shutdown, and legacy RGB
compatibility against a real camera.
