#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#import "videocapture_avfoundation.h"

static const int32_t RESULT_OK = 0;
static const int32_t ERROR_DEVICE_NOT_FOUND = -1;
static const int32_t ERROR_FORMAT_NOT_FOUND = -2;
static const int32_t ERROR_OPENING_DEVICE = -3;
static const int32_t ERROR_SESSION_ALREADY_STARTED = -4;
static const int32_t ERROR_SESSION_NOT_STARTED = -5;
static const int32_t ERROR_INVALID_ARGUMENT = -7;
static const int32_t STATUS_AUTHORIZED = 0;
static const int32_t STATUS_NOT_DETERMINED = -2;
static const int32_t STATUS_DENIED = -1;

@interface VCAVFVideoFormat : NSObject
@property(nonatomic, assign, readonly) uint32_t width;
@property(nonatomic, assign, readonly) uint32_t height;
@property(nonatomic, assign, readonly) double frameRate;
@property(nonatomic, copy, readonly) NSString *type;
- (instancetype)initWithWidth:(uint32_t)width
                        height:(uint32_t)height
                     frameRate:(double)frameRate
                          type:(NSString *)type;
@end

@implementation VCAVFVideoFormat
- (instancetype)initWithWidth:(uint32_t)width
                        height:(uint32_t)height
                     frameRate:(double)frameRate
                          type:(NSString *)type {
    self = [super init];
    if (self != nil) {
        _width = width;
        _height = height;
        _frameRate = frameRate;
        _type = [type copy];
    }
    return self;
}
@end

@interface VCAVFVideoDevice : NSObject
@property(nonatomic, copy, readonly) NSString *uniqueId;
@property(nonatomic, copy, readonly) NSString *modelId;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *deviceType;
@property(nonatomic, copy, readonly) NSArray<VCAVFVideoFormat *> *formats;
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                          modelId:(NSString *)modelId
                             name:(NSString *)name
                       deviceType:(NSString *)deviceType
                          formats:(NSArray<VCAVFVideoFormat *> *)formats;
@end

@implementation VCAVFVideoDevice
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                          modelId:(NSString *)modelId
                             name:(NSString *)name
                       deviceType:(NSString *)deviceType
                          formats:(NSArray<VCAVFVideoFormat *> *)formats {
    self = [super init];
    if (self != nil) {
        _uniqueId = [uniqueId copy];
        _modelId = [modelId copy];
        _name = [name copy];
        _deviceType = [deviceType copy];
        _formats = [formats copy];
    }
    return self;
}
@end

@interface VCAVFVideoCaptureSession : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
- (int32_t)startCaptureWithDeviceIndex:(uint32_t)deviceIndex
                              uniqueId:(NSString *)uniqueId
                           formatIndex:(NSInteger)formatIndex
                                 width:(uint32_t)width
                                height:(uint32_t)height
                            outputMode:(int32_t)outputMode;
- (int32_t)stopCapture;
- (BOOL)hasFrame;
- (BOOL)grabFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes;
- (BOOL)grabFrameBgraTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes;
- (BOOL)grabNativeFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes;
- (int32_t)setFrameCallback:(vcavf_frame_callback)callback
                    userData:(void *)userData
                   exclusive:(BOOL)exclusive;
- (uint32_t)width;
- (uint32_t)height;
- (uint32_t)bytesPerRow;
- (uint32_t)dataSize;
- (int32_t)pixelFormat;
- (uint32_t)planeCount;
- (uint32_t)planeOffset:(uint32_t)planeIndex;
- (uint32_t)planeStride:(uint32_t)planeIndex;
@end

static int32_t VCAVFPixelFormatForFourCC(FourCharCode fourcc) {
    switch (fourcc) {
        case kCMPixelFormat_32BGRA:
            return VCAVF_PIXEL_FORMAT_BGRA;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return VCAVF_PIXEL_FORMAT_NV12;
        case kCMPixelFormat_422YpCbCr8_yuvs:
            return VCAVF_PIXEL_FORMAT_YUY2;
        case kCMPixelFormat_422YpCbCr8:
            return VCAVF_PIXEL_FORMAT_UYVY;
        case kCMVideoCodecType_JPEG:
        case kCMVideoCodecType_JPEG_OpenDML:
            return VCAVF_PIXEL_FORMAT_MJPEG;
        case kCMPixelFormat_24RGB:
            return VCAVF_PIXEL_FORMAT_RGB;
        default:
            return -1;
    }
}

static BOOL VCAVFCanDeliverNativeFourCC(FourCharCode fourcc) {
    // The renderer currently interprets NV12 as video-range. Ask AVFoundation
    // to convert full-range NV12 to video-range rather than silently rendering
    // it with the wrong luminance range.
    if (fourcc == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        return NO;
    }
    const int32_t pixelFormat = VCAVFPixelFormatForFourCC(fourcc);
    return pixelFormat == VCAVF_PIXEL_FORMAT_BGRA ||
        pixelFormat == VCAVF_PIXEL_FORMAT_NV12 ||
        pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ||
        pixelFormat == VCAVF_PIXEL_FORMAT_UYVY ||
        pixelFormat == VCAVF_PIXEL_FORMAT_MJPEG;
}

static AVCaptureDeviceFormat *VCAVFDeviceFormatAtVideoIndex(
    AVCaptureDevice *device,
    NSInteger formatIndex) {
    if (device == nil || formatIndex < 0) {
        return nil;
    }

    NSInteger videoIndex = 0;
    for (AVCaptureDeviceFormat *format in device.formats) {
        CMFormatDescriptionRef description = format.formatDescription;
        if (description == NULL ||
            CMFormatDescriptionGetMediaType(description) != kCMMediaType_Video) {
            continue;
        }
        if (videoIndex == formatIndex) {
            return format;
        }
        videoIndex += 1;
    }
    return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSArray<AVCaptureDevice *> *VCAVFVideoDevices(void) {
    NSMutableArray<AVCaptureDeviceType> *deviceTypes = [[NSMutableArray alloc] initWithObjects:
        AVCaptureDeviceTypeBuiltInWideAngleCamera, nil];
    if (@available(macOS 14.0, *)) {
        [deviceTypes addObject:AVCaptureDeviceTypeExternal];
    } else {
        [deviceTypes addObject:AVCaptureDeviceTypeExternalUnknown];
    }
    if (@available(macOS 13.0, *)) {
        [deviceTypes addObject:AVCaptureDeviceTypeDeskViewCamera];
    }
    AVCaptureDeviceDiscoverySession *discovery =
        [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:deviceTypes
                               mediaType:AVMediaTypeVideo
                                position:AVCaptureDevicePositionUnspecified];
    return discovery.devices;
}
#pragma clang diagnostic pop

static uint8_t VCAVFClampByte(int value) {
    return (uint8_t)(value < 0 ? 0 : (value > 255 ? 255 : value));
}

static void VCAVFYuvToBgra(
    uint8_t y,
    uint8_t u,
    uint8_t v,
    BOOL useBt709,
    uint8_t *destination) {
    const int c = MAX(0, (int)y - 16);
    const int d = (int)u - 128;
    const int e = (int)v - 128;
    const int red = useBt709
        ? (298 * c + 459 * e + 128) >> 8
        : (298 * c + 409 * e + 128) >> 8;
    const int green = useBt709
        ? (298 * c - 55 * d - 136 * e + 128) >> 8
        : (298 * c - 100 * d - 208 * e + 128) >> 8;
    const int blue = useBt709
        ? (298 * c + 541 * d + 128) >> 8
        : (298 * c + 516 * d + 128) >> 8;
    destination[0] = VCAVFClampByte(blue);
    destination[1] = VCAVFClampByte(green);
    destination[2] = VCAVFClampByte(red);
    destination[3] = 0xff;
}

@implementation VCAVFVideoCaptureSession {
    dispatch_queue_t _captureSessionQueue;
    dispatch_semaphore_t _semaphore;

    AVCaptureDeviceInput *_deviceInput;
    AVCaptureSession *_session;
    AVCaptureVideoDataOutput *_outputData;

    CMSampleBufferRef _latestSampleBuffer;

    BOOL _hasFrame;
    uint32_t _deviceIndex;
    uint32_t _width;
    uint32_t _height;
    uint32_t _bytesPerRow;
    uint32_t _dataSize;
    int32_t _pixelFormat;
    uint32_t _planeCount;
    uint32_t _planeOffsets[2];
    uint32_t _planeStrides[2];
    vcavf_frame_callback _frameCallback;
    void *_frameCallbackUserData;
    NSMutableData *_compressedScratch;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _captureSessionQueue = dispatch_queue_create("CameraSessionQueue", DISPATCH_QUEUE_SERIAL);
        _semaphore = dispatch_semaphore_create(1);
        _latestSampleBuffer = NULL;
        _pixelFormat = VCAVF_PIXEL_FORMAT_RGB;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(captureSessionRuntimeError)
                                                     name:AVCaptureSessionRuntimeErrorNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_latestSampleBuffer != NULL) {
        CFRelease(_latestSampleBuffer);
        _latestSampleBuffer = NULL;
    }
}

- (void)captureSessionRuntimeError {
    NSLog(@"captureSessionRuntimeError");
}

- (AVCaptureVideoDataOutput *)initializeOutputDataWithWidth:(uint32_t)width
                                                     height:(uint32_t)height
                                             sourceFourCC:(FourCharCode)sourceFourCC
                                                outputMode:(int32_t)outputMode {
    AVCaptureVideoDataOutput *outputData = [[AVCaptureVideoDataOutput alloc] init];
    if (outputMode == VCAVF_OUTPUT_NATIVE && VCAVFCanDeliverNativeFourCC(sourceFourCC)) {
        if (VCAVFPixelFormatForFourCC(sourceFourCC) == VCAVF_PIXEL_FORMAT_MJPEG) {
            // Compressed video output is supported on macOS. Keep JPEG
            // compressed while pinning the output to the selected dimensions.
            outputData.videoSettings = @{
                AVVideoCodecKey : AVVideoCodecTypeJPEG,
                AVVideoWidthKey : @(width),
                AVVideoHeightKey : @(height),
            };
        } else {
            // Explicit dimensions are required on macOS for nonstandard and
            // portrait formats; an empty native-settings dictionary may let
            // the session choose its default (commonly 1920x1080).
            outputData.videoSettings = @{
                (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(sourceFourCC),
                (__bridge NSString *)kCVPixelBufferWidthKey : @(width),
                (__bridge NSString *)kCVPixelBufferHeightKey : @(height),
            };
        }
    } else if (outputMode == VCAVF_OUTPUT_NATIVE) {
        // Use NV12 for native formats that the renderer cannot consume (for
        // example H.264). This keeps color conversion out of the app process.
        outputData.videoSettings = @{
            (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey :
                @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (__bridge NSString *)kCVPixelBufferWidthKey : @(width),
            (__bridge NSString *)kCVPixelBufferHeightKey : @(height),
        };
    } else {
        outputData.videoSettings = @{
            (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_24RGB),
            (__bridge NSString *)kCVPixelBufferWidthKey : @(width),
            (__bridge NSString *)kCVPixelBufferHeightKey : @(height),
        };
    }
    outputData.alwaysDiscardsLateVideoFrames = YES;
    [outputData setSampleBufferDelegate:self queue:_captureSessionQueue];
    return outputData;
}

- (void)setExpectedLayoutForPixelFormat:(int32_t)pixelFormat
                                  width:(uint32_t)width
                                 height:(uint32_t)height {
    _width = width;
    _height = height;
    _pixelFormat = pixelFormat;
    _planeOffsets[0] = 0;
    _planeOffsets[1] = 0;
    _planeStrides[0] = 0;
    _planeStrides[1] = 0;

    switch (pixelFormat) {
        case VCAVF_PIXEL_FORMAT_BGRA:
            _bytesPerRow = width * 4;
            _dataSize = _bytesPerRow * height;
            _planeCount = 1;
            _planeStrides[0] = _bytesPerRow;
            break;
        case VCAVF_PIXEL_FORMAT_NV12:
            _bytesPerRow = width;
            _planeCount = 2;
            _planeOffsets[1] = width * height;
            _planeStrides[0] = width;
            _planeStrides[1] = width;
            _dataSize = width * height + width * (height / 2);
            break;
        case VCAVF_PIXEL_FORMAT_YUY2:
        case VCAVF_PIXEL_FORMAT_UYVY:
            _bytesPerRow = width * 2;
            _dataSize = _bytesPerRow * height;
            _planeCount = 1;
            _planeStrides[0] = _bytesPerRow;
            break;
        case VCAVF_PIXEL_FORMAT_MJPEG: {
            _bytesPerRow = 0;
            _planeCount = 1;
            _planeStrides[0] = 0;
            const uint64_t conservativeSize = (uint64_t)width * (uint64_t)height * 4u;
            _dataSize = (uint32_t)MIN(conservativeSize, (uint64_t)UINT32_MAX);
            break;
        }
        default:
            _pixelFormat = VCAVF_PIXEL_FORMAT_RGB;
            _bytesPerRow = width * 3;
            _dataSize = _bytesPerRow * height;
            _planeCount = 1;
            _planeStrides[0] = _bytesPerRow;
            break;
    }
}

- (int32_t)startCaptureWithDeviceIndex:(uint32_t)deviceIndex
                              uniqueId:(NSString *)uniqueId
                           formatIndex:(NSInteger)formatIndex
                                 width:(uint32_t)width
                                height:(uint32_t)height
                            outputMode:(int32_t)outputMode {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    if (_session != nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_SESSION_ALREADY_STARTED;
    }

    NSArray<AVCaptureDevice *> *devices = VCAVFVideoDevices();
    AVCaptureDevice *device = nil;
    for (AVCaptureDevice *candidate in devices) {
        if ([candidate.uniqueID isEqualToString:uniqueId]) {
            device = candidate;
            break;
        }
    }

    if (device == nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_DEVICE_NOT_FOUND;
    }

    AVCaptureDeviceFormat *selectedFormat =
        VCAVFDeviceFormatAtVideoIndex(device, formatIndex);
    if (selectedFormat == nil) {
        for (AVCaptureDeviceFormat *candidateFormat in device.formats) {
            CMFormatDescriptionRef description = candidateFormat.formatDescription;
            if (description == NULL ||
                CMFormatDescriptionGetMediaType(description) != kCMMediaType_Video) {
                continue;
            }
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(description);
            if ((uint32_t)dimensions.width == width && (uint32_t)dimensions.height == height) {
                selectedFormat = candidateFormat;
                break;
            }
        }
    }

    if (selectedFormat == nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_FORMAT_NOT_FOUND;
    }

    CMFormatDescriptionRef selectedDescription = selectedFormat.formatDescription;
    CMVideoDimensions selectedDimensions =
        CMVideoFormatDescriptionGetDimensions(selectedDescription);
    width = (uint32_t)selectedDimensions.width;
    height = (uint32_t)selectedDimensions.height;
    FourCharCode sourceFourCC = CMFormatDescriptionGetMediaSubType(selectedDescription);

    NSError *inputError = nil;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
    if (deviceInput == nil || inputError != nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_OPENING_DEVICE;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];

    if (![session canAddInput:deviceInput]) {
        [session commitConfiguration];
        dispatch_semaphore_signal(_semaphore);
        return ERROR_OPENING_DEVICE;
    }

    [session addInput:deviceInput];

    // Configure the device while the owning session is between
    // beginConfiguration/commitConfiguration. Otherwise macOS may replace the
    // requested format with the session's default preset when inputs are added.
    NSError *configurationError = nil;
    if (![device lockForConfiguration:&configurationError] || configurationError != nil) {
        [session commitConfiguration];
        dispatch_semaphore_signal(_semaphore);
        return ERROR_OPENING_DEVICE;
    }
    device.activeFormat = selectedFormat;
    AVFrameRateRange *bestRange = nil;
    for (AVFrameRateRange *range in selectedFormat.videoSupportedFrameRateRanges) {
        if (bestRange == nil || range.maxFrameRate > bestRange.maxFrameRate) {
            bestRange = range;
        }
    }
    if (bestRange != nil && bestRange.maxFrameRate > 0.0) {
        // Use AVFoundation's exact advertised duration. Reconstructing it from
        // the floating-point frame rate can round just outside the supported
        // range and raises an Objective-C exception on some built-in cameras.
        CMTime duration = bestRange.minFrameDuration;
        if (CMTIME_IS_VALID(duration) && duration.value > 0) {
            device.activeVideoMinFrameDuration = duration;
            device.activeVideoMaxFrameDuration = duration;
        }
    }
    [device unlockForConfiguration];

    AVCaptureVideoDataOutput *outputData =
        [self initializeOutputDataWithWidth:width
                                    height:height
                              sourceFourCC:sourceFourCC
                                 outputMode:outputMode];
    if (outputData == nil || ![session canAddOutput:outputData]) {
        [session commitConfiguration];
        dispatch_semaphore_signal(_semaphore);
        return ERROR_OPENING_DEVICE;
    }

    _deviceInput = deviceInput;
    _session = session;
    _outputData = outputData;
    _deviceIndex = deviceIndex;
    int32_t expectedPixelFormat = VCAVF_PIXEL_FORMAT_RGB;
    if (outputMode == VCAVF_OUTPUT_NATIVE) {
        expectedPixelFormat = VCAVFPixelFormatForFourCC(sourceFourCC);
        if (!VCAVFCanDeliverNativeFourCC(sourceFourCC)) {
            expectedPixelFormat = VCAVF_PIXEL_FORMAT_NV12;
        }
    }
    [self setExpectedLayoutForPixelFormat:expectedPixelFormat width:width height:height];

    [session addOutput:outputData];
    [session commitConfiguration];
    [session startRunning];

    dispatch_semaphore_signal(_semaphore);
    return RESULT_OK;
}

- (int32_t)stopCapture {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    if (_session == nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_SESSION_NOT_STARTED;
    }

    AVCaptureSession *session = _session;
    AVCaptureVideoDataOutput *outputData = _outputData;
    _frameCallback = NULL;
    _frameCallbackUserData = NULL;
    _deviceInput = nil;
    _outputData = nil;
    _session = nil;
    dispatch_semaphore_signal(_semaphore);

    [outputData setSampleBufferDelegate:nil queue:NULL];
    [session stopRunning];

    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (_latestSampleBuffer != NULL) {
        CFRelease(_latestSampleBuffer);
        _latestSampleBuffer = NULL;
    }
    _hasFrame = NO;
    _deviceIndex = 0;
    _width = 0;
    _height = 0;
    _bytesPerRow = 0;
    _dataSize = 0;
    _pixelFormat = VCAVF_PIXEL_FORMAT_RGB;
    _planeCount = 0;
    memset(_planeOffsets, 0, sizeof(_planeOffsets));
    memset(_planeStrides, 0, sizeof(_planeStrides));
    _compressedScratch = nil;

    dispatch_semaphore_signal(_semaphore);
    return RESULT_OK;
}

- (BOOL)hasFrame {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL hasFrame = _hasFrame;
    dispatch_semaphore_signal(_semaphore);
    return hasFrame;
}

- (CMSampleBufferRef)copyLatestSampleBuffer {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    CMSampleBufferRef sampleBuffer = _latestSampleBuffer;
    if (sampleBuffer != NULL) {
        CFRetain(sampleBuffer);
    }
    dispatch_semaphore_signal(_semaphore);
    return sampleBuffer;
}

- (BOOL)copyNativeSample:(CMSampleBufferRef)sampleBuffer
                      to:(uint8_t *)dst
          availableBytes:(uint32_t)availableBytes {
    if (sampleBuffer == NULL || dst == NULL) {
        return NO;
    }

    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer == NULL) {
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        if (blockBuffer == NULL) {
            return NO;
        }
        size_t dataSize = CMBlockBufferGetDataLength(blockBuffer);
        if (dataSize == 0 || dataSize > availableBytes) {
            return NO;
        }
        return CMBlockBufferCopyDataBytes(blockBuffer, 0, dataSize, dst) == kCMBlockBufferNoErr;
    }

    const uint32_t width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
    const uint32_t height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
    const int32_t pixelFormat =
        VCAVFPixelFormatForFourCC(CVPixelBufferGetPixelFormatType(imageBuffer));
    size_t required = 0;
    if (pixelFormat == VCAVF_PIXEL_FORMAT_NV12) {
        if (!CVPixelBufferIsPlanar(imageBuffer) || CVPixelBufferGetPlaneCount(imageBuffer) < 2) {
            return NO;
        }
        required = (size_t)width * height + (size_t)width * (height / 2);
    } else if (pixelFormat == VCAVF_PIXEL_FORMAT_BGRA) {
        required = (size_t)width * height * 4u;
    } else if (pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ||
               pixelFormat == VCAVF_PIXEL_FORMAT_UYVY) {
        required = (size_t)width * height * 2u;
    } else if (pixelFormat == VCAVF_PIXEL_FORMAT_RGB) {
        required = (size_t)width * height * 3u;
    } else {
        return NO;
    }
    if (required > availableBytes) {
        return NO;
    }

    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    if (pixelFormat == VCAVF_PIXEL_FORMAT_NV12 && CVPixelBufferIsPlanar(imageBuffer)) {
        size_t destinationOffset = 0;
        for (size_t plane = 0; plane < MIN((size_t)2, CVPixelBufferGetPlaneCount(imageBuffer)); plane++) {
            const size_t rows = plane == 0 ? height : height / 2;
            const size_t rowBytes = width;
            const size_t sourceStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, plane);
            const uint8_t *source = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, plane);
            if (source == NULL || sourceStride < rowBytes) {
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                return NO;
            }
            for (size_t row = 0; row < rows; row++) {
                memcpy(dst + destinationOffset + row * rowBytes,
                       source + row * sourceStride,
                       rowBytes);
            }
            destinationOffset += rowBytes * rows;
        }
    } else {
        const size_t rowBytes = pixelFormat == VCAVF_PIXEL_FORMAT_BGRA
            ? (size_t)width * 4u
            : (pixelFormat == VCAVF_PIXEL_FORMAT_RGB
                ? (size_t)width * 3u
                : (size_t)width * 2u);
        const size_t sourceStride = CVPixelBufferGetBytesPerRow(imageBuffer);
        const uint8_t *source = CVPixelBufferGetBaseAddress(imageBuffer);
        if (source == NULL || sourceStride < rowBytes) {
            CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
            return NO;
        }
        for (size_t row = 0; row < height; row++) {
            memcpy(dst + row * rowBytes, source + row * sourceStride, rowBytes);
        }
    }
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    return YES;
}

- (BOOL)grabNativeFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes {
    CMSampleBufferRef sampleBuffer = [self copyLatestSampleBuffer];
    if (sampleBuffer == NULL) {
        return NO;
    }
    BOOL result = [self copyNativeSample:sampleBuffer to:dst availableBytes:availableBytes];
    CFRelease(sampleBuffer);
    return result;
}

- (BOOL)copySample:(CMSampleBufferRef)sampleBuffer
          asBgraTo:(uint8_t *)dst
    availableBytes:(uint32_t)availableBytes {
    if (sampleBuffer == NULL || dst == NULL) {
        return NO;
    }

    CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sampleBuffer);
    const uint32_t width = description == NULL
        ? 0
        : (uint32_t)CMVideoFormatDescriptionGetDimensions(description).width;
    const uint32_t height = description == NULL
        ? 0
        : (uint32_t)CMVideoFormatDescriptionGetDimensions(description).height;
    const size_t required = (size_t)width * height * 4u;
    if (width == 0 || height == 0 || required > availableBytes) {
        return NO;
    }

    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer == NULL) {
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        if (blockBuffer == NULL) {
            return NO;
        }
        const size_t jpegSize = CMBlockBufferGetDataLength(blockBuffer);
        NSMutableData *jpegData = [NSMutableData dataWithLength:jpegSize];
        if (jpegSize == 0 ||
            CMBlockBufferCopyDataBytes(blockBuffer, 0, jpegSize, jpegData.mutableBytes) !=
                kCMBlockBufferNoErr) {
            return NO;
        }
        CGImageSourceRef source = CGImageSourceCreateWithData(
            (__bridge CFDataRef)jpegData, NULL);
        if (source == NULL) {
            return NO;
        }
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (image == NULL) {
            return NO;
        }
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(
            dst,
            width,
            height,
            8,
            width * 4,
            colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(colorSpace);
        if (context == NULL) {
            CGImageRelease(image);
            return NO;
        }
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRelease(context);
        CGImageRelease(image);
        return YES;
    }

    const FourCharCode fourcc = CVPixelBufferGetPixelFormatType(imageBuffer);
    const int32_t pixelFormat = VCAVFPixelFormatForFourCC(fourcc);
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    BOOL result = YES;
    if (pixelFormat == VCAVF_PIXEL_FORMAT_NV12 && CVPixelBufferIsPlanar(imageBuffer)) {
        const uint8_t *sourceY = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        const uint8_t *sourceUv = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
        vImage_Buffer yBuffer = {
            .data = (void *)sourceY,
            .height = height,
            .width = width,
            .rowBytes = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0),
        };
        vImage_Buffer uvBuffer = {
            .data = (void *)sourceUv,
            .height = height / 2,
            .width = width / 2,
            .rowBytes = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1),
        };
        vImage_Buffer destination = {
            .data = dst,
            .height = height,
            .width = width,
            .rowBytes = width * 4,
        };
        const vImage_YpCbCrPixelRange videoRange =
            { 16, 128, 235, 240, 255, 0, 255, 1 };
        const vImage_YpCbCrPixelRange fullRange =
            { 0, 128, 255, 255, 255, 1, 255, 0 };
        const vImage_YpCbCrPixelRange *range =
            fourcc == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ? &fullRange
                : &videoRange;
        CFTypeRef matrixAttachment = CVBufferGetAttachment(
            imageBuffer,
            kCVImageBufferYCbCrMatrixKey,
            NULL);
        const vImage_YpCbCrToARGBMatrix *matrix =
            matrixAttachment != NULL &&
                CFEqual(matrixAttachment, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
                ? kvImage_YpCbCrToARGBMatrix_ITU_R_709_2
                : kvImage_YpCbCrToARGBMatrix_ITU_R_601_4;
        vImage_YpCbCrToARGB conversion;
        const uint8_t permuteMap[4] = { 3, 2, 1, 0 };
        result = sourceY != NULL && sourceUv != NULL &&
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                matrix,
                range,
                &conversion,
                kvImage420Yp8_CbCr8,
                kvImageARGB8888,
                kvImageNoFlags) == kvImageNoError &&
            vImageConvert_420Yp8_CbCr8ToARGB8888(
                &yBuffer,
                &uvBuffer,
                &destination,
                &conversion,
                permuteMap,
                255,
                kvImageNoFlags) == kvImageNoError;
    } else {
        const uint8_t *source = CVPixelBufferGetBaseAddress(imageBuffer);
        const size_t sourceStride = CVPixelBufferGetBytesPerRow(imageBuffer);
        if (source == NULL) {
            result = NO;
        } else if (pixelFormat == VCAVF_PIXEL_FORMAT_BGRA) {
            for (size_t row = 0; row < height; row++) {
                memcpy(dst + row * width * 4u, source + row * sourceStride, width * 4u);
            }
        } else if (pixelFormat == VCAVF_PIXEL_FORMAT_RGB) {
            for (size_t row = 0; row < height; row++) {
                const uint8_t *sourceRow = source + row * sourceStride;
                uint8_t *destination = dst + row * width * 4u;
                for (size_t column = 0; column < width; column++) {
                    destination[column * 4u] = sourceRow[column * 3u + 2u];
                    destination[column * 4u + 1u] = sourceRow[column * 3u + 1u];
                    destination[column * 4u + 2u] = sourceRow[column * 3u];
                    destination[column * 4u + 3u] = 0xff;
                }
            }
        } else if (pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ||
                   pixelFormat == VCAVF_PIXEL_FORMAT_UYVY) {
            if ((width & 1u) != 0) {
                result = NO;
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                return result;
            }
            const BOOL useBt709 = width >= 1280;
            for (size_t row = 0; row < height; row++) {
                const uint8_t *sourceRow = source + row * sourceStride;
                uint8_t *destination = dst + row * width * 4u;
                for (size_t column = 0; column < width; column += 2) {
                    const uint8_t *pair = sourceRow + column * 2u;
                    const uint8_t y0 = pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ? pair[0] : pair[1];
                    const uint8_t u = pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ? pair[1] : pair[0];
                    const uint8_t y1 = pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ? pair[2] : pair[3];
                    const uint8_t v = pixelFormat == VCAVF_PIXEL_FORMAT_YUY2 ? pair[3] : pair[2];
                    VCAVFYuvToBgra(y0, u, v, useBt709, destination + column * 4u);
                    VCAVFYuvToBgra(y1, u, v, useBt709, destination + (column + 1u) * 4u);
                }
            }
        } else {
            result = NO;
        }
    }
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    return result;
}

- (BOOL)grabFrameBgraTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes {
    CMSampleBufferRef sampleBuffer = [self copyLatestSampleBuffer];
    if (sampleBuffer == NULL) {
        return NO;
    }
    BOOL result = [self copySample:sampleBuffer asBgraTo:dst availableBytes:availableBytes];
    CFRelease(sampleBuffer);
    return result;
}

- (BOOL)grabFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes {
    const uint32_t width = [self width];
    const uint32_t height = [self height];
    const size_t rgbBytes = (size_t)width * height * 3u;
    const size_t bgraBytes = (size_t)width * height * 4u;
    if (dst == NULL || rgbBytes > availableBytes || bgraBytes > UINT32_MAX) {
        return NO;
    }

    CMSampleBufferRef sampleBuffer = [self copyLatestSampleBuffer];
    if (sampleBuffer == NULL) {
        return NO;
    }
    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer != NULL &&
        VCAVFPixelFormatForFourCC(CVPixelBufferGetPixelFormatType(imageBuffer)) ==
            VCAVF_PIXEL_FORMAT_RGB) {
        BOOL copied = [self copyNativeSample:sampleBuffer
                                          to:dst
                              availableBytes:availableBytes];
        CFRelease(sampleBuffer);
        return copied;
    }
    NSMutableData *bgra = [NSMutableData dataWithLength:bgraBytes];
    BOOL converted = [self copySample:sampleBuffer
                             asBgraTo:bgra.mutableBytes
                       availableBytes:(uint32_t)bgraBytes];
    CFRelease(sampleBuffer);
    if (!converted) {
        return NO;
    }
    const uint8_t *source = bgra.bytes;
    for (size_t pixel = 0; pixel < (size_t)width * height; pixel++) {
        dst[pixel * 3u] = source[pixel * 4u + 2u];
        dst[pixel * 3u + 1u] = source[pixel * 4u + 1u];
        dst[pixel * 3u + 2u] = source[pixel * 4u];
    }
    return YES;
}

- (int32_t)setFrameCallback:(vcavf_frame_callback)callback
                    userData:(void *)userData
                   exclusive:(BOOL)exclusive {
    (void)exclusive;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (_session == nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_SESSION_NOT_STARTED;
    }
    _frameCallback = callback;
    _frameCallbackUserData = callback == NULL ? NULL : userData;
    dispatch_semaphore_signal(_semaphore);
    return RESULT_OK;
}

- (uint32_t)width {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = _width;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)height {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = _height;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)bytesPerRow {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = _bytesPerRow;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)dataSize {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = _dataSize;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (int32_t)pixelFormat {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    int32_t value = _pixelFormat;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)planeCount {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = _planeCount;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)planeOffset:(uint32_t)planeIndex {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = planeIndex < 2 ? _planeOffsets[planeIndex] : 0;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (uint32_t)planeStride:(uint32_t)planeIndex {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    uint32_t value = planeIndex < 2 ? _planeStrides[planeIndex] : 0;
    dispatch_semaphore_signal(_semaphore);
    return value;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;

    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    if (_session == nil) {
        dispatch_semaphore_signal(_semaphore);
        return;
    }
    if (_latestSampleBuffer != NULL) {
        CFRelease(_latestSampleBuffer);
    }
    _latestSampleBuffer = (CMSampleBufferRef)CFRetain(sampleBuffer);

    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer != NULL) {
        const uint32_t width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
        const uint32_t height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
        const int32_t pixelFormat =
            VCAVFPixelFormatForFourCC(CVPixelBufferGetPixelFormatType(imageBuffer));
        [self setExpectedLayoutForPixelFormat:pixelFormat width:width height:height];
        _hasFrame = YES;

        if (_frameCallback != NULL) {
            CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
            const BOOL planar = CVPixelBufferIsPlanar(imageBuffer);
            const uint32_t planeCount = planar
                ? (uint32_t)MIN((size_t)2, CVPixelBufferGetPlaneCount(imageBuffer))
                : 1;
            const uint8_t *plane0 = planar
                ? CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
                : CVPixelBufferGetBaseAddress(imageBuffer);
            const uint32_t stride0 = (uint32_t)(planar
                ? CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
                : CVPixelBufferGetBytesPerRow(imageBuffer));
            const size_t plane0Bytes = (size_t)stride0 * height;
            const uint8_t *plane1 = planeCount > 1
                ? CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1)
                : NULL;
            const uint32_t stride1 = planeCount > 1
                ? (uint32_t)CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1)
                : 0;
            const size_t plane1Bytes = planeCount > 1
                ? (size_t)stride1 * (height / 2)
                : 0;
            _frameCallback(
                _deviceIndex,
                pixelFormat,
                width,
                height,
                planeCount,
                plane0,
                plane0Bytes,
                stride0,
                plane1,
                plane1Bytes,
                stride1,
                0,
                _frameCallbackUserData);
            CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        }
    } else {
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sampleBuffer);
        FourCharCode fourcc = description == NULL
            ? 0
            : CMFormatDescriptionGetMediaSubType(description);
        CMVideoDimensions dimensions = description == NULL
            ? (CMVideoDimensions){ 0, 0 }
            : CMVideoFormatDescriptionGetDimensions(description);
        const size_t dataSize = blockBuffer == NULL
            ? 0
            : CMBlockBufferGetDataLength(blockBuffer);
        if (VCAVFPixelFormatForFourCC(fourcc) == VCAVF_PIXEL_FORMAT_MJPEG &&
            dimensions.width > 0 && dimensions.height > 0 && dataSize > 0) {
            [self setExpectedLayoutForPixelFormat:VCAVF_PIXEL_FORMAT_MJPEG
                                             width:(uint32_t)dimensions.width
                                            height:(uint32_t)dimensions.height];
            _dataSize = (uint32_t)MIN(dataSize, (size_t)UINT32_MAX);
            _hasFrame = YES;
            if (_frameCallback != NULL) {
                size_t contiguousLength = 0;
                size_t totalLength = 0;
                char *directData = NULL;
                OSStatus status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    0,
                    &contiguousLength,
                    &totalLength,
                    &directData);
                const uint8_t *callbackData = NULL;
                if (status == kCMBlockBufferNoErr && contiguousLength == totalLength) {
                    callbackData = (const uint8_t *)directData;
                } else {
                    if (_compressedScratch == nil || _compressedScratch.length < dataSize) {
                        _compressedScratch = [NSMutableData dataWithLength:dataSize];
                    }
                    if (CMBlockBufferCopyDataBytes(
                            blockBuffer,
                            0,
                            dataSize,
                            _compressedScratch.mutableBytes) == kCMBlockBufferNoErr) {
                        callbackData = _compressedScratch.bytes;
                    }
                }
                if (callbackData != NULL) {
                    _frameCallback(
                        _deviceIndex,
                        VCAVF_PIXEL_FORMAT_MJPEG,
                        _width,
                        _height,
                        1,
                        callbackData,
                        dataSize,
                        0,
                        NULL,
                        0,
                        0,
                        0,
                        _frameCallbackUserData);
                }
            }
        }
    }
    dispatch_semaphore_signal(_semaphore);
}

@end

static NSMutableArray<VCAVFVideoDevice *> *gDevices;
static NSMutableDictionary<NSString *, VCAVFVideoCaptureSession *> *gSessions;

static NSDictionary<NSNumber *, NSString *> *VCAVFFourCCMappings(void) {
    static NSDictionary<NSNumber *, NSString *> *mappings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSNumber *, NSString *> *dict = [[NSMutableDictionary alloc] init];

        dict[@((uint32_t)kCMPixelFormat_32ARGB)] = @"ARGB";
        dict[@((uint32_t)kCMPixelFormat_32BGRA)] = @"BGRA";
        dict[@((uint32_t)kCMPixelFormat_24RGB)] = @"RGB";
        dict[@((uint32_t)kCMPixelFormat_16BE555)] = @"RGB555BE";
        dict[@((uint32_t)kCMPixelFormat_16BE565)] = @"RGB565BE";
        dict[@((uint32_t)kCMPixelFormat_16LE555)] = @"RGB555";
        dict[@((uint32_t)kCMPixelFormat_16LE565)] = @"RGB565";
        dict[@((uint32_t)kCMPixelFormat_16LE5551)] = @"ARGB555";
        dict[@((uint32_t)kCMPixelFormat_422YpCbCr8)] = @"UYVY";
        dict[@((uint32_t)kCMPixelFormat_422YpCbCr8_yuvs)] = @"YUY2";
        dict[@((uint32_t)kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)] = @"NV12";
        dict[@((uint32_t)kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)] = @"NV12";

        dict[@((uint32_t)kCMVideoCodecType_JPEG)] = @"JPEG";
        dict[@((uint32_t)kCMVideoCodecType_JPEG_OpenDML)] = @"MJPG";
        dict[@((uint32_t)kCMVideoCodecType_H263)] = @"H263";
        dict[@((uint32_t)kCMVideoCodecType_H264)] = @"H264";
        dict[@((uint32_t)kCMVideoCodecType_HEVC)] = @"HEVC";
        dict[@((uint32_t)kCMVideoCodecType_MPEG4Video)] = @"MPG4";
        dict[@((uint32_t)kCMVideoCodecType_MPEG2Video)] = @"MPG2";
        dict[@((uint32_t)kCMVideoCodecType_MPEG1Video)] = @"MPG1";

        mappings = [dict copy];
    });

    return mappings;
}

static VCAVFVideoFormat *VCAVFToVideoFormat(AVCaptureDeviceFormat *format) {
    CMFormatDescriptionRef description = format.formatDescription;
    CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(description);
    FourCharCode fourcc = CMFormatDescriptionGetMediaSubType(description);

    NSString *type = VCAVFFourCCMappings()[@((uint32_t)fourcc)];
    if (type == nil) {
        type = [NSString stringWithFormat:@"UNKNOWN_%u", (unsigned int)fourcc];
    }

    double frameRate = 0.0;
    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
        frameRate = MAX(frameRate, range.maxFrameRate);
    }

    return [[VCAVFVideoFormat alloc] initWithWidth:(uint32_t)size.width
                                            height:(uint32_t)size.height
                                         frameRate:frameRate
                                              type:type];
}

static NSArray<VCAVFVideoDevice *> *VCAVFListDevices(void) {
    NSMutableArray<VCAVFVideoDevice *> *cameras = [[NSMutableArray alloc] init];

    NSArray<AVCaptureDevice *> *devices = VCAVFVideoDevices();
    for (AVCaptureDevice *device in devices) {
        NSMutableArray<VCAVFVideoFormat *> *formats = [[NSMutableArray alloc] init];

        for (AVCaptureDeviceFormat *format in device.formats) {
            CMFormatDescriptionRef description = format.formatDescription;
            if (description == NULL || CMFormatDescriptionGetMediaType(description) != kCMMediaType_Video) {
                continue;
            }

            [formats addObject:VCAVFToVideoFormat(format)];
        }

        if (formats.count > 0) {
            VCAVFVideoDevice *camera = [[VCAVFVideoDevice alloc] initWithUniqueId:device.uniqueID
                                                                           modelId:device.modelID
                                                                              name:device.localizedName
                                                                        deviceType:device.deviceType
                                                                           formats:formats];
            [cameras addObject:camera];
        }
    }

    return cameras;
}

static int32_t VCAVFHasVideoCaptureAuthorization(void) {
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

        switch (authStatus) {
            case AVAuthorizationStatusAuthorized:
                return STATUS_AUTHORIZED;
            case AVAuthorizationStatusDenied:
            case AVAuthorizationStatusRestricted:
                return STATUS_DENIED;
            default:
                return STATUS_NOT_DETERMINED;
        }
    }

    return STATUS_AUTHORIZED;
}

static void VCAVFAskVideoCaptureAuthorization(void) {
    if (@available(macOS 10.14, *)) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted) {
                                     if (granted) {
                                         NSLog(@"Video capture authorization granted by user");
                                     } else {
                                         NSLog(@"Video capture authorization rejected by user");
                                     }
                                 }];
    }
}

static void VCAVFCopyString(NSString *s, char *buf, uint32_t length) {
    if (buf == NULL || length == 0) {
        return;
    }

    if (s == nil) {
        buf[0] = '\0';
        return;
    }

    const char *cs = [s UTF8String];
    if (cs == NULL) {
        buf[0] = '\0';
        return;
    }

    strncpy(buf, cs, (size_t)length);
    buf[length - 1] = '\0';
}

static VCAVFVideoDevice *VCAVFDeviceAtIndex(uint32_t deviceIndex) {
    if (gDevices == nil) {
        return nil;
    }

    if (deviceIndex >= gDevices.count) {
        return nil;
    }

    return gDevices[deviceIndex];
}

bool vcavf_initialize(void) {
    @autoreleasepool {
        @try {
            NSArray<VCAVFVideoDevice *> *devices = VCAVFListDevices();
            gDevices = [devices mutableCopy];

            if (gSessions == nil) {
                gSessions = [[NSMutableDictionary alloc] init];
            } else {
                [gSessions removeAllObjects];
            }

            return true;
        } @catch (NSException *exception) {
            (void)exception;
            return false;
        }
    }
}

int32_t vcavf_has_videocapture_auth(void) {
    @autoreleasepool {
        return VCAVFHasVideoCaptureAuthorization();
    }
}

void vcavf_ask_videocapture_auth(void) {
    @autoreleasepool {
        VCAVFAskVideoCaptureAuthorization();
    }
}

uint32_t vcavf_devices_count(void) {
    @autoreleasepool {
        if (gDevices == nil) {
            return 0;
        }

        return (uint32_t)gDevices.count;
    }
}

void vcavf_get_device_unique_id(uint32_t deviceIndex, char *buf, uint32_t length) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return;
        }

        VCAVFCopyString(device.uniqueId, buf, length);
    }
}

void vcavf_get_device_model_id(uint32_t deviceIndex, char *buf, uint32_t length) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return;
        }

        VCAVFCopyString(device.modelId, buf, length);
    }
}

void vcavf_get_device_name(uint32_t deviceIndex, char *buf, uint32_t length) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return;
        }

        VCAVFCopyString(device.name, buf, length);
    }
}

void vcavf_get_device_type(uint32_t deviceIndex, char *buf, uint32_t length) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return;
        }

        VCAVFCopyString(device.deviceType, buf, length);
    }
}

uint32_t vcavf_get_device_formats_count(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return 0;
        }

        return (uint32_t)device.formats.count;
    }
}

void vcavf_get_device_format(uint32_t deviceIndex, uint32_t formatIndex, char *buf, uint32_t length) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil || formatIndex >= device.formats.count) {
            return;
        }

        VCAVFVideoFormat *format = device.formats[formatIndex];
        NSString *formatString = [NSString stringWithFormat:
            @"%ux%u;%@;%.3f fps",
            format.width,
            format.height,
            format.type,
            format.frameRate];
        VCAVFCopyString(formatString, buf, length);
    }
}

static int32_t VCAVFStartCapture(
    uint32_t deviceIndex,
    NSInteger formatIndex,
    uint32_t width,
    uint32_t height,
    int32_t outputMode) {
    VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
    if (device == nil) {
        return ERROR_DEVICE_NOT_FOUND;
    }
    if (outputMode != VCAVF_OUTPUT_RGB && outputMode != VCAVF_OUTPUT_NATIVE) {
        return ERROR_INVALID_ARGUMENT;
    }
    if (formatIndex >= (NSInteger)device.formats.count) {
        return ERROR_FORMAT_NOT_FOUND;
    }

    if (gSessions == nil) {
        gSessions = [[NSMutableDictionary alloc] init];
    }
    VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
    if (session != nil) {
        return RESULT_OK;
    }

    session = [[VCAVFVideoCaptureSession alloc] init];
    gSessions[device.uniqueId] = session;
    int32_t result = [session startCaptureWithDeviceIndex:deviceIndex
                                                uniqueId:device.uniqueId
                                             formatIndex:formatIndex
                                                   width:width
                                                  height:height
                                              outputMode:outputMode];
    if (result != RESULT_OK) {
        [gSessions removeObjectForKey:device.uniqueId];
    }
    return result;
}

int32_t vcavf_start_capture(uint32_t deviceIndex, uint32_t width, uint32_t height) {
    @autoreleasepool {
        return VCAVFStartCapture(
            deviceIndex,
            -1,
            width,
            height,
            VCAVF_OUTPUT_RGB);
    }
}

int32_t vcavf_start_capture_with_format_output(
    uint32_t deviceIndex,
    uint32_t formatIndex,
    int32_t outputMode) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return ERROR_DEVICE_NOT_FOUND;
        }
        if (formatIndex >= device.formats.count) {
            return ERROR_FORMAT_NOT_FOUND;
        }
        VCAVFVideoFormat *format = device.formats[formatIndex];
        return VCAVFStartCapture(
            deviceIndex,
            (NSInteger)formatIndex,
            format.width,
            format.height,
            outputMode);
    }
}

int32_t vcavf_stop_capture(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return ERROR_DEVICE_NOT_FOUND;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return ERROR_SESSION_NOT_STARTED;
        }

        [gSessions removeObjectForKey:device.uniqueId];
        return [session stopCapture];
    }
}

bool vcavf_has_new_frame(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return false;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return false;
        }

        return [session hasFrame];
    }
}

bool vcavf_grab_frame(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return false;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return false;
        }

        return [session grabFrameTo:buffer availableBytes:availableBytes];
    }
}

bool vcavf_grab_frame_native(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session != nil &&
            [session grabNativeFrameTo:buffer availableBytes:availableBytes];
    }
}

bool vcavf_grab_frame_bgra(uint32_t deviceIndex, uint8_t *buffer, uint32_t availableBytes) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session != nil &&
            [session grabFrameBgraTo:buffer availableBytes:availableBytes];
    }
}

int32_t vcavf_set_frame_callback(
    uint32_t deviceIndex,
    vcavf_frame_callback callback,
    void *userData,
    bool exclusive) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return ERROR_DEVICE_NOT_FOUND;
        }
        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return ERROR_SESSION_NOT_STARTED;
        }
        return [session setFrameCallback:callback
                                userData:userData
                               exclusive:exclusive ? YES : NO];
    }
}

uint32_t vcavf_frame_width(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return 0;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return 0;
        }

        return [session width];
    }
}

uint32_t vcavf_frame_height(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return 0;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return 0;
        }

        return [session height];
    }
}

uint32_t vcavf_frame_bytes_per_row(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return 0;
        }

        VCAVFVideoCaptureSession *session = gSessions[device.uniqueId];
        if (session == nil) {
            return 0;
        }

        return [session bytesPerRow];
    }
}

uint32_t vcavf_frame_data_size(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session == nil ? 0 : [session dataSize];
    }
}

int32_t vcavf_frame_pixel_format(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session == nil ? -1 : [session pixelFormat];
    }
}

uint32_t vcavf_frame_plane_count(uint32_t deviceIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session == nil ? 0 : [session planeCount];
    }
}

uint32_t vcavf_frame_plane_offset(uint32_t deviceIndex, uint32_t planeIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session == nil ? 0 : [session planeOffset:planeIndex];
    }
}

uint32_t vcavf_frame_plane_stride(uint32_t deviceIndex, uint32_t planeIndex) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        VCAVFVideoCaptureSession *session =
            device == nil ? nil : gSessions[device.uniqueId];
        return session == nil ? 0 : [session planeStride:planeIndex];
    }
}
