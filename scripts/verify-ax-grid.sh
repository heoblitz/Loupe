#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loupe-ax-grid.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat >"$TEST_DIR/probe.m" <<'OBJC'
#import "LoupeHID.m"
#include <assert.h>

@interface GridRequest : NSObject
@property(nonatomic) NSNumber *requestType;
@property(nonatomic) NSDictionary *parameters;
+ (instancetype)requestWithTranslation:(id)translation;
@end
@implementation GridRequest
+ (instancetype)requestWithTranslation:(id)translation { return [self new]; }
@end
@interface GridResponse : NSObject
@property(nonatomic) NSNumber *error;
@property(nonatomic) id resultData;
@end
@implementation GridResponse
@end
@interface GridDevice : NSObject
@property(nonatomic) NSUInteger active;
@property(nonatomic) NSUInteger peak;
@property(nonatomic) BOOL slow;
@property(nonatomic) BOOL fail;
- (void)sendAccessibilityRequestAsync:(GridRequest *)request completionQueue:(dispatch_queue_t)queue completionHandler:(void (^)(id))handler;
@end
@implementation GridDevice
- (void)sendAccessibilityRequestAsync:(GridRequest *)request completionQueue:(dispatch_queue_t)queue completionHandler:(void (^)(id))handler {
    NSPoint point = [request.parameters[@"point"] pointValue];
    NSUInteger index = (NSUInteger)((point.y - 12.5) / 25) * 10 + (NSUInteger)((point.x - 12.5) / 25);
    @synchronized (self) { self.active++; self.peak = MAX(self.peak, self.active); }
    double delay = self.slow ? 0.2 : (double)(4 - index % 4) * 0.002;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, ^{
        GridResponse *response = [GridResponse new];
        response.error = self.fail ? @42 : (index == 7 ? @8 : @0);
        response.resultData = @(index);
        @synchronized (self) { self.active--; }
        handler(response);
    });
}
@end
int main(void) {
    @autoreleasepool {
        GridDevice *device = [GridDevice new];
        char *error = NULL;
        NSArray *hits = LoupeAXGridHits(device, GridRequest.class, NSObject.class, 0, 0, 10, 200, NSProcessInfo.processInfo.systemUptime + 3, &error);
        assert(hits.count == 200 && error == NULL);
        for (NSUInteger i = 0; i < hits.count; i++) {
            if (i == 7) assert(hits[i] == [NSNull null]);
            else assert([hits[i] unsignedIntegerValue] == i);
        }
        assert(device.peak > 1 && device.peak <= 64);
        device.fail = YES;
        assert(LoupeAXGridHits(device, GridRequest.class, NSObject.class, 0, 0, 10, 1, NSProcessInfo.processInfo.systemUptime + 3, &error) == nil);
        assert(error && strstr(error, "42")); free(error); error = NULL;
        device.fail = NO; device.slow = YES;
        assert(LoupeAXGridHits(device, GridRequest.class, NSObject.class, 0, 0, 10, 100, NSProcessInfo.processInfo.systemUptime + 0.02, &error) == nil);
        assert(error && strstr(error, "timed out")); free(error);
        // Let callbacks arriving after the timeout run before exiting.
        [NSThread sleepForTimeInterval:0.3];
        puts("AX grid passed: bounded concurrency, out-of-order responses, empty hits, errors, and timeout");
    }
}
OBJC
xcrun clang -fobjc-arc -framework AppKit -framework CoreImage -framework IOSurface -framework ImageIO \
  -I "$ROOT_DIR/Sources/LoupeHID" -I "$ROOT_DIR/Sources/LoupeHID/include" \
  "$TEST_DIR/probe.m" "$ROOT_DIR/Sources/LoupeHID/LoupeDTUHID.m" -o "$TEST_DIR/probe"
"$TEST_DIR/probe"
