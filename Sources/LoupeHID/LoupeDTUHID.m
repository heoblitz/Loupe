#import "LoupeDTUHID.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <objc/message.h>
#import <xpc/xpc.h>

// Protocol and simulator endpoint discovery references:
// https://github.com/facebook/idb/tree/main/FBSimulatorControl/HID
// https://github.com/facebook/idb/blob/main/FBSimulatorControl/XPC/SimulatorXPCConnection.swift
static NSString * const LoupeDTUHIDService = @"com.apple.coredevice.feature.remote.hid.digitizer";
typedef void *(*LoupeEndpointFromPort)(mach_port_t, uint64_t, uint64_t);
typedef void (*LoupeEnableSim2Host)(xpc_connection_t);

static NSError *LoupeDTUHIDError(NSString *message)
{
    return [NSError errorWithDomain:@"dev.loupe.DTUHID" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static xpc_object_t LoupeDTUHIDMessage(const char *type, xpc_object_t payload, bool barrier)
{
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "messageType", type);
    xpc_dictionary_set_bool(message, "isBarrier", barrier);
    xpc_dictionary_set_string(message, "featureIdentifier", LoupeDTUHIDService.UTF8String);
    xpc_dictionary_set_value(message, "payload", payload);
    return message;
}

@interface LoupeDTUHIDClient () {
    xpc_connection_t _connection;
    dispatch_queue_t _queue;
    NSLock *_failureLock;
    NSError *_failure;
    BOOL _contactActive;
}
- (instancetype)initWithConnection:(xpc_connection_t)connection;
- (BOOL)confirmLivenessWithError:(NSError **)error;
@end

@implementation LoupeDTUHIDClient

+ (instancetype)clientForDevice:(id)device unsupported:(BOOL *)unsupported error:(NSError **)error
{
    *unsupported = NO;
    SEL lookup = NSSelectorFromString(@"lookup:error:");
    if (![device respondsToSelector:lookup]) {
        *unsupported = YES;
        return nil;
    }
    NSError *lookupError = nil;
    mach_port_t port = ((mach_port_t (*)(id, SEL, id, NSError **))objc_msgSend)(
        device, lookup, LoupeDTUHIDService, &lookupError);
    if (port == MACH_PORT_NULL) {
        // Only a known missing service permits legacy input. A boot/startup or
        // connection failure must not turn into a successful but lost gesture.
        *unsupported = [lookupError.domain isEqualToString:@"com.apple.CoreSimulator.SimError"] && lookupError.code == 405;
        if (!*unsupported && error) *error = lookupError ?: LoupeDTUHIDError(@"DTUHID service lookup failed");
        return nil;
    }
    LoupeEndpointFromPort endpointFromPort = (LoupeEndpointFromPort)dlsym(RTLD_DEFAULT, "xpc_endpoint_create_mach_port_4sim");
    LoupeEnableSim2Host enable = (LoupeEnableSim2Host)dlsym(RTLD_DEFAULT, "xpc_connection_enable_sim2host_4sim");
    if (!endpointFromPort || !enable) {
        mach_port_deallocate(mach_task_self(), port);
        if (error) *error = LoupeDTUHIDError(@"DTUHID simulator XPC endpoint symbols are unavailable");
        return nil;
    }
    // The endpoint consumes the send right returned by SimDevice.lookup.
    xpc_endpoint_t endpoint = (__bridge_transfer xpc_endpoint_t)endpointFromPort(port, 0, 0);
    xpc_connection_t connection = endpoint ? xpc_connection_create_from_endpoint(endpoint) : nil;
    if (!connection) {
        if (error) *error = LoupeDTUHIDError(@"failed to create DTUHID simulator connection");
        return nil;
    }
    enable(connection);
    LoupeDTUHIDClient *client = [[self alloc] initWithConnection:connection];
    if (![client confirmLivenessWithError:error]) return nil;
    if ([NSProcessInfo.processInfo.environment[@"LOUPE_HID_DIAGNOSTICS"] isEqualToString:@"1"]) {
        fprintf(stderr, "loupe.hid.transport backend=dtuhid service=%s responsive=1\n", LoupeDTUHIDService.UTF8String);
    }
    return client;
}

- (instancetype)initWithConnection:(xpc_connection_t)connection
{
    if ((self = [super init])) {
        _connection = connection;
        _queue = dispatch_queue_create("dev.loupe.dtuhid", DISPATCH_QUEUE_SERIAL);
        _failureLock = [[NSLock alloc] init];
        xpc_connection_set_target_queue(connection, _queue);
        __weak LoupeDTUHIDClient *weakSelf = self;
        xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
            if (xpc_get_type(event) != XPC_TYPE_ERROR) return;
            LoupeDTUHIDClient *client = weakSelf;
            if (!client) return;
            const char *detail = xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION);
            [client->_failureLock lock];
            client->_failure = LoupeDTUHIDError([NSString stringWithFormat:@"DTUHID connection failed: %s", detail ?: "unknown XPC error"]);
            [client->_failureLock unlock];
        });
        xpc_connection_resume(connection);
    }
    return self;
}

- (void)dealloc
{
    xpc_connection_cancel(_connection);
}

- (BOOL)checkConnectionWithError:(NSError **)error
{
    [_failureLock lock];
    NSError *failure = _failure;
    [_failureLock unlock];
    if (failure && error) *error = failure;
    return failure == nil;
}

- (BOOL)confirmLivenessWithError:(NSError **)error
{
    if (![self checkConnectionWithError:error]) return NO;
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    // A barrier is a separate no-event message. Marking a real input as a
    // barrier acknowledges it without delivering that input to the guest.
    xpc_dictionary_set_uint64(payload, "usageCode", 0);
    xpc_dictionary_set_uint64(payload, "state", 2);
    xpc_object_t message = LoupeDTUHIDMessage("IndigoKeyboardButtonEvent", payload, true);
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    __block NSError *replyError = nil;
    xpc_connection_send_message_with_reply(_connection, message, _queue, ^(xpc_object_t reply) {
        if (xpc_get_type(reply) == XPC_TYPE_ERROR) {
            const char *detail = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION);
            replyError = LoupeDTUHIDError([NSString stringWithFormat:@"DTUHID did not answer: %s", detail ?: "unknown XPC error"]);
        }
        dispatch_semaphore_signal(completed);
    });
    if (dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) != 0) {
        if (error) *error = LoupeDTUHIDError(@"DTUHID service did not answer its liveness barrier within 4 seconds");
        return NO;
    }
    if (replyError && error) *error = replyError;
    return replyError == nil;
}

- (BOOL)sendTouchAtRatio:(CGPoint)ratio direction:(int)direction error:(NSError **)error
{
    if (![self checkConnectionWithError:error]) return NO;
    uint64_t phase = direction == 2 ? 2 : (_contactActive ? 1 : 0);
    _contactActive = direction != 2;
    xpc_object_t point = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_double(point, "x", ratio.x);
    xpc_dictionary_set_double(point, "y", ratio.y);
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_value(payload, "pointOne", point);
    xpc_dictionary_set_uint64(payload, "eventType", phase);
    xpc_dictionary_set_uint64(payload, "edge", 0);
    xpc_dictionary_set_uint64(payload, "target", 0);
    xpc_connection_send_message(_connection, LoupeDTUHIDMessage("IndigoDigitizerEvent", payload, false));
    return YES;
}

- (BOOL)sendKeyCode:(uint32_t)keyCode direction:(int)direction error:(NSError **)error
{
    if (![self checkConnectionWithError:error]) return NO;
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(payload, "usageCode", keyCode);
    xpc_dictionary_set_uint64(payload, "state", direction);
    xpc_connection_send_message(_connection, LoupeDTUHIDMessage("IndigoKeyboardButtonEvent", payload, false));
    return YES;
}

- (BOOL)finishWithError:(NSError **)error
{
    // Confirm that the daemon consumed this connection's preceding messages
    // before releasing it. A local XPC send acknowledgement cannot prove that.
    return [self confirmLivenessWithError:error];
}

@end
