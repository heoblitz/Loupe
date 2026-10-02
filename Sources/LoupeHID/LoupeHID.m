#import "LoupeHID.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
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
#pragma pack(pop)

_Static_assert(sizeof(LoupeIndigoTouch) == 112, "Unexpected Indigo touch layout");
_Static_assert(sizeof(LoupeIndigoPayload) == 144, "Indigo event union must retain the full payload stride");
_Static_assert(sizeof(LoupeIndigoMessage) == 176, "Unexpected Indigo message layout");

typedef LoupeIndigoMessage *(*LoupeKeyboardMessageFunction)(uint32_t keyCode, int operation);
typedef LoupeIndigoMessage *(*LoupeMouseMessageFunction)(CGPoint *point0, CGPoint *point1, uint32_t target, NSEventType eventType, NSSize size, uint32_t edge);

typedef struct {
    LoupeKeyboardMessageFunction keyboardMessage;
    LoupeMouseMessageFunction mouseMessage;
} LoupeHIDFunctions;

typedef struct {
    uint32_t keyCode;
    bool shift;
} LoupeHIDKeyEvent;

static NSString * const LoupeCoreSimulatorPath = @"/Library/Developer/PrivateFrameworks/CoreSimulator.framework";
static int const LoupeHIDDirectionDown = 1;
static int const LoupeHIDDirectionUp = 2;
static int const LoupeHIDEventTypeTouch = 2;
static int const LoupeHIDTouchEventKind = 0x0b;
static int const LoupeHIDDigitizerTarget = 0x32;

static NSString *LoupeDeveloperDir(void);

static void LoupeHIDRecordPhase(const char *phase)
{
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        fprintf(stderr, "loupe.hid.phase %s timestamp=%llu qos=%u\n", phase, mach_absolute_time(), qos_class_self());
    }
}

static void LoupeHIDSetError(char **errorMessage, NSString *message)
{
    if (errorMessage == NULL) {
        return;
    }
    *errorMessage = strdup(message.UTF8String);
}

static NSString *LoupeSimulatorKitPath(void)
{
    NSString *developerDir = LoupeDeveloperDir();
    return [developerDir stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework"];
}

static NSString *LoupeResolveDeveloperDir(void)
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

static NSString *LoupeDeveloperDir(void)
{
    static NSString *developerDir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ developerDir = LoupeResolveDeveloperDir(); });
    return developerDir;
}

void LoupeHIDFreeCString(char *string)
{
    free(string);
}

bool LoupeSimulatorLoadCoreSimulator(char **errorMessage)
{
    LoupeHIDRecordPhase("coresimulator.begin");
    NSBundle *coreSimulator = [NSBundle bundleWithPath:LoupeCoreSimulatorPath];
    if (![coreSimulator load]) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load %@", LoupeCoreSimulatorPath]);
        return false;
    }
    LoupeHIDRecordPhase("coresimulator.end");
    return true;
}

bool LoupeHIDLoadFrameworks(char **errorMessage)
{
    LoupeHIDRecordPhase("frameworks.begin");
    if (!LoupeSimulatorLoadCoreSimulator(errorMessage)) return false;
    LoupeHIDRecordPhase("simulatorkit.begin");
    NSString *simulatorKitPath = LoupeSimulatorKitPath();
    NSBundle *simulatorKit = [NSBundle bundleWithPath:simulatorKitPath];
    if (![simulatorKit load]) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load %@", simulatorKitPath]);
        return false;
    }

    LoupeHIDRecordPhase("simulatorkit.end");
    LoupeHIDRecordPhase("frameworks.end");
    return true;
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

id LoupeHIDDeviceForUDID(NSString *udid, char **errorMessage)
{
    static NSLock *lock;
    static NSMutableDictionary *resolvedDevices;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
        resolvedDevices = [[NSMutableDictionary alloc] init];
    });
    [lock lock];
    @try {
        // `booted` must be resolved afresh; explicit identities are shared with
        // capture and boot observation for this short-lived CLI process.
        if (![udid isEqualToString:@"booted"] && resolvedDevices[udid] != nil) {
            return resolvedDevices[udid];
        }
        Class contextClass = NSClassFromString(@"SimServiceContext");
        if (contextClass == Nil) {
            LoupeHIDSetError(errorMessage, @"CoreSimulator SimServiceContext is unavailable");
            return nil;
        }

        NSError *error = nil;
        LoupeHIDRecordPhase("service-context.begin");
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

        LoupeHIDRecordPhase("service-context.end");
        LoupeHIDRecordPhase("device-set.begin");

        id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(
            context,
            NSSelectorFromString(@"defaultDeviceSetWithError:"),
            &error
        );
        if (deviceSet == nil) {
            LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load CoreSimulator device set: %@", error]);
            return nil;
        }

        LoupeHIDRecordPhase("device-set.end");
        LoupeHIDRecordPhase("device-list.begin");

        NSArray *devices = ((id (*)(id, SEL))objc_msgSend)(deviceSet, NSSelectorFromString(@"availableDevices"));
        for (id device in devices) {
            NSString *state = ((id (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"stateString"));
            NSUUID *deviceUDID = ((id (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"UDID"));
            if (([udid isEqualToString:@"booted"] && [state isEqualToString:@"Booted"]) || [[deviceUDID UUIDString] isEqualToString:udid]) {
                LoupeHIDRecordPhase("device-list.end");
                if (![udid isEqualToString:@"booted"]) resolvedDevices[udid] = device;
                return device;
            }
        }

        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"booted simulator not found for UDID %@", udid]);
        return nil;
    } @finally { [lock unlock]; }
}

static id LoupeHIDCreateClientForUDID(NSString *udid, char **errorMessage)
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
    LoupeHIDRecordPhase("client.begin");
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
    LoupeHIDRecordPhase("client.end");
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

static void LoupeHIDRunGesture(dispatch_block_t gesture)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("dev.loupe.hid.gesture",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
    });
    // Unlike dispatch_sync, async_and_wait observes the queue's QoS. Touch
    // timing must not inherit a background caller's timer coalescing policy.
    dispatch_async_and_wait(queue, ^{
        const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
        if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
            fprintf(stderr, "loupe.hid.gesture qos=%u\n", qos_class_self());
        }
        [NSProcessInfo.processInfo performActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
            reason:@"Deliver requested simulator gesture" usingBlock:gesture];
    });
}

static LoupeIndigoMessage *LoupeHIDTouchMessage(LoupeMouseMessageFunction mouseMessage, CGPoint ratio, int direction)
{
    LoupeIndigoMessage *seed = mouseMessage(&ratio, NULL, LoupeHIDDigitizerTarget, (NSEventType)direction, NSMakeSize(1, 1), 0);
    if (seed == NULL) {
        return NULL;
    }
    seed->payload.event.touch.xRatio = ratio.x;
    seed->payload.event.touch.yRatio = ratio.y;
    const char *diagnostics = getenv("LOUPE_HID_DIAGNOSTICS");
    if (diagnostics != NULL && strcmp(diagnostics, "1") == 0) {
        LoupeIndigoTouch touch = seed->payload.event.touch;
        fprintf(stderr, "loupe.hid.message direction=%d seedSize=%zu innerSize=%u eventType=%u ratio=%.6f,%.6f fields=%u,%u,%u,%u,%u,%u,%u,%u\n",
            direction, malloc_size(seed), seed->innerSize, seed->eventType, ratio.x, ratio.y,
            touch.field1, touch.field2, touch.field3, touch.field9, touch.field10,
            touch.field11, touch.field12, touch.field13);
    }

    size_t messageSize = sizeof(LoupeIndigoMessage) + sizeof(LoupeIndigoPayload);
    size_t stride = sizeof(LoupeIndigoPayload);
    LoupeIndigoMessage *message = calloc(1, messageSize);
    if (message == NULL) {
        free(seed);
        return NULL;
    }
    message->innerSize = sizeof(LoupeIndigoPayload);
    message->eventType = LoupeHIDEventTypeTouch;
    message->payload.field1 = LoupeHIDTouchEventKind;
    message->payload.timestamp = mach_absolute_time();
    memcpy(&(message->payload.event.touch), &(seed->payload.event.touch), sizeof(LoupeIndigoTouch));

    LoupeIndigoPayload *second = (LoupeIndigoPayload *)((char *)&message->payload + stride);
    memcpy(second, &message->payload, stride);
    second->event.touch.field1 = 1;
    second->event.touch.field2 = 2;

    free(seed);
    return message;
}

static bool LoupeHIDPrepare(NSString *udid, id *client, LoupeHIDFunctions *functions, char **errorMessage)
{
    static NSLock *lock;
    static NSMutableDictionary *clients;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
        clients = [[NSMutableDictionary alloc] init];
    });
    [lock lock];
    @try {
        if (!LoupeHIDLoadFrameworks(errorMessage)) {
            return false;
        }
        if (!LoupeHIDLoadFunctions(functions, errorMessage)) {
            return false;
        }
        *client = clients[udid];
        if (*client == nil) {
            *client = LoupeHIDCreateClientForUDID(udid, errorMessage);
            if (*client != nil) {
                clients[udid] = *client;
            }
        }
        return *client != nil;
    } @finally {
        [lock unlock];
    }
}

int LoupeHIDInitialize(const char *udid, char **errorMessage)
{
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        return LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage) ? 0 : 1;
    }
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
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
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
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionDown), errorMessage)) {
                return 1;
            }
            // ACK latency must not consume the contact's minimum dwell. If
            // down takes longer than 50ms to acknowledge, an enqueue-based
            // deadline otherwise sends up immediately after that acknowledgement.
            LoupeHIDWaitUntil(NSProcessInfo.processInfo.systemUptime + 0.050);
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionUp), errorMessage)) {
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
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
            return 1;
        }

        int steps = MAX(1, (int)ceil(hypot(endX - startX, endY - startY) / 20.0));
        CGPoint startRatio = LoupeHIDRatio(startX, startY, width, height);
        if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, startRatio, LoupeHIDDirectionDown), errorMessage)) {
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
            if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionDown), errorMessage)) {
                // Release the same contact after a failed move; never replay it.
                CGPoint endRatio = LoupeHIDRatio(endX, endY, width, height);
                LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, endRatio, LoupeHIDDirectionUp), NULL);
                return 1;
            }
        }
        CGPoint endRatio = LoupeHIDRatio(endX, endY, width, height);
        if (!LoupeHIDSendTouchMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, endRatio, LoupeHIDDirectionUp), errorMessage)) {
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
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
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
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
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
