#import "LoupeSyntheticEvents.h"

#import <TargetConditionals.h>

#if TARGET_OS_IOS && !TARGET_OS_TV && !TARGET_OS_VISION && !TARGET_OS_WATCH

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>

typedef double IOHIDFloat;
typedef uint32_t IOHIDDigitizerEventMask;
typedef uint32_t IOHIDDigitizerTransducerType;
typedef uint32_t IOHIDEventField;
typedef uint32_t IOHIDEventOptionBits;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct {
    unsigned char _firstTouchForView : 1;
} LoupeUITouchFlags;

enum {
    LoupeIOHIDDigitizerTransducerTypeHand = 3,
    LoupeIOHIDDigitizerEventRange = 0x00000001,
    LoupeIOHIDDigitizerEventTouch = 0x00000002,
    LoupeIOHIDDigitizerEventPosition = 0x00000004,
    LoupeIOHIDEventTypeDigitizer = 11,
    LoupeIOHIDEventFieldDigitizerIsDisplayIntegrated =
        (LoupeIOHIDEventTypeDigitizer << 16) + 25,
};

IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator,
    uint64_t timestamp,
    IOHIDDigitizerTransducerType transducerType,
    uint32_t index,
    uint32_t identifier,
    IOHIDDigitizerEventMask eventMask,
    uint32_t buttonEvent,
    IOHIDFloat x,
    IOHIDFloat y,
    IOHIDFloat z,
    IOHIDFloat tipPressure,
    IOHIDFloat twist,
    boolean_t range,
    boolean_t touch,
    IOHIDEventOptionBits options
);
IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator,
    uint64_t timestamp,
    uint32_t index,
    uint32_t identifier,
    IOHIDDigitizerEventMask eventMask,
    IOHIDFloat x,
    IOHIDFloat y,
    IOHIDFloat z,
    IOHIDFloat tipPressure,
    IOHIDFloat twist,
    boolean_t range,
    boolean_t touch,
    IOHIDEventOptionBits options
);
void IOHIDEventAppendEvent(IOHIDEventRef event, IOHIDEventRef childEvent, IOHIDEventOptionBits options);
void IOHIDEventSetIntegerValue(IOHIDEventRef event, IOHIDEventField field, CFIndex value);

@interface UIApplication (LoupeSyntheticPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UIEvent (LoupeSyntheticPrivate)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayedDelivery;
- (void)_clearTouches;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UITouch (LoupeSyntheticPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setLocationInWindow:(CGPoint)point resetPrevious:(BOOL)resetPrevious;
- (void)_setHidEvent:(IOHIDEventRef)event;
- (void)_setIsTapToClick:(BOOL)value;
- (void)setIsTap:(BOOL)value;
- (void)setIsDelayed:(BOOL)value;
- (void)_setPathIndex:(NSUInteger)value;
- (void)_setPathIdentity:(NSUInteger)value;
- (void)_setSenderID:(uint64_t)value;
@end

static NSString * const LoupeSyntheticEventsErrorDomain = @"dev.loupe.synthetic-events";

static NSError *LoupeSyntheticError(NSString *message)
{
    return [NSError errorWithDomain:LoupeSyntheticEventsErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static uint64_t LoupeMachTimeFromSeconds(CFTimeInterval seconds)
{
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebase);
    });
    uint64_t nanoseconds = (uint64_t)(seconds * (CFTimeInterval)NSEC_PER_SEC);
    return nanoseconds * timebase.denom / timebase.numer;
}

static UIWindow *LoupeKeyWindow(void)
{
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            if (windowScene.windows.count > 0) {
                return windowScene.windows.firstObject;
            }
        }
    }

    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (keyWindow) {
        return keyWindow;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void LoupeSetFirstTouchFlag(UITouch *touch)
{
    if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) {
        [touch _setIsTapToClick:YES];
    } else if ([touch respondsToSelector:@selector(setIsTap:)]) {
        [touch setIsTap:YES];
    }

    Ivar flagsIvar = class_getInstanceVariable(UITouch.class, "_touchFlags");
    if (!flagsIvar) {
        return;
    }
    typedef LoupeUITouchFlags (*LoupeUITouchFlagsGetFunction)(id object, Ivar ivar);
    typedef void (*LoupeUITouchFlagsSetFunction)(id object, Ivar ivar, LoupeUITouchFlags flags);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    LoupeUITouchFlagsGetFunction getFlags = (LoupeUITouchFlagsGetFunction)object_getIvar;
    LoupeUITouchFlagsSetFunction setFlags = (LoupeUITouchFlagsSetFunction)(void *)object_setIvar;
#pragma clang diagnostic pop
    LoupeUITouchFlags flags = getFlags(touch, flagsIvar);
    flags._firstTouchForView = 1;
    setFlags(touch, flagsIvar, flags);
}

static IOHIDDigitizerEventMask LoupeEventMask(UITouchPhase phase)
{
    switch (phase) {
    case UITouchPhaseMoved:
    case UITouchPhaseStationary:
        return LoupeIOHIDDigitizerEventPosition;
    case UITouchPhaseCancelled:
    case UITouchPhaseEnded:
    case UITouchPhaseBegan:
    default:
        return LoupeIOHIDDigitizerEventRange | LoupeIOHIDDigitizerEventTouch;
    }
}

static BOOL LoupeIsTouching(UITouchPhase phase)
{
    return phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled;
}

static void LoupeMarkIntegratedDisplay(IOHIDEventRef event)
{
#if TARGET_IPHONE_SIMULATOR
    IOHIDEventSetIntegerValue(event, LoupeIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
#else
    IOHIDEventSetIntegerValue(event, LoupeIOHIDEventFieldDigitizerIsDisplayIntegrated, 0);
#endif
}

static UITouch *LoupeTouchForPoint(CGPoint point, UIWindow *window, UIEvent *event)
{
    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:window];
    [touch setTapCount:1];
    if ([touch respondsToSelector:@selector(setIsDelayed:)]) {
        [touch setIsDelayed:NO];
    }
    if ([touch respondsToSelector:@selector(_setPathIndex:)]) {
        [touch _setPathIndex:1];
    }
    if ([touch respondsToSelector:@selector(_setPathIdentity:)]) {
        [touch _setPathIdentity:2];
    }
    if ([touch respondsToSelector:@selector(_setSenderID:)]) {
        [touch _setSenderID:0x0acefade00000002];
    }
    UIView *view = [window hitTest:point withEvent:event];
    [touch setView:view ?: window];
    LoupeSetFirstTouchFlag(touch);
    return touch;
}

static BOOL LoupeSendTouch(UITouch *touch, CGPoint point, UITouchPhase phase, UIWindow *window, NSError **error)
{
    UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
    if (!event) {
        if (error) {
            *error = LoupeSyntheticError(@"UIApplication did not provide a touches event.");
        }
        return NO;
    }

    CFTimeInterval timestamp = CACurrentMediaTime();
    uint64_t deliveryTime = LoupeMachTimeFromSeconds(timestamp);
    BOOL touching = LoupeIsTouching(phase);
    IOHIDDigitizerEventMask eventMask = LoupeEventMask(phase);

    [touch setPhase:phase];
    [touch setTimestamp:timestamp];
    [touch _setLocationInWindow:point resetPrevious:(phase == UITouchPhaseBegan)];
    if (!touch.view) {
        [touch setView:[window hitTest:point withEvent:event] ?: window];
    }

    IOHIDEventRef hidEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        deliveryTime,
        LoupeIOHIDDigitizerTransducerTypeHand,
        1,
        2,
        eventMask,
        0,
        0,
        0,
        0,
        0,
        0,
        touching,
        touching,
        0
    );
    LoupeMarkIntegratedDisplay(hidEvent);

    IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault,
        deliveryTime,
        1,
        2,
        eventMask,
        point.x,
        point.y,
        0,
        0,
        0,
        touching,
        touching,
        0
    );
    LoupeMarkIntegratedDisplay(fingerEvent);
    IOHIDEventAppendEvent(hidEvent, fingerEvent, 0);
    if ([touch respondsToSelector:@selector(_setHidEvent:)]) {
        [touch _setHidEvent:fingerEvent];
    }

    [event _clearTouches];
    [event _addTouch:touch forDelayedDelivery:NO];
    [event _setHIDEvent:hidEvent];

    @try {
        @autoreleasepool {
            [UIApplication.sharedApplication sendEvent:event];
        }
    } @catch (NSException *exception) {
        if (error) {
            *error = LoupeSyntheticError([NSString stringWithFormat:@"Synthetic touch delivery failed: %@", exception.reason]);
        }
        CFRelease(fingerEvent);
        CFRelease(hidEvent);
        return NO;
    }

    [event _setHIDEvent:NULL];
    CFRelease(fingerEvent);
    CFRelease(hidEvent);
    return YES;
}

BOOL LoupeSyntheticTap(CGPoint point, NSError **error)
{
    UIWindow *window = LoupeKeyWindow();
    if (!window) {
        if (error) {
            *error = LoupeSyntheticError(@"No active UIWindow found for synthetic tap.");
        }
        return NO;
    }
    UIEvent *seedEvent = [UIApplication.sharedApplication _touchesEvent];
    UITouch *touch = LoupeTouchForPoint(point, window, seedEvent);
    return LoupeSendTouch(touch, point, UITouchPhaseBegan, window, error)
        && LoupeSendTouch(touch, point, UITouchPhaseEnded, window, error);
}

BOOL LoupeSyntheticDrag(CGPoint startPoint, CGPoint endPoint, NSTimeInterval duration, NSError **error)
{
    UIWindow *window = LoupeKeyWindow();
    if (!window) {
        if (error) {
            *error = LoupeSyntheticError(@"No active UIWindow found for synthetic drag.");
        }
        return NO;
    }
    UIEvent *seedEvent = [UIApplication.sharedApplication _touchesEvent];
    UITouch *touch = LoupeTouchForPoint(startPoint, window, seedEvent);
    if (!LoupeSendTouch(touch, startPoint, UITouchPhaseBegan, window, error)) {
        return NO;
    }

    NSInteger steps = MAX(1, (NSInteger)ceil(hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) / 20.0));
    NSTimeInterval stepDelay = MAX(0.001, duration / (NSTimeInterval)steps);
    for (NSInteger index = 1; index <= steps; index += 1) {
        CGFloat progress = (CGFloat)index / (CGFloat)steps;
        CGPoint point = CGPointMake(
            startPoint.x + (endPoint.x - startPoint.x) * progress,
            startPoint.y + (endPoint.y - startPoint.y) * progress
        );
        if (!LoupeSendTouch(touch, point, UITouchPhaseMoved, window, error)) {
            return NO;
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:stepDelay]];
    }

    return LoupeSendTouch(touch, endPoint, UITouchPhaseEnded, window, error);
}

#else

BOOL LoupeSyntheticTap(CGPoint point, NSError **error)
{
    (void)point;
    if (error) {
        *error = [NSError errorWithDomain:@"dev.loupe.synthetic-events"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Synthetic UIKit touch events are unavailable on this platform."}];
    }
    return NO;
}

BOOL LoupeSyntheticDrag(CGPoint startPoint, CGPoint endPoint, NSTimeInterval duration, NSError **error)
{
    (void)startPoint;
    (void)endPoint;
    (void)duration;
    if (error) {
        *error = [NSError errorWithDomain:@"dev.loupe.synthetic-events"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Synthetic UIKit touch events are unavailable on this platform."}];
    }
    return NO;
}

#endif
