import ctypes
import time

lib = ctypes.CDLL('libvideocapture_x86_64.dylib')
lib.vcavf_get_device_unique_id.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_char), ctypes.c_uint32]
lib.vcavf_get_device_model_id.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_char), ctypes.c_uint32]
lib.vcavf_get_device_name.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_char), ctypes.c_uint32]
lib.vcavf_get_device_format.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.c_char), ctypes.c_uint32]
lib.vcavf_has_new_frame.restype = ctypes.c_bool
lib.vcavf_grab_frame.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32]
lib.vcavf_grab_frame.restype = ctypes.c_bool

lib.vcavf_initialize()

lib.vcavf_ask_videocapture_auth()
print(lib.vcavf_has_videocapture_auth())

print(lib.vcavf_devices_count())

buf = ctypes.cast(ctypes.create_string_buffer(100),ctypes.POINTER(ctypes.c_char))

lib.vcavf_get_device_unique_id(0, buf, 100)
unique_id = ctypes.c_char_p.from_buffer(buf).value
lib.vcavf_get_device_model_id(0, buf, 100)
model_id = ctypes.c_char_p.from_buffer(buf).value
lib.vcavf_get_device_name(0, buf, 100)
name = ctypes.c_char_p.from_buffer(buf).value

print(unique_id)
print(model_id)
print(name)

formats_count = lib.vcavf_get_device_formats_count(0)

for i in range(formats_count):
    lib.vcavf_get_device_format(0, i, buf, 100)
    format = ctypes.c_char_p.from_buffer(buf).value

    print(format)

lib.vcavf_start_capture(0, 1280, 720)

time.sleep(1)
for i in range(3):
    time.sleep(1)
    print(lib.vcavf_has_new_frame(0))
    print(lib.vcavf_frame_width(0))
    print(lib.vcavf_frame_height(0))