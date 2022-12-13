name_x86_64 := libvideocapture_x86_64.dylib
name_arm64 := libvideocapture_arm64.dylib
macos := apple-macosx10.10

all: $(name_x86_64) $(name_arm64)

$(name_x86_64): Sources/**/*
	swiftc Sources/videocapture-avfoundation/*.swift \
		-target x86_64-$(macos) \
		-emit-library -o $(name_x86_64) -Xlinker -install_name -Xlinker $(name_x86_64)

$(name_arm64): Sources/**/*
	swiftc Sources/videocapture-avfoundation/*.swift \
		-target arm64-$(macos) \
		-emit-library -o $(name_arm64) -Xlinker -install_name -Xlinker $(name_arm64)

test:
	swift test

clean:
	rm -f $(name_x86_64) $(name_arm64) videocapture_*.*
