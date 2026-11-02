#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loupe-dtuhid.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat >"$TEST_DIR/probe.m" <<'EOF'
#import "LoupeDTUHID.m"
#import <assert.h>

@interface MissingHIDService : NSObject
@property BOOL unsupported;
@end
@implementation MissingHIDService
- (mach_port_t)lookup:(NSString *)name error:(NSError **)error {
    *error = [NSError errorWithDomain:self.unsupported ? @"com.apple.CoreSimulator.SimError" : NSPOSIXErrorDomain
        code:self.unsupported ? 405 : 61 userInfo:nil];
    return MACH_PORT_NULL;
}
@end

int main(void) {
    @autoreleasepool {
        MissingHIDService *device = [MissingHIDService new];
        for (NSNumber *missing in @[@YES, @NO]) {
            device.unsupported = missing.boolValue;
            BOOL unsupported = NO;
            NSError *error = nil;
            assert([LoupeDTUHIDClient clientForDevice:device unsupported:&unsupported error:&error] == nil);
            assert(unsupported == missing.boolValue);
            assert(missing.boolValue || error != nil);
        }
        dispatch_queue_t queue = dispatch_queue_create("dev.loupe.test.dtuhid", DISPATCH_QUEUE_SERIAL);
        NSMutableArray *received = [NSMutableArray array];
        __block xpc_connection_t peer = nil;
        __block BOOL answerBarriers = YES;
        xpc_connection_t listener = xpc_connection_create(NULL, queue);
        xpc_connection_set_event_handler(listener, ^(xpc_object_t connection) {
            if (xpc_get_type(connection) != XPC_TYPE_CONNECTION) return;
            peer = connection;
            xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
                if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) return;
                assert(strcmp(xpc_dictionary_get_string(event, "featureIdentifier"), LoupeDTUHIDService.UTF8String) == 0);
                if (xpc_dictionary_get_bool(event, "isBarrier")) {
                    xpc_object_t payload = xpc_dictionary_get_value(event, "payload");
                    assert(xpc_dictionary_get_uint64(payload, "usageCode") == 0);
                    assert(xpc_dictionary_get_uint64(payload, "state") == 2);
                    if (answerBarriers) xpc_connection_send_message(connection, xpc_dictionary_create_reply(event));
                } else {
                    [received addObject:event];
                }
            });
            xpc_connection_resume(connection);
        });
        xpc_connection_resume(listener);
        xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
        xpc_connection_t connection = xpc_connection_create_from_endpoint(endpoint);
        LoupeDTUHIDClient *client = [[LoupeDTUHIDClient alloc] initWithConnection:connection];
        NSError *error = nil;
        assert([client confirmLivenessWithError:&error]);
        assert(received.count == 0); // Liveness must never type a character.
        assert([client sendTouchAtRatio:CGPointMake(.25, .75) direction:1 error:&error]);
        assert([client sendTouchAtRatio:CGPointMake(.5, .8) direction:1 error:&error]);
        assert([client sendTouchAtRatio:CGPointMake(.5, .8) direction:2 error:&error]);
        assert([client sendKeyCode:4 direction:1 error:&error]);
        assert([client sendKeyCode:4 direction:2 error:&error]);
        assert([client finishWithError:&error]);
        assert(received.count == 5);
        for (NSUInteger i = 0; i < 3; i++) {
            xpc_object_t message = received[i];
            assert(strcmp(xpc_dictionary_get_string(message, "messageType"), "IndigoDigitizerEvent") == 0);
            xpc_object_t payload = xpc_dictionary_get_value(message, "payload");
            assert(xpc_get_type(xpc_dictionary_get_value(payload, "eventType")) == XPC_TYPE_UINT64);
            assert(xpc_dictionary_get_uint64(payload, "eventType") == i);
            assert(xpc_dictionary_get_uint64(payload, "target") == 0);
            assert(xpc_dictionary_get_value(payload, "pointTwo") == NULL);
            xpc_object_t point = xpc_dictionary_get_value(payload, "pointOne");
            assert(xpc_get_type(xpc_dictionary_get_value(point, "x")) == XPC_TYPE_DOUBLE);
            assert(xpc_dictionary_get_double(point, "x") == (i == 0 ? .25 : .5));
        }
        for (NSUInteger i = 3; i < 5; i++) {
            xpc_object_t message = received[i];
            assert(strcmp(xpc_dictionary_get_string(message, "messageType"), "IndigoKeyboardButtonEvent") == 0);
            xpc_object_t payload = xpc_dictionary_get_value(message, "payload");
            assert(xpc_dictionary_get_uint64(payload, "usageCode") == 4);
            assert(xpc_dictionary_get_uint64(payload, "state") == i - 2);
        }
        dispatch_sync(queue, ^{ answerBarriers = NO; });
        assert(![client finishWithError:&error]);
        assert(error != nil); // A peer that stops replying must not report success.
        xpc_connection_cancel(connection);
        xpc_connection_cancel(peer);
        xpc_connection_cancel(listener);
        puts("DTUHID passed: service capability, live peer, touch phases, typed wire payloads, keyboard, completion barrier, unresponsive peer");
    }
}
EOF
xcrun clang -fobjc-arc -framework Foundation -framework CoreGraphics \
  -I "$ROOT_DIR/Sources/LoupeHID" "$TEST_DIR/probe.m" -o "$TEST_DIR/probe"
"$TEST_DIR/probe"
