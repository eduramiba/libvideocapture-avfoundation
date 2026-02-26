name_x86_64 := libvideocapture_x86_64.dylib
name_arm64 := libvideocapture_arm64.dylib
sdk_path := $(shell xcrun --sdk macosx --show-sdk-path)
sdk_version_major := $(shell xcrun --sdk macosx --show-sdk-version | cut -d. -f1)

target_x86_64 := x86_64-apple-macosx10.10
target_arm64 := arm64-apple-macosx11.0

sources := Sources/videocapture-avfoundation/*.m
headers := Sources/videocapture-avfoundation/include/*.h

common_flags := -fobjc-arc -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -isysroot $(sdk_path)

all: $(name_x86_64) $(if $(filter-out 10,$(sdk_version_major)),$(name_arm64),)

$(name_x86_64): $(sources) $(headers)
	clang $(sources) \
		-target $(target_x86_64) \
		-dynamiclib $(common_flags) \
		-I Sources/videocapture-avfoundation/include \
		-o $(name_x86_64) \
		-Wl,-install_name,$(name_x86_64)

$(name_arm64): $(sources) $(headers)
	clang $(sources) \
		-target $(target_arm64) \
		-dynamiclib $(common_flags) \
		-I Sources/videocapture-avfoundation/include \
		-o $(name_arm64) \
		-Wl,-install_name,$(name_arm64)

test:
	python c_api_test.py

clean:
	rm -f $(name_x86_64) $(name_arm64) videocapture_*.*
