#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
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
static const int32_t STATUS_AUTHORIZED = 0;
static const int32_t STATUS_NOT_DETERMINED = -2;
static const int32_t STATUS_DENIED = -1;

@interface VCAVFVideoFormat : NSObject
@property(nonatomic, assign, readonly) uint32_t width;
@property(nonatomic, assign, readonly) uint32_t height;
@property(nonatomic, copy, readonly) NSString *type;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height type:(NSString *)type;
@end

@implementation VCAVFVideoFormat
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height type:(NSString *)type {
    self = [super init];
    if (self != nil) {
        _width = width;
        _height = height;
        _type = [type copy];
    }
    return self;
}
@end

@interface VCAVFVideoDevice : NSObject
@property(nonatomic, copy, readonly) NSString *uniqueId;
@property(nonatomic, copy, readonly) NSString *modelId;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSArray<VCAVFVideoFormat *> *formats;
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                          modelId:(NSString *)modelId
                             name:(NSString *)name
                          formats:(NSArray<VCAVFVideoFormat *> *)formats;
@end

@implementation VCAVFVideoDevice
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                          modelId:(NSString *)modelId
                             name:(NSString *)name
                          formats:(NSArray<VCAVFVideoFormat *> *)formats {
    self = [super init];
    if (self != nil) {
        _uniqueId = [uniqueId copy];
        _modelId = [modelId copy];
        _name = [name copy];
        _formats = [formats copy];
    }
    return self;
}
@end

@interface VCAVFVideoCaptureSession : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
- (int32_t)startCaptureWithUniqueId:(NSString *)uniqueId width:(uint32_t)width height:(uint32_t)height;
- (int32_t)stopCapture;
- (BOOL)hasFrame;
- (BOOL)grabFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes;
- (uint32_t)width;
- (uint32_t)height;
- (uint32_t)bytesPerRow;
@end

@implementation VCAVFVideoCaptureSession {
    dispatch_queue_t _captureSessionQueue;
    dispatch_semaphore_t _semaphore;

    AVCaptureDeviceInput *_deviceInput;
    AVCaptureSession *_session;
    AVCaptureVideoDataOutput *_outputData;

    uint8_t *_buffer;
    size_t _bufferSize;

    BOOL _hasFrame;
    uint32_t _width;
    uint32_t _height;
    uint32_t _bytesPerRow;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _captureSessionQueue = dispatch_queue_create("CameraSessionQueue", DISPATCH_QUEUE_SERIAL);
        _semaphore = dispatch_semaphore_create(1);
        _buffer = NULL;
        _bufferSize = 0;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(captureSessionRuntimeError)
                                                     name:AVCaptureSessionRuntimeErrorNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_buffer != NULL) {
        free(_buffer);
        _buffer = NULL;
    }
}

- (void)captureSessionRuntimeError {
    NSLog(@"captureSessionRuntimeError");
}

- (AVCaptureVideoDataOutput *)initializeOutputDataWithWidth:(uint32_t)width height:(uint32_t)height {
    AVCaptureVideoDataOutput *outputData = [[AVCaptureVideoDataOutput alloc] init];
    outputData.videoSettings = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_24RGB),
        (__bridge NSString *)kCVPixelBufferWidthKey : @(width),
        (__bridge NSString *)kCVPixelBufferHeightKey : @(height),
    };
    outputData.alwaysDiscardsLateVideoFrames = YES;
    [outputData setSampleBufferDelegate:self queue:_captureSessionQueue];
    return outputData;
}

- (int32_t)startCaptureWithUniqueId:(NSString *)uniqueId width:(uint32_t)width height:(uint32_t)height {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    if (_session != nil) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_SESSION_ALREADY_STARTED;
    }

    NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
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

    BOOL foundFormat = NO;
    for (AVCaptureDeviceFormat *candidateFormat in device.formats) {
        CMFormatDescriptionRef description = candidateFormat.formatDescription;
        if (description == NULL || CMFormatDescriptionGetMediaType(description) != kCMMediaType_Video) {
            continue;
        }

        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(description);
        if ((uint32_t)dimensions.width == width && (uint32_t)dimensions.height == height) {
            foundFormat = YES;
            break;
        }
    }

    if (!foundFormat) {
        dispatch_semaphore_signal(_semaphore);
        return ERROR_FORMAT_NOT_FOUND;
    }

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

    AVCaptureVideoDataOutput *outputData = [self initializeOutputDataWithWidth:width height:height];
    if (outputData == nil || ![session canAddOutput:outputData]) {
        [session commitConfiguration];
        dispatch_semaphore_signal(_semaphore);
        return ERROR_OPENING_DEVICE;
    }

    _deviceInput = deviceInput;
    _session = session;
    _outputData = outputData;

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

    [_session stopRunning];
    _deviceInput = nil;
    _outputData = nil;
    _session = nil;

    if (_buffer != NULL) {
        free(_buffer);
        _buffer = NULL;
    }

    _bufferSize = 0;
    _hasFrame = NO;
    _width = 0;
    _height = 0;
    _bytesPerRow = 0;

    dispatch_semaphore_signal(_semaphore);
    return RESULT_OK;
}

- (BOOL)hasFrame {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL hasFrame = _hasFrame;
    dispatch_semaphore_signal(_semaphore);
    return hasFrame;
}

- (BOOL)grabFrameTo:(uint8_t *)dst availableBytes:(uint32_t)availableBytes {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    if (!_hasFrame || _buffer == NULL || dst == NULL) {
        dispatch_semaphore_signal(_semaphore);
        return NO;
    }

    size_t copySize = (size_t)availableBytes;
    if (copySize > _bufferSize) {
        copySize = _bufferSize;
    }

    memcpy(dst, _buffer, copySize);
    _hasFrame = NO;

    dispatch_semaphore_signal(_semaphore);
    return YES;
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

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;

    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer == NULL) {
        return;
    }

    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    _width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
    _height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
    _bytesPerRow = (uint32_t)CVPixelBufferGetBytesPerRow(imageBuffer);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t size = CVPixelBufferGetDataSize(imageBuffer);
    if (_bufferSize < size) {
        void *newBuffer = realloc(_buffer, size);
        if (newBuffer == NULL) {
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            dispatch_semaphore_signal(_semaphore);
            return;
        }

        _buffer = (uint8_t *)newBuffer;
        _bufferSize = size;
    }

    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    if (baseAddress != NULL && _buffer != NULL) {
        memcpy(_buffer, baseAddress, size);
        _hasFrame = YES;
    }

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
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

        dict[@((uint32_t)kCMVideoCodecType_JPEG)] = @"JPEG";
#ifdef kCMVideoCodecType_JPEG_OpenDML
        dict[@((uint32_t)kCMVideoCodecType_JPEG_OpenDML)] = @"MJPG";
#endif
#ifdef kCMVideoCodecType_H263
        dict[@((uint32_t)kCMVideoCodecType_H263)] = @"H263";
#endif
#ifdef kCMVideoCodecType_H264
        dict[@((uint32_t)kCMVideoCodecType_H264)] = @"H264";
#endif
#ifdef kCMVideoCodecType_HEVC
        dict[@((uint32_t)kCMVideoCodecType_HEVC)] = @"HEVC";
#endif
#ifdef kCMVideoCodecType_MPEG4Video
        dict[@((uint32_t)kCMVideoCodecType_MPEG4Video)] = @"MPG4";
#endif
#ifdef kCMVideoCodecType_MPEG2Video
        dict[@((uint32_t)kCMVideoCodecType_MPEG2Video)] = @"MPG2";
#endif
#ifdef kCMVideoCodecType_MPEG1Video
        dict[@((uint32_t)kCMVideoCodecType_MPEG1Video)] = @"MPG1";
#endif

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

    return [[VCAVFVideoFormat alloc] initWithWidth:(uint32_t)size.width
                                            height:(uint32_t)size.height
                                              type:type];
}

static NSArray<VCAVFVideoDevice *> *VCAVFListDevices(void) {
    NSMutableArray<VCAVFVideoDevice *> *cameras = [[NSMutableArray alloc] init];

    NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
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
        NSString *formatString = [NSString stringWithFormat:@"%ux%u;%@", format.width, format.height, format.type];
        VCAVFCopyString(formatString, buf, length);
    }
}

int32_t vcavf_start_capture(uint32_t deviceIndex, uint32_t width, uint32_t height) {
    @autoreleasepool {
        VCAVFVideoDevice *device = VCAVFDeviceAtIndex(deviceIndex);
        if (device == nil) {
            return ERROR_DEVICE_NOT_FOUND;
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

        int32_t result = [session startCaptureWithUniqueId:device.uniqueId width:width height:height];
        if (result != RESULT_OK) {
            [gSessions removeObjectForKey:device.uniqueId];
        }

        return result;
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
