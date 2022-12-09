import CoreFoundation

var devices: [VideoDevice] = [];
var sessions: [String: VideoCaptureSession] = [:];

@_cdecl("vcavf_initialize")
public func initialize() -> Bool {
    do {
        devices = listDevices();
        return true;
    } catch {
        return false;
    }
}

@_cdecl("vcavf_has_videocapture_auth")
public func has_videocapture_auth() -> Int32 {
    return hasVideoCaptureAuthorization();
}

@_cdecl("vcavf_ask_videocapture_auth")
public func ask_videocapture_auth() {
    return askVideoCaptureAuthorization();
}

@_cdecl("vcavf_devices_count")
public func devices_count() -> UInt32 {
    UInt32(devices.count);
}

@_cdecl("vcavf_get_device_unique_id")
public func get_device_unique_id(deviceIndex: UInt32, buf: UnsafeMutablePointer<CChar>, length: UInt32) {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return;
    }

    copy_str(s: dev.uniqueId, buf: buf, length: length)    
}

@_cdecl("vcavf_get_device_model_id")
public func get_device_model_id(deviceIndex: UInt32, buf: UnsafeMutablePointer<CChar>, length: UInt32) {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return;
    }

    copy_str(s: dev.modelId, buf: buf, length: length)    
}

@_cdecl("vcavf_get_device_name")
public func get_device_name(deviceIndex: UInt32, buf: UnsafeMutablePointer<CChar>, length: UInt32) {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return;
    }

    copy_str(s: dev.name, buf: buf, length: length)
}

@_cdecl("vcavf_get_device_formats_count")
public func get_device_formats_count(deviceIndex: UInt32) -> UInt32 {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return 0;
    }

    return UInt32(dev.formats.count);
}

@_cdecl("vcavf_get_device_format")
public func get_device_format(deviceIndex: UInt32, formatIndex: UInt32, buf: UnsafeMutablePointer<CChar>, length: UInt32) {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return;
    }

    let format: VideoFormat = dev.formats[Int(formatIndex)];

    let formatStr = "\(format.width)x\(format.height);\(format.type)";

    copy_str(s: formatStr, buf: buf, length: length)
}

@_cdecl("vcavf_start_capture")
public func start_capture(deviceIndex: UInt32, width: UInt32, height: UInt32) -> Int32 {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return ERROR_DEVICE_NOT_FOUND;
    }

    var session: VideoCaptureSession? = sessions[dev.uniqueId];

    if session == nil {
        session = VideoCaptureSession();
        sessions[dev.uniqueId] = session;
    } else {
        return 0;
    }

    guard let s = session else {
        return ERROR_OPENING_DEVICE
    }

    return s.startCapture(uniqueId: dev.uniqueId, width: width, height: height)
}

@_cdecl("vcavf_stop_capture")
public func stop_capture(deviceIndex: UInt32) -> Int32 {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return ERROR_DEVICE_NOT_FOUND;
    }

    guard let s = sessions[dev.uniqueId] else {
        return ERROR_SESSION_NOT_STARTED;
    }

    sessions.removeValue(forKey: dev.uniqueId);

    return s.stopCapture()
}

@_cdecl("vcavf_has_new_frame")
public func has_new_frame(deviceIndex: UInt32) -> Bool {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return false;
    }

    guard let session = sessions[dev.uniqueId] else {
        return false;
    }

    return session.hasFrame;
}

@_cdecl("vcavf_grab_frame")
public func grab_frame(deviceIndex: UInt32, buffer: UnsafeMutablePointer<UInt8>, availableBytes: UInt32) -> Bool {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return false;
    }

    guard let session = sessions[dev.uniqueId] else {
        return false;
    }

    return session.grabFrame(dst: buffer, availableBytes: availableBytes);
}

@_cdecl("vcavf_frame_width")
public func frame_width(deviceIndex: UInt32) -> UInt32 {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return 0;
    }

    guard let session = sessions[dev.uniqueId] else {
        return 0;
    }

    return session.width;
}

@_cdecl("vcavf_frame_height")
public func frame_height(deviceIndex: UInt32) -> UInt32 {
    guard let dev: VideoDevice = devices[safe: Int(deviceIndex)] else {
        return 0;
    }

    guard let session = sessions[dev.uniqueId] else {
        return 0;
    }

    return session.height;
}

private func copy_str(s: String, buf: UnsafeMutablePointer<CChar>, length: UInt32) {
    let cs: [CChar]? = s.cString(using: String.Encoding.utf8)

    strncpy(buf, cs, Int(length))
}

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}