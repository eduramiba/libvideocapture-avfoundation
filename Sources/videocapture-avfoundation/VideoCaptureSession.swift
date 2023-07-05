import AVFoundation

public class VideoCaptureSession : NSObject {

    /// Dispatch queue for capture session events.
    fileprivate let captureSessionQueue = DispatchQueue(label: "CameraSessionQueue", attributes: [])
    fileprivate let semaphore = DispatchSemaphore(value: 1)

    private var deviceInput: AVCaptureDeviceInput? = nil;
    private var session: AVCaptureSession? = nil;
    private var outputData: AVCaptureVideoDataOutput? = nil;
    private var buffer: UnsafeMutablePointer<UInt8>? = nil;
    public var hasFrame: Bool = false
    public var width: UInt32 = 0;
    public var height: UInt32 = 0;
    public var bytesPerRow: UInt32 = 0;

    public override init() {
        super.init();
        NotificationCenter.default.addObserver(self, selector: #selector(captureSessionRuntimeError), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
    }

    @objc fileprivate func captureSessionRuntimeError() {
        print("captureSessionRuntimeError")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func stopCapture() -> Int32 {
        self.semaphore.wait();
        defer {
            self.semaphore.signal();
        }

        guard let s = session else {
            return ERROR_SESSION_NOT_STARTED;
        }

        s.stopRunning();
        self.deviceInput = nil;
        self.outputData = nil;
        self.session = nil;
        self.buffer = nil;
        self.hasFrame = false;
        self.width = 0;
        self.height = 0;

        return RESULT_OK;
    }

    public func grabFrame(dst: UnsafeMutablePointer<UInt8>, availableBytes: UInt32) -> Bool {
        self.semaphore.wait();
        defer {
            self.semaphore.signal();
        }

        guard hasFrame else {
            return false;
        }

        memcpy(dst, self.buffer, Int(availableBytes))

        hasFrame = false;

        return true;
    }

    public func startCapture(uniqueId: String, format: VideoFormat) -> Int32 {
        return startCapture(uniqueId: uniqueId, width: format.width, height: format.height)
    }

    public func startCapture(uniqueId: String, width: UInt32, height: UInt32) -> Int32 {
        self.semaphore.wait();
        defer {
            self.semaphore.signal();
        }

        if self.session != nil {
            return ERROR_SESSION_ALREADY_STARTED;
        }        

        let devices = AVCaptureDevice.devices(for: AVMediaType.video);

        guard let device = devices.first(where: { $0.uniqueID == uniqueId }) else {
            return ERROR_DEVICE_NOT_FOUND;
        }

        let formats = device.formats.filter({ $0.mediaType == AVMediaType.video });
        let format = formats.first(where: {
            let vf = toVideoFormat(format: $0);
            return vf.width == width && vf.height == height
        });

        if format == nil {
            return ERROR_FORMAT_NOT_FOUND;
        }

        do {                
            let deviceInput : AVCaptureDeviceInput = try AVCaptureDeviceInput(device: device);

            let session: AVCaptureSession = AVCaptureSession();
            session.beginConfiguration();

            guard session.canAddInput(deviceInput) else {
                print("canAddInput failed")
                return ERROR_OPENING_DEVICE;
            }
            
            session.addInput(deviceInput);

            let outputData = try self.initializeOutputData(width: width, height: height);
            guard session.canAddOutput(outputData) else {
                print("canAddOutput failed")
                return ERROR_OPENING_DEVICE;
            }

            self.deviceInput = deviceInput;
            self.session = session;

            session.addOutput(outputData);
            session.commitConfiguration();
            session.startRunning();
        } catch {
            print(error)
        }

        return RESULT_OK;
    }

    private func initializeOutputData(width: UInt32, height: UInt32) throws -> AVCaptureVideoDataOutput {
        let outputData: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput();
        outputData.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_24RGB),
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
        ] as [String : Any];
        outputData.alwaysDiscardsLateVideoFrames = true;

        outputData.setSampleBufferDelegate(self, queue: captureSessionQueue);
        self.outputData = outputData;
        return outputData;
    }
}

extension VideoCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    @objc
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer : CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            /// Handle an error. We failed to get image buffer.
            return;
        }

        self.width = UInt32(CVPixelBufferGetWidth(imageBuffer))
        self.height = UInt32(CVPixelBufferGetHeight(imageBuffer))
        self.bytesPerRow = UInt32(CVPixelBufferGetBytesPerRow(imageBuffer))

        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0));
        let size = CVPixelBufferGetDataSize(imageBuffer);

        if (self.buffer == nil) {
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size);
        }
        
        if let baseAddress: UnsafeMutableRawPointer = CVPixelBufferGetBaseAddress(imageBuffer) {
            let source: UnsafeMutablePointer<UInt8> = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            memcpy(self.buffer, source, size);
            
            self.hasFrame = true;
        } else {
            // `baseAddress` is `nil`
            // NOOP
        }

        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0));
    }
}
