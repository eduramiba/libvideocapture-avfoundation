name_x86_64 := libvideocapture_x86_64.dylib
name_arm64 := libvideocapture_arm64.dylib
macos := apple-macosx10.10

sources := Sources/videocapture-avfoundation/*.m
headers := Sources/videocapture-avfoundation/include/*.h

common_flags := -fobjc-arc -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo

all: $(name_x86_64) $(name_arm64)

$(name_x86_64): $(sources) $(headers)
	clang $(sources) \
		-target x86_64-$(macos) \
		-dynamiclib $(common_flags) \
		-I Sources/videocapture-avfoundation/include \
		-o $(name_x86_64) \
		-Wl,-install_name,$(name_x86_64)

$(name_arm64): $(sources) $(headers)
	clang $(sources) \
		-target arm64-$(macos) \
		-dynamiclib $(common_flags) \
		-I Sources/videocapture-avfoundation/include \
		-o $(name_arm64) \
		-Wl,-install_name,$(name_arm64)

test:
	swift test

clean:
	rm -f $(name_x86_64) $(name_arm64) videocapture_*.*
