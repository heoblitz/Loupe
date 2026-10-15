#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loupe-hid-touch.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/probe.m" <<'EOF'
#import "LoupeHID.m"
#include <assert.h>

static size_t fixtureStride;
static size_t fixtureBytes;
static unsigned char expectedMessage[512];
static LoupeIndigoMessage *fixtureMessage;
static uint32_t fixtureTarget = 0x40000007;

static LoupeIndigoMessage *messageFixture(CGPoint *point0, CGPoint *point1,
    uint32_t target, NSEventType eventType, NSSize size, uint32_t edge)
{
    assert(target == fixtureTarget);
    LoupeIndigoMessage *message = calloc(1, fixtureBytes);
    fixtureMessage = message;
    for (size_t i = 0; i < fixtureBytes; i++) ((unsigned char *)message)[i] = (unsigned char)(i * 7 + 3);
    message->innerSize = (uint32_t)fixtureStride;
    message->eventType = 2;
    message->payload.field1 = 0x0b;
    message->payload.timestamp = 123;
    message->payload.event.touch.xRatio = point0->x + ((target & 0x40000000) ? 0.125 : 0);
    message->payload.event.touch.yRatio = point0->y;
    memcpy(expectedMessage, message, fixtureBytes);
    return message;
}

int main(void)
{
    @autoreleasepool {
        size_t payloadOffset = offsetof(LoupeIndigoMessage, payload);
        for (size_t stride = 144; stride <= 192; stride += 16) {
            fixtureStride = stride;
            fixtureBytes = payloadOffset + 2 * stride;
            LoupeIndigoMessage *message = LoupeHIDTouchMessage(messageFixture, 0x40000007, CGPointMake(0.25, 0.75), 1);
            assert(message != NULL);
            assert(message->innerSize == stride);
            assert(message->eventType == 2);
            assert(message->payload.field1 == 0x0b);
            assert(message->payload.timestamp != 0);
            assert(malloc_size(message) >= payloadOffset + 2 * stride);
            assert(message == fixtureMessage);
            assert(memcmp(message, expectedMessage, fixtureBytes) == 0);
            free(message);
        }
        // Reject an undersized stride and a payload extending past its allocation.
        fixtureStride = 128;
        fixtureBytes = sizeof(LoupeIndigoMessage);
        assert(LoupeHIDTouchMessage(messageFixture, 0x40000007, CGPointMake(0.25, 0.75), 1) == NULL);
        fixtureStride = 512;
        assert(LoupeHIDTouchMessage(messageFixture, 0x40000007, CGPointMake(0.25, 0.75), 1) == NULL);
        fixtureStride = 160;
        fixtureBytes = payloadOffset + fixtureStride;
        fixtureTarget = 0x32;
        LoupeIndigoMessage *legacy = LoupeHIDTouchMessage(messageFixture, 0x32, CGPointMake(0.25, 0.75), 1);
        assert(legacy != NULL);
        assert(legacy->innerSize == fixtureStride);
        assert(legacy->eventType == 2);
        assert(legacy->payload.field1 == 0x0b);
        assert(memcmp(&legacy->payload.event, expectedMessage + offsetof(LoupeIndigoMessage, payload.event),
            fixtureStride - offsetof(LoupeIndigoPayload, event)) == 0);
        LoupeIndigoPayload *second = (void *)((char *)&legacy->payload + fixtureStride);
        assert(second->timestamp == legacy->payload.timestamp);
        assert(second->event.touch.field1 == 1);
        assert(second->event.touch.field2 == 2);
        free(legacy);
        fixtureTarget = 0x40000007;
        LoupeIndigoMessage *screen = LoupeHIDScreenMessage(messageFixture, 0x40000007, @"main-display-uid");
        assert(screen != NULL);
        assert(screen->innerSize == fixtureStride);
        assert(screen->eventType == 1);
        assert(screen->payload.field1 == 0x7fff0001);
        assert(screen->payload.timestamp != 0);
        LoupeIndigoScreenEvent *event = (void *)&screen->payload.event;
        assert(event->operation == 1);
        assert(event->target == 0x40000007);
        assert(strcmp(event->displayUID, "main-display-uid") == 0);
        assert(*((uint32_t *)((char *)screen + 0x40)) == 0x40000007);
        assert(strcmp((char *)screen + 0x44, "main-display-uid") == 0);
        free(screen);
        assert(LoupeHIDScreenMessage(messageFixture, 0x32, @"main-display-uid") == NULL);
        assert(LoupeHIDScreenMessage(messageFixture, 0x40000007, @"") == NULL);
        assert(LoupeHIDScreenMessage(messageFixture, 0x40000007,
            [@"x" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0]) == NULL);
        puts("HID touch messages passed: dynamic stride, complete event bytes, screen registration, malformed payload rejection");
    }
}
EOF

xcrun clang -fobjc-arc -framework AppKit -framework CoreImage -framework IOSurface -framework ImageIO \
  -I "$ROOT_DIR/Sources/LoupeHID" -I "$ROOT_DIR/Sources/LoupeHID/include" \
  "$TEST_DIR/probe.m" -o "$TEST_DIR/probe"
"$TEST_DIR/probe"
