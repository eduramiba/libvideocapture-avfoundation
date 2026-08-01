import ctypes
import os
import platform
import time


script_dir = os.path.dirname(os.path.abspath(__file__))
machine = platform.machine().lower()
lib_name = (
    "libvideocapture_arm64.dylib"
    if machine in ("arm64", "aarch64")
    else "libvideocapture_x86_64.dylib"
)
lib = ctypes.CDLL(os.path.join(script_dir, lib_name))

uint8_p = ctypes.POINTER(ctypes.c_uint8)
char_p = ctypes.POINTER(ctypes.c_char)

lib.vcavf_initialize.restype = ctypes.c_bool
lib.vcavf_devices_count.restype = ctypes.c_uint32
lib.vcavf_get_device_unique_id.argtypes = [ctypes.c_uint32, char_p, ctypes.c_uint32]
lib.vcavf_get_device_model_id.argtypes = [ctypes.c_uint32, char_p, ctypes.c_uint32]
lib.vcavf_get_device_name.argtypes = [ctypes.c_uint32, char_p, ctypes.c_uint32]
lib.vcavf_get_device_type.argtypes = [ctypes.c_uint32, char_p, ctypes.c_uint32]
lib.vcavf_get_device_formats_count.argtypes = [ctypes.c_uint32]
lib.vcavf_get_device_formats_count.restype = ctypes.c_uint32
lib.vcavf_get_device_format.argtypes = [ctypes.c_uint32, ctypes.c_uint32, char_p, ctypes.c_uint32]
lib.vcavf_start_capture_with_format_output.argtypes = [
    ctypes.c_uint32,
    ctypes.c_uint32,
    ctypes.c_int32,
]
lib.vcavf_start_capture_with_format_output.restype = ctypes.c_int32
lib.vcavf_start_capture.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32]
lib.vcavf_start_capture.restype = ctypes.c_int32
lib.vcavf_stop_capture.argtypes = [ctypes.c_uint32]
lib.vcavf_stop_capture.restype = ctypes.c_int32
lib.vcavf_has_new_frame.argtypes = [ctypes.c_uint32]
lib.vcavf_has_new_frame.restype = ctypes.c_bool
lib.vcavf_frame_width.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_width.restype = ctypes.c_uint32
lib.vcavf_frame_height.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_height.restype = ctypes.c_uint32
lib.vcavf_frame_bytes_per_row.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_bytes_per_row.restype = ctypes.c_uint32
lib.vcavf_frame_data_size.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_data_size.restype = ctypes.c_uint32
lib.vcavf_frame_pixel_format.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_pixel_format.restype = ctypes.c_int32
lib.vcavf_frame_plane_count.argtypes = [ctypes.c_uint32]
lib.vcavf_frame_plane_count.restype = ctypes.c_uint32
lib.vcavf_frame_plane_offset.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
lib.vcavf_frame_plane_offset.restype = ctypes.c_uint32
lib.vcavf_frame_plane_stride.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
lib.vcavf_frame_plane_stride.restype = ctypes.c_uint32
lib.vcavf_grab_frame.argtypes = [ctypes.c_uint32, uint8_p, ctypes.c_uint32]
lib.vcavf_grab_frame.restype = ctypes.c_bool
lib.vcavf_grab_frame_native.argtypes = [ctypes.c_uint32, uint8_p, ctypes.c_uint32]
lib.vcavf_grab_frame_native.restype = ctypes.c_bool
lib.vcavf_grab_frame_bgra.argtypes = [ctypes.c_uint32, uint8_p, ctypes.c_uint32]
lib.vcavf_grab_frame_bgra.restype = ctypes.c_bool

FRAME_CALLBACK = ctypes.CFUNCTYPE(
    None,
    ctypes.c_uint32,
    ctypes.c_int32,
    ctypes.c_uint32,
    ctypes.c_uint32,
    ctypes.c_uint32,
    uint8_p,
    ctypes.c_size_t,
    ctypes.c_uint32,
    uint8_p,
    ctypes.c_size_t,
    ctypes.c_uint32,
    ctypes.c_int64,
    ctypes.c_void_p,
)
lib.vcavf_set_frame_callback.argtypes = [
    ctypes.c_uint32,
    FRAME_CALLBACK,
    ctypes.c_void_p,
    ctypes.c_bool,
]
lib.vcavf_set_frame_callback.restype = ctypes.c_int32


def get_string(function, *indices):
    buffer = ctypes.create_string_buffer(256)
    function(*indices, buffer, len(buffer))
    return buffer.value.decode("utf-8", errors="replace")


def parse_format(value):
    fields = value.split(";")
    width, height = (int(part) for part in fields[0].split("x", 1))
    frame_rate = float(fields[2].split()[0]) if len(fields) > 2 else 0.0
    return width, height, fields[1] if len(fields) > 1 else "", frame_rate


def wait_for_first_frame(device_index, timeout_seconds=5.0):
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if lib.vcavf_has_new_frame(device_index):
            return
        time.sleep(0.02)
    raise AssertionError("Timed out waiting for the first camera frame")


def sampled_sum(buffer):
    return sum(buffer[offset] for offset in range(0, len(buffer), 4096))


assert lib.vcavf_initialize(), "AVFoundation initialization failed"
device_count = lib.vcavf_devices_count()
assert device_count > 0, "No video capture device is available"

device_metadata = []
for metadata_index in range(device_count):
    name = get_string(lib.vcavf_get_device_name, metadata_index)
    device_type = get_string(lib.vcavf_get_device_type, metadata_index)
    assert device_type, "Camera device type must not be empty"
    device_metadata.append((name, device_type))
    print("Discovered:", metadata_index, name, "[", device_type, "]")

device_index = 0
print("Device:", get_string(lib.vcavf_get_device_name, device_index))
print("Unique ID:", get_string(lib.vcavf_get_device_unique_id, device_index))
print("Model ID:", get_string(lib.vcavf_get_device_model_id, device_index))

formats = []
for format_index in range(lib.vcavf_get_device_formats_count(device_index)):
    value = get_string(lib.vcavf_get_device_format, device_index, format_index)
    parsed = parse_format(value)
    formats.append((format_index, value, parsed))
    print(format_index, value)

assert formats, "Camera exposes no formats"
realtime_formats = [entry for entry in formats if entry[2][3] >= 29.0]
selected = max(realtime_formats or formats, key=lambda entry: entry[2][0] * entry[2][1])
format_index, format_description, _ = selected
selected_width, selected_height, _, _ = selected[2]
print("Selected:", format_description)

callback_frames = 0
callback_layout = None


@FRAME_CALLBACK
def on_frame(
    callback_device,
    pixel_format,
    width,
    height,
    plane_count,
    plane0,
    plane0_bytes,
    plane0_stride,
    plane1,
    plane1_bytes,
    plane1_stride,
    timestamp_nanoseconds,
    user_data,
):
    del plane0, plane1, timestamp_nanoseconds, user_data
    global callback_frames, callback_layout
    assert callback_device == device_index
    callback_frames += 1
    callback_layout = (
        pixel_format,
        width,
        height,
        plane_count,
        plane0_bytes,
        plane0_stride,
        plane1_bytes,
        plane1_stride,
    )


assert (
    lib.vcavf_start_capture_with_format_output(device_index, format_index, 1) == 0
), "Native capture start failed"
assert lib.vcavf_set_frame_callback(device_index, on_frame, None, True) == 0
wait_for_first_frame(device_index)
time.sleep(1.0)

width = lib.vcavf_frame_width(device_index)
height = lib.vcavf_frame_height(device_index)
data_size = lib.vcavf_frame_data_size(device_index)
pixel_format = lib.vcavf_frame_pixel_format(device_index)
plane_count = lib.vcavf_frame_plane_count(device_index)
assert width > 0 and height > 0 and data_size > 0
assert (width, height) == (selected_width, selected_height), (
    "Exact format was not preserved: expected %dx%d, got %dx%d"
    % (selected_width, selected_height, width, height)
)
assert pixel_format in (1, 2, 3, 4, 7)
assert plane_count in (1, 2)
assert callback_frames > 0 and callback_layout is not None

native_buffer = (ctypes.c_uint8 * data_size)()
assert lib.vcavf_grab_frame_native(device_index, native_buffer, data_size)
assert sampled_sum(native_buffer) > 0

bgra_size = width * height * 4
bgra_buffer = (ctypes.c_uint8 * bgra_size)()
started = time.perf_counter()
assert lib.vcavf_grab_frame_bgra(device_index, bgra_buffer, bgra_size)
bgra_milliseconds = (time.perf_counter() - started) * 1000.0
assert sampled_sum(bgra_buffer) > 0
assert not lib.vcavf_grab_frame_bgra(device_index, bgra_buffer, bgra_size - 1)

rgb_size = width * height * 3
rgb_buffer = (ctypes.c_uint8 * rgb_size)()
assert lib.vcavf_grab_frame(device_index, rgb_buffer, rgb_size)
assert sampled_sum(rgb_buffer) > 0
assert lib.vcavf_set_frame_callback(device_index, FRAME_CALLBACK(), None, False) == 0
assert lib.vcavf_stop_capture(device_index) == 0

print(
    "Native callback check passed: %d frames, format=%d, %dx%d, planes=%d; "
    "on-demand BGRA conversion %.3f ms"
    % (callback_frames, pixel_format, width, height, plane_count, bgra_milliseconds)
)

# Verify the old ABI remains functional for existing clients.
assert (
    lib.vcavf_start_capture_with_format_output(device_index, format_index, 0) == 0
), "Legacy RGB capture start failed"
wait_for_first_frame(device_index)
assert lib.vcavf_frame_pixel_format(device_index) == 0
width = lib.vcavf_frame_width(device_index)
height = lib.vcavf_frame_height(device_index)
assert (width, height) == (selected_width, selected_height)
legacy_size = width * height * 3
legacy_buffer = (ctypes.c_uint8 * legacy_size)()
assert lib.vcavf_grab_frame(device_index, legacy_buffer, legacy_size)
assert sampled_sum(legacy_buffer) > 0
assert lib.vcavf_stop_capture(device_index) == 0

assert lib.vcavf_start_capture(device_index, selected_width, selected_height) == 0
wait_for_first_frame(device_index)
legacy_width = lib.vcavf_frame_width(device_index)
legacy_height = lib.vcavf_frame_height(device_index)
legacy_buffer = (ctypes.c_uint8 * (legacy_width * legacy_height * 3))()
assert lib.vcavf_grab_frame(
    device_index,
    legacy_buffer,
    legacy_width * legacy_height * 3,
)
assert sampled_sum(legacy_buffer) > 0
assert lib.vcavf_stop_capture(device_index) == 0
print("Legacy RGB start/grab compatibility check passed")
