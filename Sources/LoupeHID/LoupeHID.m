#import "LoupeHID.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <IOSurface/IOSurface.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <malloc/malloc.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/qos.h>
#import <unistd.h>

#pragma pack(push, 4)
typedef struct {
    uint32_t field1;
    uint32_t field2;
    uint32_t field3;
    double xRatio;
    double yRatio;
    double field6;
    double field7;
    double field8;
    uint32_t field9;
    uint32_t field10;
    uint32_t field11;
    uint32_t field12;
    uint32_t field13;
    double field14;
    double field15;
    double field16;
    double field17;
    double field18;
} LoupeIndigoTouch;

typedef union {
    LoupeIndigoTouch touch;
    // IndigoEvent also carries a game-controller payload with 16 doubles.
    // Its size determines the stride of the duplicated touch contact, even
    // when only the smaller IndigoTouch member is populated.
    unsigned char storage[128];
} LoupeIndigoEvent;

typedef struct {
    uint32_t field1;
    uint64_t timestamp;
    uint32_t field3;
    LoupeIndigoEvent event;
} LoupeIndigoPayload;

typedef struct {
    unsigned char header[24];
    uint32_t innerSize;
    unsigned char eventType;
    unsigned char padding[3];
    LoupeIndigoPayload payload;
} LoupeIndigoMessage;

// SimulatorHID's extended create-digitizer control event. Its display UID is
// the screenProperties.uniqueId used by the guest to associate HID with UI.
typedef struct {
    uint32_t operation;
    uint32_t reserved;
    uint64_t reserved2;
    uint32_t target;
    uint8_t isBuiltIn;
    char displayUID[64];
} LoupeIndigoScreenEvent;
#pragma pack(pop)

_Static_assert(sizeof(LoupeIndigoTouch) == 112, "Unexpected Indigo touch layout");
_Static_assert(sizeof(LoupeIndigoPayload) == 144, "Indigo event union must retain the full payload stride");
_Static_assert(sizeof(LoupeIndigoMessage) == 176, "Unexpected Indigo message layout");
_Static_assert(offsetof(LoupeIndigoScreenEvent, target) == 16, "Unexpected screen target offset");
_Static_assert(offsetof(LoupeIndigoScreenEvent, isBuiltIn) == 20, "Unexpected built-in display flag offset");
_Static_assert(offsetof(LoupeIndigoScreenEvent, displayUID) == 21, "Unexpected display UID offset");

typedef LoupeIndigoMessage *(*LoupeKeyboardMessageFunction)(uint32_t keyCode, int operation);
typedef LoupeIndigoMessage *(*LoupeMouseMessageFunction)(CGPoint *point0, CGPoint *point1, uint32_t target, NSEventType eventType, NSSize size, uint32_t edge);

typedef struct {
    LoupeKeyboardMessageFunction keyboardMessage;
    LoupeMouseMessageFunction mouseMessage;
    uint32_t touchTarget;
} LoupeHIDFunctions;

typedef struct {
    uint32_t keyCode;
    bool shift;
} LoupeHIDKeyEvent;

static NSString * const LoupeCoreSimulatorPath = @"/Library/Developer/PrivateFrameworks/CoreSimulator.framework";
static int const LoupeHIDDirectionDown = 1;
static int const LoupeHIDDirectionUp = 2;

static NSString *LoupeDeveloperDir(void);
static id LoupeSimulatorObject(id target, NSString *name);

static bool LoupeHIDRegisterMainScreen(id device, id client, LoupeHIDFunctions *functions, char **errorMessage);

static void LoupeHIDSetError(char **errorMessage, NSString *message)
{
    if (errorMessage == NULL) {
        return;
    }
    *errorMessage = strdup(message.UTF8String);
}

static NSArray<NSString *> *LoupeSimulatorKitPaths(void)
{
    NSString *developerDir = [LoupeDeveloperDir() stringByStandardizingPath];
    return @[
        [developerDir stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework"],
        [[developerDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"SharedFrameworks/SimulatorKit.framework"],
    ];
}

static NSString *LoupeDeveloperDir(void)
{
    NSString *environmentDeveloperDir = [NSProcessInfo processInfo].environment[@"DEVELOPER_DIR"];
    if (environmentDeveloperDir.length > 0) {
        return environmentDeveloperDir;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcode-select"];
    task.arguments = @[@"-p"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    if ([task launchAndReturnError:nil]) {
        [task waitUntilExit];
        if (task.terminationStatus == 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *path = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (path.length > 0) {
                return path;
            }
        }
    }

    return @"/Applications/Xcode.app/Contents/Developer";
}

void LoupeHIDFreeCString(char *string)
{
    free(string);
}

static bool LoupeLoadCoreSimulator(char **errorMessage)
{
    NSBundle *coreSimulator = [NSBundle bundleWithPath:LoupeCoreSimulatorPath];
    if (![coreSimulator load]) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load %@", LoupeCoreSimulatorPath]);
        return false;
    }
    return true;
}

static bool LoupeHIDLoadFrameworks(char **errorMessage)
{
    if (!LoupeLoadCoreSimulator(errorMessage)) return false;
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    for (NSString *path in LoupeSimulatorKitPaths()) {
        NSBundle *simulatorKit = [NSBundle bundleWithPath:path];
        NSError *loadError = nil;
        if ([simulatorKit loadAndReturnError:&loadError]) {
            return true;
        }
        NSString *reason = loadError.localizedDescription ?: @"framework bundle not found or invalid";
        [failures addObject:[NSString stringWithFormat:@"%@: %@", path, reason]];
    }

    LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load SimulatorKit; tried:\n%@", [failures componentsJoinedByString:@"\n"]]);
    return false;
}

static bool LoupeHIDLoadFunctions(LoupeHIDFunctions *functions, char **errorMessage)
{
    functions->keyboardMessage = (LoupeKeyboardMessageFunction)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForKeyboardArbitrary");
    functions->mouseMessage = (LoupeMouseMessageFunction)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForMouseNSEvent");
    if (functions->keyboardMessage == NULL || functions->mouseMessage == NULL) {
        LoupeHIDSetError(errorMessage, @"SimulatorKit Indigo HID symbols are unavailable");
        return false;
    }
    return true;
}

static void LoupeHIDLookupStage(const char *stage)
{
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        fprintf(stderr, "loupe.hid.lookup stage=%s uptime=%.6f\n", stage,
            NSProcessInfo.processInfo.systemUptime);
    }
}

static id LoupeHIDDeviceForUDID(NSString *udid, char **errorMessage)
{
    Class contextClass = NSClassFromString(@"SimServiceContext");
    if (contextClass == Nil) {
        LoupeHIDSetError(errorMessage, @"CoreSimulator SimServiceContext is unavailable");
        return nil;
    }

    NSError *error = nil;
    LoupeHIDLookupStage("service-context");
    id context = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        contextClass,
        NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),
        LoupeDeveloperDir(),
        &error
    );
    if (context == nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to create CoreSimulator service context: %@", error]);
        return nil;
    }

    LoupeHIDLookupStage("device-set");
    id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(
        context,
        NSSelectorFromString(@"defaultDeviceSetWithError:"),
        &error
    );
    if (deviceSet == nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load CoreSimulator device set: %@", error]);
        return nil;
    }

    LoupeHIDLookupStage("available-devices");
    NSArray *devices = ((id (*)(id, SEL))objc_msgSend)(deviceSet, NSSelectorFromString(@"availableDevices"));
    LoupeHIDLookupStage("select-device");
    for (id device in devices) {
        NSString *state = ((id (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"stateString"));
        NSUUID *deviceUDID = ((id (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"UDID"));
        if (([udid isEqualToString:@"booted"] && [state isEqualToString:@"Booted"]) || [[deviceUDID UUIDString] isEqualToString:udid]) {
            return device;
        }
    }

    LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"booted simulator not found for UDID %@", udid]);
    return nil;
}

static id LoupeHIDClientForUDID(NSString *udid, LoupeHIDFunctions *touchFunctions, char **errorMessage)
{
    id device = LoupeHIDDeviceForUDID(udid, errorMessage);
    if (device == nil) {
        return nil;
    }
    Class clientClass = NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient");
    if (clientClass == Nil) {
        LoupeHIDSetError(errorMessage, @"SimulatorKit SimDeviceLegacyHIDClient is unavailable");
        return nil;
    }

    NSError *error = nil;
    id client = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        [clientClass alloc],
        NSSelectorFromString(@"initWithDevice:error:"),
        device,
        &error
    );
    if (client == nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to create HID client: %@", error]);
        return nil;
    }
    if (touchFunctions != NULL) {
        touchFunctions->touchTarget = 0x32;
        // Xcode 27 exposes the backing SimScreen; its input service is routed
        // by screen ID. Earlier SimulatorKit uses the legacy main digitizer.
        Class screenClass = NSClassFromString(@"SimulatorKit.SimDeviceScreen");
        if ([screenClass instancesRespondToSelector:NSSelectorFromString(@"screen")] &&
            !LoupeHIDRegisterMainScreen(device, client, touchFunctions, errorMessage)) return nil;
    }
    return client;
}

static void LoupeHIDSendMessage(id client, LoupeIndigoMessage *message)
{
    ((void (*)(id, SEL, LoupeIndigoMessage *, BOOL, dispatch_queue_t, id))objc_msgSend)(
        client,
        NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:"),
        message,
        YES,
        NULL,
        nil
    );
}

static bool LoupeHIDSendTouchMessage(id client, LoupeIndigoMessage *message, char **errorMessage)
{
    if (message == NULL) {
        LoupeHIDSetError(errorMessage, @"failed to build simulator touch message");
        return false;
    }
    dispatch_semaphore_t completion = dispatch_semaphore_create(0);
    __block NSError *sendError = nil;
    __block double acknowledgedAt = 0;
    double enqueuedAt = NSProcessInfo.processInfo.systemUptime;
    uint64_t eventTimestamp = message->payload.timestamp;
    ((void (*)(id, SEL, LoupeIndigoMessage *, BOOL, dispatch_queue_t, void (^)(NSError *)))objc_msgSend)(
        client,
        NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:"),
        message,
        YES,
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^(NSError *error) {
            sendError = error;
            acknowledgedAt = NSProcessInfo.processInfo.systemUptime;
            dispatch_semaphore_signal(completion);
        }
    );
    // The transport is asynchronous. Keep the client alive and preserve touch
    // phase ordering until delivery is acknowledged, rather than assuming a
    // fixed sleep flushed the final event before this CLI process exits.
    if (dispatch_semaphore_wait(completion, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
        LoupeHIDSetError(errorMessage, @"simulator touch delivery was not acknowledged");
        return false;
    }
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        fprintf(stderr, "loupe.hid.touch timestamp=%llu enqueued=%.6f acknowledged=%.6f latency=%.6f\n",
            (unsigned long long)eventTimestamp, enqueuedAt, acknowledgedAt, acknowledgedAt - enqueuedAt);
    }
    if (sendError != nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"simulator touch delivery failed: %@", sendError.localizedDescription]);
        return false;
    }
    return true;
}

static CGPoint LoupeHIDRatio(double x, double y, double width, double height)
{
    return CGPointMake(x / MAX(width, 1.0), y / MAX(height, 1.0));
}

static void LoupeHIDWaitUntil(double deadline)
{
    double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
    if (remaining <= 0) return;
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0,
        DISPATCH_TIMER_STRICT, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    // Queue QoS alone does not exempt a background process from timer
    // coalescing. Request precision only for this bounded gesture phase.
    // The handler must run outside the serial gesture queue we are waiting on.
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)ceil(remaining * 1000000000.0)),
        DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(timer, ^{ dispatch_semaphore_signal(completed); });
    dispatch_resume(timer);
    dispatch_semaphore_wait(completed, DISPATCH_TIME_FOREVER);
    dispatch_source_cancel(timer);
}

static void LoupeHIDRunInputTask(const char *phase, NSString *reason, dispatch_block_t operation)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("dev.loupe.hid.gesture",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
    });
    // Enqueue on the interactive worker instead of executing synchronously
    // on the caller. A nested async_and_wait from the main thread can leave
    // SimulatorKit's ROCKit proxy without its expected dispatch context.
    // The completion also keeps output pointers alive until preparation ends.
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{
        const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
        if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
            fprintf(stderr, "loupe.hid.%s qos=%u\n", phase, qos_class_self());
        }
        [NSProcessInfo.processInfo performActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
            reason:reason usingBlock:operation];
        dispatch_semaphore_signal(completed);
    });
    dispatch_semaphore_wait(completed, DISPATCH_TIME_FOREVER);
}

static void LoupeHIDRunGesture(dispatch_block_t gesture)
{
    LoupeHIDRunInputTask("gesture", @"Deliver requested simulator gesture", gesture);
}

static LoupeIndigoMessage *LoupeHIDTouchMessage(LoupeMouseMessageFunction mouseMessage, uint32_t target, CGPoint ratio, int direction)
{
    LoupeIndigoMessage *seed = mouseMessage(&ratio, NULL, target, (NSEventType)direction, NSMakeSize(1, 1), 0);
    if (seed == NULL) {
        return NULL;
    }
    size_t stride = seed->innerSize;
    size_t payloadOffset = offsetof(LoupeIndigoMessage, payload);
    size_t seedSize = malloc_size(seed);
    if (stride < sizeof(LoupeIndigoPayload) || seedSize < payloadOffset ||
        stride > seedSize - payloadOffset || stride > (SIZE_MAX - payloadOffset) / 2) {
        free(seed);
        return NULL;
    }
    if ((target & 0x40000000) == 0) {
        seed->payload.event.touch.xRatio = ratio.x;
        seed->payload.event.touch.yRatio = ratio.y;
    }
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        LoupeIndigoTouch touch = seed->payload.event.touch;
        fprintf(stderr, "loupe.hid.message direction=%d seedSize=%zu innerSize=%u eventType=%u ratio=%.6f,%.6f fields=%u,%u,%u,%u,%u,%u,%u,%u\n",
            direction, malloc_size(seed), seed->innerSize, seed->eventType, ratio.x, ratio.y,
            touch.field1, touch.field2, touch.field3, touch.field9, touch.field10,
            touch.field11, touch.field12, touch.field13);
    }

    // Screen-routed input uses SimulatorKit's complete native message.
    if ((target & 0x40000000) != 0) return seed;

    // Preserve the legacy main-digitizer envelope and Mach-time convention,
    // while retaining the builder's actual payload stride and event tail.
    LoupeIndigoMessage *message = calloc(1, payloadOffset + 2 * stride);
    if (message == NULL) { free(seed); return NULL; }
    message->innerSize = (uint32_t)stride;
    message->eventType = 2;
    message->payload.field1 = 0x0b;
    message->payload.timestamp = mach_absolute_time();
    memcpy(&message->payload.event, &seed->payload.event, stride - offsetof(LoupeIndigoPayload, event));
    LoupeIndigoPayload *second = (void *)((char *)&message->payload + stride);
    memcpy(second, &message->payload, stride);
    second->event.touch.field1 = 1;
    second->event.touch.field2 = 2;
    free(seed);
    return message;
}

static LoupeIndigoMessage *LoupeHIDScreenMessage(LoupeMouseMessageFunction mouseMessage, uint32_t target, NSString *displayUID)
{
    NSData *uid = [displayUID dataUsingEncoding:NSUTF8StringEncoding];
    if ((target & 0x40000000) == 0 || uid.length == 0 ||
        uid.length >= sizeof(((LoupeIndigoScreenEvent *)0)->displayUID)) return NULL;
    CGPoint ratio = CGPointZero;
    LoupeIndigoMessage *seed = mouseMessage(&ratio, NULL, target, (NSEventType)LoupeHIDDirectionDown, NSMakeSize(1, 1), 0);
    if (seed == NULL) return NULL;
    size_t stride = seed->innerSize;
    size_t offset = offsetof(LoupeIndigoMessage, payload);
    size_t allocated = malloc_size(seed);
    free(seed);
    if (stride < sizeof(LoupeIndigoPayload) || allocated < offset || stride > allocated - offset) return NULL;
    LoupeIndigoMessage *message = calloc(1, offset + stride);
    if (message == NULL) return NULL;
    message->innerSize = (uint32_t)stride;
    message->eventType = 1;
    message->payload.field1 = 0x7fff0001;
    message->payload.timestamp = mach_absolute_time();
    LoupeIndigoScreenEvent *event = (void *)&message->payload.event;
    event->operation = 1;
    event->target = target;
    event->isBuiltIn = 0;
    memcpy(event->displayUID, uid.bytes, uid.length);
    return message;
}

static bool LoupeHIDRegisterMainScreen(id device, id client, LoupeHIDFunctions *functions, char **errorMessage)
{
    id mainScreen = nil;
    for (id port in LoupeSimulatorObject(LoupeSimulatorObject(device, @"io"), @"ioPorts")) {
        id descriptor = LoupeSimulatorObject(port, @"descriptor");
        id state = LoupeSimulatorObject(descriptor, @"state");
        if (![state respondsToSelector:NSSelectorFromString(@"displayClass")]) continue;
        unsigned short displayClass = ((unsigned short (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"displayClass"));
        if (displayClass != 0) continue;
        if (mainScreen != nil) {
            LoupeHIDSetError(errorMessage, @"simulator main screen is ambiguous for touch input");
            return false;
        }
        mainScreen = descriptor;
    }
    id properties = LoupeSimulatorObject(mainScreen, @"screenProperties");
    NSString *displayUID = LoupeSimulatorObject(properties, @"uniqueId");
    if (![properties respondsToSelector:NSSelectorFromString(@"screenID")] ||
        ![displayUID isKindOfClass:NSString.class] || displayUID.length == 0) {
        LoupeHIDSetError(errorMessage, @"simulator main screen ID and display UID are unavailable for touch input");
        return false;
    }
    uint32_t screenID = ((uint32_t (*)(id, SEL))objc_msgSend)(properties, NSSelectorFromString(@"screenID"));
    // Device Hub owns the screen's built-in digitizer. Bind a separate virtual
    // target to the actual display UID and reuse it across CLI invocations.
    functions->touchTarget = screenID | 0x40100000;
    if (!LoupeHIDSendTouchMessage(client, LoupeHIDScreenMessage(functions->mouseMessage, functions->touchTarget, displayUID), errorMessage)) return false;
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        fprintf(stderr, "loupe.hid.screen id=%u target=0x%x registered=1\n", screenID, functions->touchTarget);
    }
    return true;
}

static bool LoupeHIDPrepare(NSString *udid, id *client, LoupeHIDFunctions *functions, bool forTouch, char **errorMessage)
{
    if (!LoupeHIDLoadFrameworks(errorMessage)) {
        return false;
    }
    if (!LoupeHIDLoadFunctions(functions, errorMessage)) {
        return false;
    }
    *client = LoupeHIDClientForUDID(udid, forTouch ? functions : NULL, errorMessage);
    return *client != nil;
}

int LoupeHIDTap(const char *udid, double x, double y, double width, double height, char **errorMessage)
{
    return LoupeHIDTapCount(udid, x, y, width, height, 1, errorMessage);
}

static int LoupeHIDPerformTapCount(const char *udid, double x, double y, double width, double height, int count, char **errorMessage)
{
    if (count < 1 || count > 2) {
        LoupeHIDSetError(errorMessage, @"Tap count must be 1 or 2");
        return 1;
    }
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, true, errorMessage)) {
            return 1;
        }

        double startedAt = NSProcessInfo.processInfo.systemUptime;
        double previousUpAcknowledgedAt = startedAt;
        for (int index = 0; index < count; index++) {
            if (index > 0) {
                // Keep the gesture on one timeline. A delayed wake-up must
                // not add another full inter-tap gap, which can turn a double
                // tap into two separate taps. Still leave one frame after up.
                LoupeHIDWaitUntil(MAX(startedAt + index * 0.155, previousUpAcknowledgedAt + 0.016));
            }
            CGPoint ratio = LoupeHIDRatio(x, y, width, height);
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, ratio, LoupeHIDDirectionDown), errorMessage)) {
                return 1;
            }
            // ACK latency must not consume the contact's minimum dwell. If
            // down takes longer than 50ms to acknowledge, an enqueue-based
            // deadline otherwise sends up immediately after that acknowledgement.
            LoupeHIDWaitUntil(NSProcessInfo.processInfo.systemUptime + 0.050);
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, ratio, LoupeHIDDirectionUp), errorMessage)) {
                return 1;
            }
            previousUpAcknowledgedAt = NSProcessInfo.processInfo.systemUptime;
        }
        LoupeHIDWaitUntil(NSProcessInfo.processInfo.systemUptime + 0.025);
        return 0;
    }
}

int LoupeHIDTapCount(const char *udid, double x, double y, double width, double height, int count, char **errorMessage)
{
    __block int status;
    LoupeHIDRunGesture(^{ status = LoupeHIDPerformTapCount(udid, x, y, width, height, count, errorMessage); });
    return status;
}

int LoupeHIDDrag(
    const char *udid,
    double startX,
    double startY,
    double endX,
    double endY,
    double width,
    double height,
    double duration,
    char **errorMessage
)
{
    return LoupeHIDDragWithHold(udid, startX, startY, endX, endY, width, height, duration, 0, errorMessage);
}

static int LoupeHIDPerformDragWithHold(
    const char *udid, double startX, double startY, double endX, double endY,
    double width, double height, double duration, double holdDuration, char **errorMessage
)
{
    if (!isfinite(duration) || duration <= 0 || !isfinite(holdDuration) || holdDuration < 0 || duration + holdDuration > 10) {
        LoupeHIDSetError(errorMessage, @"Touch hold and movement timing is invalid");
        return 1;
    }
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, true, errorMessage)) {
            return 1;
        }

        int steps = MAX(1, (int)ceil(hypot(endX - startX, endY - startY) / 20.0));
        CGPoint startRatio = LoupeHIDRatio(startX, startY, width, height);
        if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, startRatio, LoupeHIDDirectionDown), errorMessage)) {
            return 1;
        }
        if (holdDuration > 0) LoupeHIDWaitUntil(NSProcessInfo.processInfo.systemUptime + holdDuration);
        double startedAt = NSProcessInfo.processInfo.systemUptime;
        for (int index = 1; index <= steps; index += 1) {
            double progress = (double)index / (double)steps;
            LoupeHIDWaitUntil(startedAt + duration * progress);
            double x = startX + ((endX - startX) * progress);
            double y = startY + ((endY - startY) * progress);
            CGPoint ratio = LoupeHIDRatio(x, y, width, height);
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, ratio, LoupeHIDDirectionDown), errorMessage)) {
                // Release the same contact after a failed move; never replay it.
                CGPoint endRatio = LoupeHIDRatio(endX, endY, width, height);
                LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, endRatio, LoupeHIDDirectionUp), NULL);
                return 1;
            }
        }
        CGPoint endRatio = LoupeHIDRatio(endX, endY, width, height);
        if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, functions.touchTarget, endRatio, LoupeHIDDirectionUp), errorMessage)) {
            return 1;
        }
        LoupeHIDWaitUntil(NSProcessInfo.processInfo.systemUptime + 0.025);
        return 0;
    }
}

int LoupeHIDDragWithHold(
    const char *udid, double startX, double startY, double endX, double endY,
    double width, double height, double duration, double holdDuration, char **errorMessage
)
{
    __block int status;
    LoupeHIDRunGesture(^{
        status = LoupeHIDPerformDragWithHold(udid, startX, startY, endX, endY,
            width, height, duration, holdDuration, errorMessage);
    });
    return status;
}

static LoupeHIDKeyEvent LoupeHIDKeyEventForUnichar(unichar character)
{
    if (character >= 'a' && character <= 'z') {
        return (LoupeHIDKeyEvent){ character - 'a' + 4, false };
    }
    if (character >= 'A' && character <= 'Z') {
        return (LoupeHIDKeyEvent){ character - 'A' + 4, true };
    }
    if (character >= '1' && character <= '9') {
        return (LoupeHIDKeyEvent){ character - '1' + 30, false };
    }
    if (character == '0') {
        return (LoupeHIDKeyEvent){ 39, false };
    }

    switch (character) {
        case '\n': return (LoupeHIDKeyEvent){ 40, false };
        case ' ': return (LoupeHIDKeyEvent){ 44, false };
        case '-': return (LoupeHIDKeyEvent){ 45, false };
        case '=': return (LoupeHIDKeyEvent){ 46, false };
        case '[': return (LoupeHIDKeyEvent){ 47, false };
        case ']': return (LoupeHIDKeyEvent){ 48, false };
        case '\\': return (LoupeHIDKeyEvent){ 49, false };
        case ';': return (LoupeHIDKeyEvent){ 51, false };
        case '\'': return (LoupeHIDKeyEvent){ 52, false };
        case '`': return (LoupeHIDKeyEvent){ 53, false };
        case ',': return (LoupeHIDKeyEvent){ 54, false };
        case '.': return (LoupeHIDKeyEvent){ 55, false };
        case '/': return (LoupeHIDKeyEvent){ 56, false };
        case '!': return (LoupeHIDKeyEvent){ 30, true };
        case '@': return (LoupeHIDKeyEvent){ 31, true };
        case '#': return (LoupeHIDKeyEvent){ 32, true };
        case '$': return (LoupeHIDKeyEvent){ 33, true };
        case '%': return (LoupeHIDKeyEvent){ 34, true };
        case '^': return (LoupeHIDKeyEvent){ 35, true };
        case '&': return (LoupeHIDKeyEvent){ 36, true };
        case '*': return (LoupeHIDKeyEvent){ 37, true };
        case '(': return (LoupeHIDKeyEvent){ 38, true };
        case ')': return (LoupeHIDKeyEvent){ 39, true };
        case '_': return (LoupeHIDKeyEvent){ 45, true };
        case '+': return (LoupeHIDKeyEvent){ 46, true };
        case '{': return (LoupeHIDKeyEvent){ 47, true };
        case '}': return (LoupeHIDKeyEvent){ 48, true };
        case '|': return (LoupeHIDKeyEvent){ 49, true };
        case ':': return (LoupeHIDKeyEvent){ 51, true };
        case '"': return (LoupeHIDKeyEvent){ 52, true };
        case '~': return (LoupeHIDKeyEvent){ 53, true };
        case '<': return (LoupeHIDKeyEvent){ 54, true };
        case '>': return (LoupeHIDKeyEvent){ 55, true };
        case '?': return (LoupeHIDKeyEvent){ 56, true };
        default: return (LoupeHIDKeyEvent){ 0, false };
    }
}

static void LoupeHIDSendKey(id client, LoupeKeyboardMessageFunction keyboardMessage, uint32_t keyCode, int direction)
{
    LoupeHIDSendMessage(client, keyboardMessage(keyCode, direction));
}

static uint32_t LoupeHIDRemoteKeyCode(NSString *button)
{
    NSString *normalized = [[button lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"_" withString:@""];
    if ([normalized isEqualToString:@"up"]) { return 82; }
    if ([normalized isEqualToString:@"down"]) { return 81; }
    if ([normalized isEqualToString:@"left"]) { return 80; }
    if ([normalized isEqualToString:@"right"]) { return 79; }
    if ([normalized isEqualToString:@"select"] || [normalized isEqualToString:@"ok"] || [normalized isEqualToString:@"enter"]) { return 40; }
    if ([normalized isEqualToString:@"menu"] || [normalized isEqualToString:@"back"]) { return 41; }
    if ([normalized isEqualToString:@"playpause"] || [normalized isEqualToString:@"play"]) { return 44; }
    return 0;
}

int LoupeHIDType(const char *udid, const char *text, char **errorMessage)
{
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, false, errorMessage)) {
            return 1;
        }

        NSString *input = [NSString stringWithUTF8String:text];
        for (NSUInteger index = 0; index < input.length; index += 1) {
            LoupeHIDKeyEvent event = LoupeHIDKeyEventForUnichar([input characterAtIndex:index]);
            if (event.keyCode == 0) {
                LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"unsupported character for HID typing at index %lu", (unsigned long)index]);
                return 1;
            }
            if (event.shift) {
                LoupeHIDSendKey(client, functions.keyboardMessage, 225, LoupeHIDDirectionDown);
            }
            LoupeHIDSendKey(client, functions.keyboardMessage, event.keyCode, LoupeHIDDirectionDown);
            LoupeHIDSendKey(client, functions.keyboardMessage, event.keyCode, LoupeHIDDirectionUp);
            if (event.shift) {
                LoupeHIDSendKey(client, functions.keyboardMessage, 225, LoupeHIDDirectionUp);
            }
            usleep(20 * 1000);
        }
        usleep(25 * 1000);
        return 0;
    }
}

int LoupeHIDPress(const char *udid, const char *button, char **errorMessage)
{
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, false, errorMessage)) {
            return 1;
        }

        NSString *input = [NSString stringWithUTF8String:button];
        uint32_t keyCode = LoupeHIDRemoteKeyCode(input);
        if (keyCode == 0) {
            LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"unsupported press button: %@", input]);
            return 1;
        }

        LoupeHIDSendKey(client, functions.keyboardMessage, keyCode, LoupeHIDDirectionDown);
        usleep(40 * 1000);
        LoupeHIDSendKey(client, functions.keyboardMessage, keyCode, LoupeHIDDirectionUp);
        usleep(25 * 1000);
        return 0;
    }
}

// Read the composed main display, using the same CoreSimulator connection as HID.
static id LoupeSimulatorObject(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [target respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(target, selector) : nil;
}

void LoupeSimulatorFreeBuffer(void *bytes) { free(bytes); }

static void LoupeFramebufferStage(const char *stage) {
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        fprintf(stderr, "loupe.framebuffer stage=%s uptime=%.6f\n", stage,
            NSProcessInfo.processInfo.systemUptime);
    }
}

int LoupeSimulatorCopyPNG(const char *udid, void **bytes, size_t *count, char **errorMessage) {
    *bytes = NULL; *count = 0;
    @autoreleasepool { @try {
        LoupeFramebufferStage("load-core-simulator");
        if (!LoupeLoadCoreSimulator(errorMessage)) return 1;
        LoupeFramebufferStage("connect-device");
        id device = LoupeHIDDeviceForUDID([NSString stringWithUTF8String:udid], errorMessage);
        if (!device) return 1;
        LoupeFramebufferStage("read-ports");
        NSArray *ports = LoupeSimulatorObject(LoupeSimulatorObject(device, @"io"), @"ioPorts");
        id mainDisplay = nil;
        for (id port in ports) {
            id descriptor = LoupeSimulatorObject(port, @"descriptor");
            id state = LoupeSimulatorObject(descriptor, @"state");
            if (![state respondsToSelector:NSSelectorFromString(@"displayClass")] ||
                ![descriptor respondsToSelector:NSSelectorFromString(@"framebufferSurface")]) continue;
            unsigned short displayClass = ((unsigned short (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"displayClass"));
            if (displayClass != 0) continue;
            if (mainDisplay) { LoupeHIDSetError(errorMessage, @"Simulator main display is ambiguous"); return 1; }
            mainDisplay = descriptor;
        }
        if (!mainDisplay) return 2;
        LoupeFramebufferStage("read-surface");
        IOSurfaceRef surface = (__bridge IOSurfaceRef)(LoupeSimulatorObject(mainDisplay, @"framebufferSurface") ?: LoupeSimulatorObject(mainDisplay, @"ioSurface"));
        if (!surface) { LoupeHIDSetError(errorMessage, @"Simulator main display has no framebuffer"); return 1; }
        // Read the main display's composed framebuffer. App interface
        // orientation alone is not evidence of display surface orientation.
        IOSurfaceIncrementUseCount(surface);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image = NULL;
        CFMutableDataRef png = NULL;
        CGImageDestinationRef destination = NULL;
        @try {
            LoupeFramebufferStage("create-context");
            static CIContext *context;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ context = [[CIContext alloc] initWithOptions:nil]; });
            if (!space) { LoupeHIDSetError(errorMessage, @"Could not create framebuffer color space"); return 1; }
            LoupeFramebufferStage("render-image");
            CIImage *source = [CIImage imageWithIOSurface:surface options:@{kCIImageColorSpace:(__bridge id)space}];
            image = [context createCGImage:source fromRect:source.extent];
            if (!image || CGImageGetWidth(image) == 0 || CGImageGetHeight(image) == 0) {
                LoupeHIDSetError(errorMessage, @"Could not render simulator framebuffer"); return 1;
            }
            LoupeFramebufferStage("encode-png");
            png = CFDataCreateMutable(kCFAllocatorDefault, 0);
            destination = CGImageDestinationCreateWithData(png, CFSTR("public.png"), 1, NULL);
            if (!destination) { LoupeHIDSetError(errorMessage, @"Could not encode simulator framebuffer"); return 1; }
            CGImageDestinationAddImage(destination, image, NULL);
            if (!CGImageDestinationFinalize(destination)) { LoupeHIDSetError(errorMessage, @"Incomplete framebuffer PNG"); return 1; }
            size_t length = (size_t)CFDataGetLength(png);
            void *copy = malloc(length);
            if (!copy) { LoupeHIDSetError(errorMessage, @"Could not allocate framebuffer PNG"); return 1; }
            memcpy(copy, CFDataGetBytePtr(png), length);
            *bytes = copy; *count = length;
            LoupeFramebufferStage("complete");
            return 0;
        } @finally {
            if (destination) CFRelease(destination);
            if (png) CFRelease(png);
            if (image) CGImageRelease(image);
            if (space) CGColorSpaceRelease(space);
            IOSurfaceDecrementUseCount(surface);
        }
    } @catch (NSException *exception) {
        LoupeHIDSetError(errorMessage, exception.reason ?: exception.name); return 1;
    } }
}
