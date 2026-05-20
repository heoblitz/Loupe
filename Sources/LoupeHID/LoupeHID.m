#import "LoupeHID.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <malloc/malloc.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
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
    unsigned char storage[112];
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

typedef LoupeIndigoMessage *(*LoupeKeyboardMessageFunction)(uint32_t keyCode, int operation);
typedef LoupeIndigoMessage *(*LoupeMouseMessageFunction)(CGPoint *point0, CGPoint *point1, int target, int eventType, BOOL flags);

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

static bool LoupeHIDLoadFrameworks(char **errorMessage)
{
    NSBundle *coreSimulator = [NSBundle bundleWithPath:LoupeCoreSimulatorPath];
    if (![coreSimulator load]) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load %@", LoupeCoreSimulatorPath]);
        return false;
    }

    NSString *simulatorKitPath = LoupeSimulatorKitPath();
    NSBundle *simulatorKit = [NSBundle bundleWithPath:simulatorKitPath];
    if (![simulatorKit load]) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load %@", simulatorKitPath]);
        return false;
    }

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

static id LoupeHIDDeviceForUDID(NSString *udid, char **errorMessage)
{
    Class contextClass = NSClassFromString(@"SimServiceContext");
    if (contextClass == Nil) {
        LoupeHIDSetError(errorMessage, @"CoreSimulator SimServiceContext is unavailable");
        return nil;
    }

    NSError *error = nil;
    id context = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        contextClass,
        NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),
        nil,
        &error
    );
    if (context == nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to create CoreSimulator service context: %@", error]);
        return nil;
    }

    id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(
        context,
        NSSelectorFromString(@"defaultDeviceSetWithError:"),
        &error
    );
    if (deviceSet == nil) {
        LoupeHIDSetError(errorMessage, [NSString stringWithFormat:@"failed to load CoreSimulator device set: %@", error]);
        return nil;
    }

    NSArray *devices = ((id (*)(id, SEL))objc_msgSend)(deviceSet, NSSelectorFromString(@"availableDevices"));
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

static id LoupeHIDClientForUDID(NSString *udid, char **errorMessage)
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

static CGPoint LoupeHIDRatio(double x, double y, double width, double height)
{
    return CGPointMake(x / MAX(width, 1.0), y / MAX(height, 1.0));
}

static LoupeIndigoMessage *LoupeHIDTouchMessage(LoupeMouseMessageFunction mouseMessage, CGPoint ratio, int direction)
{
    LoupeIndigoMessage *seed = mouseMessage(&ratio, NULL, LoupeHIDDigitizerTarget, direction, NO);
    seed->payload.event.touch.xRatio = ratio.x;
    seed->payload.event.touch.yRatio = ratio.y;

    size_t messageSize = sizeof(LoupeIndigoMessage) + sizeof(LoupeIndigoPayload);
    size_t stride = sizeof(LoupeIndigoPayload);
    LoupeIndigoMessage *message = calloc(1, messageSize);
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
    if (!LoupeHIDLoadFrameworks(errorMessage)) {
        return false;
    }
    if (!LoupeHIDLoadFunctions(functions, errorMessage)) {
        return false;
    }
    *client = LoupeHIDClientForUDID(udid, errorMessage);
    return *client != nil;
}

int LoupeHIDTap(const char *udid, double x, double y, double width, double height, char **errorMessage)
{
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
            return 1;
        }

        CGPoint ratio = LoupeHIDRatio(x, y, width, height);
        LoupeHIDSendMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionDown));
        usleep(50 * 1000);
        LoupeHIDSendMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionUp));
        usleep(25 * 1000);
        return 0;
    }
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
    @autoreleasepool {
        id client = nil;
        LoupeHIDFunctions functions;
        if (!LoupeHIDPrepare([NSString stringWithUTF8String:udid], &client, &functions, errorMessage)) {
            return 1;
        }

        int steps = MAX(1, (int)ceil(hypot(endX - startX, endY - startY) / 20.0));
        useconds_t stepDelay = (useconds_t)MAX(1, duration / (double)steps * 1000000.0);
        for (int index = 0; index <= steps; index += 1) {
            double progress = (double)index / (double)steps;
            double x = startX + ((endX - startX) * progress);
            double y = startY + ((endY - startY) * progress);
            CGPoint ratio = LoupeHIDRatio(x, y, width, height);
            LoupeHIDSendMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, ratio, LoupeHIDDirectionDown));
            usleep(stepDelay);
        }
        CGPoint endRatio = LoupeHIDRatio(endX, endY, width, height);
        LoupeHIDSendMessage(client, LoupeHIDTouchMessage(functions.mouseMessage, endRatio, LoupeHIDDirectionUp));
        usleep(25 * 1000);
        return 0;
    }
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
