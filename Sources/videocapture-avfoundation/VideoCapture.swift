import AVFoundation

let RESULT_OK = Int32(0);
let ERROR_DEVICE_NOT_FOUND = Int32(-1);
let ERROR_FORMAT_NOT_FOUND = Int32(-2);
let ERROR_OPENING_DEVICE = Int32(-3);
let ERROR_SESSION_ALREADY_STARTED = Int32(-4);
let ERROR_SESSION_NOT_STARTED = Int32(-5);
let STATUS_AUTHORIZED = Int32(0);
let STATUS_NOT_DETERMINED = Int32(-2);
let STATUS_DENIED = Int32(-1);

public func listDevices() -> [VideoDevice] {
    var cameras: [VideoDevice] = [];

    let devices = AVCaptureDevice.devices(for: AVMediaType.video);
    for device in devices {
        let formats = device.formats.filter({ $0.mediaType == AVMediaType.video });

        if (!formats.isEmpty) {
            let videoFormats = formats.map(toVideoFormat);

            let camera = VideoDevice(uniqueId: device.uniqueID, modelId: device.modelID, name: device.localizedName, formats: videoFormats);
            cameras.append(camera);
        }
    }

    return cameras;
}

public func hasVideoCaptureAuthorization() -> Int32 {
    if #available(OSX 10.14, *) {
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 14, patchVersion: 0)) {
            let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
            switch authStatus {
                case .authorized: return STATUS_AUTHORIZED;
                case .denied, .restricted: return STATUS_DENIED;
                default: return STATUS_NOT_DETERMINED;
            }
        }
    }

    return STATUS_AUTHORIZED; 
}


public func askVideoCaptureAuthorization() {
    if #available(OSX 10.14, *) {
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 14, patchVersion: 0)) {
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted: Bool) -> Void in
                if granted == true {
                    print("Video capture authorization granted by user")
                } else {
                    print("Video capture authorization rejected by user")
                }
            });
        }
    }
}

public func toVideoFormat(format: AVCaptureDevice.Format) -> VideoFormat {
    let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    let fourcc = CMFormatDescriptionGetMediaSubType(format.formatDescription);

    let type = fourCCMappings[fourcc] ?? ("UNKNOWN_" + String(fourcc));

    return VideoFormat(width: UInt32(size.width), height: UInt32(size.height), type: type)
}

private let fourCCMappings: [CMPixelFormatType: String] = [
    // Raw formats
    kCMPixelFormat_32ARGB: "ARGB",
    kCMPixelFormat_32BGRA: "BGRA",
    kCMPixelFormat_24RGB: "RGB",
    kCMPixelFormat_16BE555: "RGB555BE",
    kCMPixelFormat_16BE565: "RGB565BE",
    kCMPixelFormat_16LE555: "RGB555",
    kCMPixelFormat_16LE565: "RGB565",
    kCMPixelFormat_16LE5551: "ARGB555",
    kCMPixelFormat_422YpCbCr8: "UYVY",
    kCMPixelFormat_422YpCbCr8_yuvs: "YUY2",
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: "NV12", //Review this

    // Compressed formats
    kCMVideoCodecType_JPEG: "JPEG",
    kCMVideoCodecType_JPEG_OpenDML: "MJPG",
    kCMVideoCodecType_H263: "H263",
    kCMVideoCodecType_H264: "H264",
    kCMVideoCodecType_HEVC: "HEVC",
    kCMVideoCodecType_MPEG4Video: "MPG4",
    kCMVideoCodecType_MPEG2Video: "MPG2",
    kCMVideoCodecType_MPEG1Video: "MPG1"
]
