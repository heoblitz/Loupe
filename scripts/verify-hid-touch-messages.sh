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

static LoupeIndigoMessage *messageFixture(CGPoint *point0, CGPoint *point1,
    uint32_t target, NSEventType eventType, NSSize size, uint32_t edge)
{
    assert(target == 0x32);
    LoupeIndigoMessage *message = calloc(1, fixtureBytes);
    for (size_t i = 0; i < fixtureBytes; i++) ((unsigned char *)message)[i] = (unsigned char)(i * 7 + 3);
    message->innerSize = (uint32_t)fixtureStride;
    message->eventType = 2;
    message->payload.field1 = 0x0b;
    message->payload.timestamp = 123;
    message->payload.event.touch.xRatio = point0->x;
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
            fixtureBytes = payloadOffset + stride;
            LoupeIndigoMessage *message = LoupeHIDTouchMessage(messageFixture, CGPointMake(0.25, 0.75), 1);
            assert(message != NULL);
            assert(message->innerSize == stride);
            assert(message->eventType == 2);
            assert(message->payload.field1 == 0x0b);
            assert(message->payload.timestamp != 0 && message->payload.timestamp != 123);
            assert(malloc_size(message) >= payloadOffset + 2 * stride);
            assert(memcmp(&message->payload.event, expectedMessage + offsetof(LoupeIndigoMessage, payload.event),
                stride - offsetof(LoupeIndigoPayload, event)) == 0);
            LoupeIndigoPayload *second = (void *)((char *)&message->payload + stride);
            assert(second->timestamp == message->payload.timestamp);
            assert(second->event.touch.field1 == 1);
            assert(second->event.touch.field2 == 2);
            free(message);
        }
        fixtureStride = 128;
        fixtureBytes = sizeof(LoupeIndigoMessage);
        assert(LoupeHIDTouchMessage(messageFixture, CGPointMake(0.25, 0.75), 1) == NULL);
        fixtureStride = 512;
        assert(LoupeHIDTouchMessage(messageFixture, CGPointMake(0.25, 0.75), 1) == NULL);
        puts("HID touch messages passed: legacy target, dynamic stride, complete event bytes, duplicated contacts, malformed payload rejection");
    }
}
EOF

xcrun clang -fobjc-arc -framework AppKit -framework CoreImage -framework IOSurface -framework ImageIO \
  -I "$ROOT_DIR/Sources/LoupeHID" -I "$ROOT_DIR/Sources/LoupeHID/include" \
  "$TEST_DIR/probe.m" "$ROOT_DIR/Sources/LoupeHID/LoupeDTUHID.m" -o "$TEST_DIR/probe"
"$TEST_DIR/probe"
