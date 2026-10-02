#import "LoupeSimulatorObservation.h"
#import "LoupeSimulatorPrivate.h"
#import <CoreImage/CoreImage.h>
#import <IOSurface/IOSurface.h>
#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

static id object(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [target respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(target, selector) : nil;
}

static void failure(char **errorMessage, NSString *message) {
    if (errorMessage) *errorMessage = strdup(message.UTF8String);
}

void LoupeSimulatorFreeBuffer(void *bytes) { free(bytes); }

int LoupeSimulatorBootStatus(const char *udid, uint32_t *status, int *state, char **errorMessage) {
    @autoreleasepool { @try {
        if (!LoupeSimulatorLoadCoreSimulator(errorMessage)) return 1;
        id device = LoupeHIDDeviceForUDID([NSString stringWithUTF8String:udid], errorMessage);
        if (!device) return 1;
        id boot = object(device, @"bootStatus");
        *state = (int)((NSUInteger (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"state"));
        if (!boot) { *status = 0; return 0; }
        if (![boot respondsToSelector:NSSelectorFromString(@"status")]) {
            failure(errorMessage, @"CoreSimulator boot status is unavailable"); return 1;
        }
        *status = ((uint32_t (*)(id, SEL))objc_msgSend)(boot, NSSelectorFromString(@"status"));
        return 0;
    } @catch (NSException *exception) {
        failure(errorMessage, exception.reason ?: exception.name); return 1;
    } }
}

int LoupeSimulatorCopyPNG(const char *udid, void **bytes, size_t *count, char **errorMessage) {
    *bytes = NULL; *count = 0;
    @autoreleasepool { @try {
        if (!LoupeSimulatorLoadCoreSimulator(errorMessage)) return 1;
        id device = LoupeHIDDeviceForUDID([NSString stringWithUTF8String:udid], errorMessage);
        if (!device) return 1;
        NSArray *ports = object(object(device, @"io"), @"ioPorts");
        id mainDisplay = nil;
        for (id port in ports) {
            id descriptor = object(port, @"descriptor");
            id state = object(descriptor, @"state");
            if (![state respondsToSelector:NSSelectorFromString(@"displayClass")] ||
                ![descriptor respondsToSelector:NSSelectorFromString(@"framebufferSurface")]) continue;
            unsigned short displayClass = ((unsigned short (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"displayClass"));
            if (displayClass != 0) continue;
            if (mainDisplay) { failure(errorMessage, @"Simulator main display is ambiguous"); return 1; }
            mainDisplay = descriptor;
        }
        if (!mainDisplay) return 2;
        IOSurfaceRef surface = (__bridge IOSurfaceRef)(object(mainDisplay, @"framebufferSurface") ?: object(mainDisplay, @"ioSurface"));
        if (!surface) { failure(errorMessage, @"Simulator main display has no framebuffer"); return 1; }
        // Read the main display's composed framebuffer. App interface
        // orientation alone is not evidence of display surface orientation.
        IOSurfaceIncrementUseCount(surface);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image = NULL;
        CFMutableDataRef png = NULL;
        CGImageDestinationRef destination = NULL;
        @try {
            static CIContext *context;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ context = [[CIContext alloc] initWithOptions:nil]; });
            if (!space) { failure(errorMessage, @"Could not create framebuffer color space"); return 1; }
            CIImage *source = [CIImage imageWithIOSurface:surface options:@{kCIImageColorSpace:(__bridge id)space}];
            image = [context createCGImage:source fromRect:source.extent];
            if (!image || CGImageGetWidth(image) == 0 || CGImageGetHeight(image) == 0) {
                failure(errorMessage, @"Could not render simulator framebuffer"); return 1;
            }
            png = CFDataCreateMutable(kCFAllocatorDefault, 0);
            destination = CGImageDestinationCreateWithData(png, CFSTR("public.png"), 1, NULL);
            if (!destination) { failure(errorMessage, @"Could not encode simulator framebuffer"); return 1; }
            CGImageDestinationAddImage(destination, image, NULL);
            if (!CGImageDestinationFinalize(destination)) { failure(errorMessage, @"Incomplete framebuffer PNG"); return 1; }
            size_t length = (size_t)CFDataGetLength(png);
            void *copy = malloc(length);
            if (!copy) { failure(errorMessage, @"Could not allocate framebuffer PNG"); return 1; }
            memcpy(copy, CFDataGetBytePtr(png), length);
            *bytes = copy; *count = length;
            return 0;
        } @finally {
            if (destination) CFRelease(destination);
            if (png) CFRelease(png);
            if (image) CGImageRelease(image);
            if (space) CGColorSpaceRelease(space);
            IOSurfaceDecrementUseCount(surface);
        }
    } @catch (NSException *exception) {
        failure(errorMessage, exception.reason ?: exception.name); return 1;
    } }
}
