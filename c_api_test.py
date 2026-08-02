import atexit
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

int32_p = ctypes.POINTER(ctypes.c_int32)
lib.vcavf_get_video_proc_amp_range.argtypes = [
    ctypes.c_uint32,
    ctypes.c_int32,
    int32_p,
    int32_p,
    int32_p,
    int32_p,
    int32_p,
]
lib.vcavf_get_video_proc_amp_range.restype = ctypes.c_int32
lib.vcavf_get_video_proc_amp.argtypes = [
    ctypes.c_uint32,
    ctypes.c_int32,
    int32_p,
    int32_p,
]
lib.vcavf_get_video_proc_amp.restype = ctypes.c_int32
lib.vcavf_set_video_proc_amp.argtypes = [
    ctypes.c_uint32,
    ctypes.c_int32,
    ctypes.c_int32,
    ctypes.c_int32,
]
lib.vcavf_set_video_proc_amp.restype = ctypes.c_int32
lib.vcavf_get_camera_control_range.argtypes = list(
    lib.vcavf_get_video_proc_amp_range.argtypes
)
lib.vcavf_get_camera_control_range.restype = ctypes.c_int32
lib.vcavf_get_camera_control.argtypes = list(lib.vcavf_get_video_proc_amp.argtypes)
lib.vcavf_get_camera_control.restype = ctypes.c_int32
lib.vcavf_set_camera_control.argtypes = list(lib.vcavf_set_video_proc_amp.argtypes)
lib.vcavf_set_camera_control.restype = ctypes.c_int32

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


def sampled_bgra_luma(buffer):
    pixel_count = len(buffer) // 4
    pixel_step = max(1, pixel_count // 5000)
    total = 0.0
    samples = 0
    for pixel in range(0, pixel_count, pixel_step):
        offset = pixel * 4
        blue = buffer[offset]
        green = buffer[offset + 1]
        red = buffer[offset + 2]
        total += 0.0722 * blue + 0.7152 * green + 0.2126 * red
        samples += 1
    return total / max(1, samples)


def get_control_range(range_function, device_index, property_id):
    values = [ctypes.c_int32() for _ in range(5)]
    result = range_function(
        device_index,
        property_id,
        *(ctypes.byref(value) for value in values),
    )
    return result, tuple(value.value for value in values)


def get_control(get_function, device_index, property_id):
    value = ctypes.c_int32()
    flags = ctypes.c_int32()
    result = get_function(
        device_index,
        property_id,
        ctypes.byref(value),
        ctypes.byref(flags),
    )
    return result, value.value, flags.value


assert lib.vcavf_initialize(), "AVFoundation initialization failed"
device_count = lib.vcavf_devices_count()
assert device_count > 0, "No video capture device is available"

control_output = ctypes.c_int32()
assert (
    lib.vcavf_get_video_proc_amp_range(
        0,
        99,
        ctypes.byref(control_output),
        ctypes.byref(control_output),
        ctypes.byref(control_output),
        ctypes.byref(control_output),
        ctypes.byref(control_output),
    )
    == -9
)
assert (
    lib.vcavf_get_video_proc_amp_range(
        0,
        0,
        None,
        ctypes.byref(control_output),
        ctypes.byref(control_output),
        ctypes.byref(control_output),
        ctypes.byref(control_output),
    )
    == -7
)
assert (
    lib.vcavf_get_video_proc_amp(
        device_count,
        0,
        ctypes.byref(control_output),
        ctypes.byref(control_output),
    )
    == -1
)

device_metadata = []
for metadata_index in range(device_count):
    name = get_string(lib.vcavf_get_device_name, metadata_index)
    device_type = get_string(lib.vcavf_get_device_type, metadata_index)
    assert device_type, "Camera device type must not be empty"
    device_metadata.append((name, device_type))
    print("Discovered:", metadata_index, name, "[", device_type, "]")

device_index = next(
    (
        index
        for index, (name, _) in enumerate(device_metadata)
        if "dino" in name.casefold()
    ),
    0,
)
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

capture_cleanup = {"active": False, "device_index": device_index}


def stop_capture_on_exit():
    if capture_cleanup["active"]:
        lib.vcavf_stop_capture(capture_cleanup["device_index"])
        capture_cleanup["active"] = False


atexit.register(stop_capture_on_exit)

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
capture_cleanup["active"] = True
assert lib.vcavf_set_frame_callback(device_index, on_frame, None, True) == 0
wait_for_first_frame(device_index)
time.sleep(1.0)

video_proc_amp_names = (
    "brightness",
    "contrast",
    "hue",
    "saturation",
    "sharpness",
    "gamma",
    "color-enable",
    "white-balance",
    "backlight-compensation",
    "gain",
)
camera_control_names = (
    "pan",
    "tilt",
    "roll",
    "zoom",
    "exposure",
    "iris",
    "focus",
)
supported_video_proc_amp = {}
supported_camera_controls = {}
for property_id, control_name in enumerate(video_proc_amp_names):
    result, control_range = get_control_range(
        lib.vcavf_get_video_proc_amp_range,
        device_index,
        property_id,
    )
    if result != 0:
        continue
    current_result, current_value, current_flags = get_control(
        lib.vcavf_get_video_proc_amp,
        device_index,
        property_id,
    )
    assert current_result == 0
    supported_video_proc_amp[property_id] = (control_range, current_value, current_flags)
    print(
        "VideoProcAmp:",
        control_name,
        "range=%s current=%d flags=%d" % (control_range, current_value, current_flags),
    )

for property_id, control_name in enumerate(camera_control_names):
    result, control_range = get_control_range(
        lib.vcavf_get_camera_control_range,
        device_index,
        property_id,
    )
    if result != 0:
        continue
    current_result, current_value, current_flags = get_control(
        lib.vcavf_get_camera_control,
        device_index,
        property_id,
    )
    assert current_result == 0
    supported_camera_controls[property_id] = (
        control_range,
        current_value,
        current_flags,
    )
    print(
        "CameraControl:",
        control_name,
        "range=%s current=%d flags=%d" % (control_range, current_value, current_flags),
    )

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

selected_device_name = get_string(lib.vcavf_get_device_name, device_index)
if "dino" in selected_device_name.casefold():
    original_luma = sampled_bgra_luma(bgra_buffer)
    mutated_controls = 0
    for property_id, control_name in enumerate(video_proc_amp_names):
        control_state = supported_video_proc_amp.get(property_id)
        if control_state is None:
            continue
        control_range, original_value, original_flags = control_state
        minimum, maximum, step, _, caps = control_range
        if (caps & 2) == 0 or maximum <= minimum:
            continue
        step = max(1, step)
        if property_id == 0:
            target = minimum + (3 * (maximum - minimum)) // 4
            if abs(target - original_value) < max(step, (maximum - minimum) // 8):
                target = minimum + (maximum - minimum) // 4
        else:
            target = original_value + step
            if target > maximum:
                target = original_value - step
        target = max(minimum, min(maximum, target))
        target = minimum + round((target - minimum) / step) * step
        if target == original_value:
            continue

        set_succeeded = False
        try:
            set_result = lib.vcavf_set_video_proc_amp(
                device_index,
                property_id,
                target,
                2,
            )
            assert set_result == 0, "Failed to set %s (result=%d)" % (
                control_name,
                set_result,
            )
            set_succeeded = True
            deadline = time.monotonic() + 5.0
            changed_value = original_value
            changed_flags = original_flags
            result = -1
            while time.monotonic() < deadline:
                result, changed_value, changed_flags = get_control(
                    lib.vcavf_get_video_proc_amp,
                    device_index,
                    property_id,
                )
                if result == 0 and abs(changed_value - target) <= step:
                    break
                time.sleep(0.05)
            assert result == 0, "%s readback failed (result=%d)" % (
                control_name,
                result,
            )
            assert abs(changed_value - target) <= step, (
                "%s did not retain the requested value: requested=%d read=%d"
                % (control_name, target, changed_value)
            )
            assert (changed_flags & 2) != 0
            time.sleep(0.35)
            changed_frame = (ctypes.c_uint8 * bgra_size)()
            assert lib.vcavf_grab_frame_bgra(
                device_index,
                changed_frame,
                bgra_size,
            )
            assert max(changed_frame) > 0
            if property_id == 0:
                changed_luma = sampled_bgra_luma(changed_frame)
                assert abs(changed_luma - original_luma) >= 0.5, (
                    "Brightness readback changed but the frame did not: %.3f -> %.3f"
                    % (original_luma, changed_luma)
                )
                print(
                    "Brightness frame response: %.3f -> %.3f"
                    % (original_luma, changed_luma)
                )
            mutated_controls += 1
        finally:
            if set_succeeded:
                restore_deadline = time.monotonic() + 10.0
                restore_result = -1
                while time.monotonic() < restore_deadline:
                    restore_result = lib.vcavf_set_video_proc_amp(
                        device_index,
                        property_id,
                        original_value,
                        2,
                    )
                    if restore_result == 0:
                        break
                    time.sleep(0.1)
                assert restore_result == 0, (
                    "Failed to restore %s value (result=%d)"
                    % (control_name, restore_result)
                )
                if (original_flags & 1) != 0 and (caps & 1) != 0:
                    automatic_deadline = time.monotonic() + 5.0
                    automatic_result = -1
                    while time.monotonic() < automatic_deadline:
                        automatic_result = lib.vcavf_set_video_proc_amp(
                            device_index,
                            property_id,
                            original_value,
                            1,
                        )
                        if automatic_result == 0:
                            break
                        time.sleep(0.1)
                    assert automatic_result == 0, (
                        "Failed to restore %s automatic mode (result=%d)"
                        % (control_name, automatic_result)
                    )
                time.sleep(0.2)
    assert mutated_controls > 0, "Dino-Lite exposes no writable VideoProcAmp controls"
    print("Dino-Lite reversible control checks passed:", mutated_controls)

    auto_mode_checks = 0
    for property_id, control_name in enumerate(video_proc_amp_names):
        control_state = supported_video_proc_amp.get(property_id)
        if control_state is None:
            continue
        control_range, original_value, original_flags = control_state
        caps = control_range[4]
        if (caps & 1) == 0 or (original_flags & 1) != 0:
            continue
        auto_set_succeeded = False
        try:
            result = lib.vcavf_set_video_proc_amp(
                device_index,
                property_id,
                original_value,
                1,
            )
            assert result == 0, "Failed to enable %s automatic mode (result=%d)" % (
                control_name,
                result,
            )
            auto_set_succeeded = True
            deadline = time.monotonic() + 5.0
            while time.monotonic() < deadline:
                result, _, changed_flags = get_control(
                    lib.vcavf_get_video_proc_amp,
                    device_index,
                    property_id,
                )
                if result == 0 and (changed_flags & 1) != 0:
                    break
                time.sleep(0.05)
            assert result == 0 and (changed_flags & 1) != 0, (
                "%s automatic mode did not read back" % control_name
            )
            auto_mode_checks += 1
        finally:
            if auto_set_succeeded:
                result = lib.vcavf_set_video_proc_amp(
                    device_index,
                    property_id,
                    original_value,
                    original_flags,
                )
                assert result == 0, (
                    "Failed to restore %s mode (result=%d)"
                    % (control_name, result)
                )
        # One successful auto/manual round trip is enough to verify the flag
        # mapping without perturbing every image control in a single run.
        break
    assert auto_mode_checks > 0, "Dino-Lite exposes no testable automatic mode"
    print("Dino-Lite reversible auto/manual mode check passed")

    mutated_camera_controls = 0
    for property_id, control_name in enumerate(camera_control_names):
        control_state = supported_camera_controls.get(property_id)
        if control_state is None:
            continue
        control_range, original_value, original_flags = control_state
        minimum, maximum, step, _, caps = control_range
        if (caps & 2) == 0 or maximum <= minimum:
            continue
        step = max(1, step)
        target = original_value + step
        if target > maximum:
            target = original_value - step
        target = max(minimum, min(maximum, target))
        if target == original_value:
            continue

        set_succeeded = False
        try:
            set_result = lib.vcavf_set_camera_control(
                device_index,
                property_id,
                target,
                2,
            )
            assert set_result == 0, "Failed to set %s (result=%d)" % (
                control_name,
                set_result,
            )
            set_succeeded = True
            deadline = time.monotonic() + 5.0
            result = -1
            changed_value = original_value
            while time.monotonic() < deadline:
                result, changed_value, changed_flags = get_control(
                    lib.vcavf_get_camera_control,
                    device_index,
                    property_id,
                )
                if result == 0 and abs(changed_value - target) <= step:
                    break
                time.sleep(0.05)
            assert result == 0, "%s readback failed (result=%d)" % (
                control_name,
                result,
            )
            assert abs(changed_value - target) <= step, (
                "%s did not retain the requested value: requested=%d read=%d"
                % (control_name, target, changed_value)
            )
            assert (changed_flags & 2) != 0
            changed_frame = (ctypes.c_uint8 * bgra_size)()
            assert lib.vcavf_grab_frame_bgra(
                device_index,
                changed_frame,
                bgra_size,
            )
            assert max(changed_frame) > 0
            mutated_camera_controls += 1
        finally:
            if set_succeeded:
                restore_result = lib.vcavf_set_camera_control(
                    device_index,
                    property_id,
                    original_value,
                    2,
                )
                assert restore_result == 0, (
                    "Failed to restore %s value (result=%d)"
                    % (control_name, restore_result)
                )
                if (original_flags & 1) != 0 and (caps & 1) != 0:
                    automatic_result = lib.vcavf_set_camera_control(
                        device_index,
                        property_id,
                        original_value,
                        1,
                    )
                    assert automatic_result == 0, (
                        "Failed to restore %s automatic mode (result=%d)"
                        % (control_name, automatic_result)
                    )
    assert mutated_camera_controls > 0, (
        "Dino-Lite exposes no writable CameraControl controls"
    )
    print(
        "Dino-Lite reversible CameraControl checks passed:",
        mutated_camera_controls,
    )

rgb_size = width * height * 3
rgb_buffer = (ctypes.c_uint8 * rgb_size)()
assert lib.vcavf_grab_frame(device_index, rgb_buffer, rgb_size)
assert sampled_sum(rgb_buffer) > 0
assert lib.vcavf_set_frame_callback(device_index, FRAME_CALLBACK(), None, False) == 0
assert lib.vcavf_stop_capture(device_index) == 0
capture_cleanup["active"] = False

print(
    "Native callback check passed: %d frames, format=%d, %dx%d, planes=%d; "
    "on-demand BGRA conversion %.3f ms"
    % (callback_frames, pixel_format, width, height, plane_count, bgra_milliseconds)
)

# Verify the old ABI remains functional for existing clients.
assert (
    lib.vcavf_start_capture_with_format_output(device_index, format_index, 0) == 0
), "Legacy RGB capture start failed"
capture_cleanup["active"] = True
wait_for_first_frame(device_index)
assert lib.vcavf_frame_pixel_format(device_index) == 0
width = lib.vcavf_frame_width(device_index)
height = lib.vcavf_frame_height(device_index)
assert (width, height) == (selected_width, selected_height)
legacy_size = width * height * 3
legacy_buffer = (ctypes.c_uint8 * legacy_size)()
assert lib.vcavf_grab_frame(device_index, legacy_buffer, legacy_size)
assert max(legacy_buffer) > 0, (
    "Legacy RGB frame was empty (min=%d, max=%d, sampled=%d)"
    % (min(legacy_buffer), max(legacy_buffer), sampled_sum(legacy_buffer))
)
assert lib.vcavf_stop_capture(device_index) == 0
capture_cleanup["active"] = False

assert lib.vcavf_start_capture(device_index, selected_width, selected_height) == 0
capture_cleanup["active"] = True
wait_for_first_frame(device_index)
legacy_width = lib.vcavf_frame_width(device_index)
legacy_height = lib.vcavf_frame_height(device_index)
legacy_buffer = (ctypes.c_uint8 * (legacy_width * legacy_height * 3))()
assert lib.vcavf_grab_frame(
    device_index,
    legacy_buffer,
    legacy_width * legacy_height * 3,
)
assert max(legacy_buffer) > 0, (
    "Legacy size-based RGB frame was empty (min=%d, max=%d, sampled=%d)"
    % (min(legacy_buffer), max(legacy_buffer), sampled_sum(legacy_buffer))
)
assert lib.vcavf_stop_capture(device_index) == 0
capture_cleanup["active"] = False
print("Legacy RGB start/grab compatibility check passed")
