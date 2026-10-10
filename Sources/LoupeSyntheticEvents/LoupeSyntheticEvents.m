#import "LoupeSyntheticEvents.h"

#import <TargetConditionals.h>

#if (DEBUG || TARGET_OS_SIMULATOR) && TARGET_OS_IOS && !TARGET_OS_TV && !TARGET_OS_VISION && !TARGET_OS_WATCH

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
enum {
    LoupeIOHIDDigitizerTransducerTypeHand = 3,
    LoupeIOHIDDigitizerEventRange = 0x00000001,
    LoupeIOHIDDigitizerEventTouch = 0x00000002,
    LoupeIOHIDDigitizerEventPosition = 0x00000004,
    LoupeIOHIDEventTypeDigitizer = 11,
    LoupeIOHIDEventFieldDigitizerIsDisplayIntegrated =
        (LoupeIOHIDEventTypeDigitizer << 16) + 25,
};

IOHIDEventRef __attribute__((weak_import)) IOHIDEventCreateDigitizerEvent(
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
IOHIDEventRef __attribute__((weak_import)) IOHIDEventCreateDigitizerFingerEvent(
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
void __attribute__((weak_import)) IOHIDEventAppendEvent(IOHIDEventRef event, IOHIDEventRef childEvent, IOHIDEventOptionBits options);
void __attribute__((weak_import)) IOHIDEventSetIntegerValue(IOHIDEventRef event, IOHIDEventField field, CFIndex value);

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
- (void)_setIsFirstTouchForView:(BOOL)value;
- (void)setGestureView:(id)view;
- (void)setIsDelayed:(BOOL)value;
- (void)_setPathIndex:(NSUInteger)value;
- (void)_setPathIdentity:(NSUInteger)value;
- (void)_setSenderID:(uint64_t)value;
@end

@interface UIView (LoupeSyntheticHitTesting)
- (id)_hitTestWithContext:(id)context;
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
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && !window.hidden && window.alpha > 0) return window;
        }
    }
    return nil;
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

static UITouch *LoupeTouchForPoint(CGPoint point, UIWindow *window, UIEvent *event, NSUInteger tapCount)
{
    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:window];
    [touch setTapCount:tapCount];
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
    id responder = view;
    // iOS 18 introduced gesture responders inside SwiftUI hosting views. A
    // UIView-only hit test stops before the Button's actual gesture recipient.
    // API behavior is also documented by kif-framework/KIF PR #1323.
    if (@available(iOS 18.0, *)) {
        Class contextClass = NSClassFromString(@"_UIHitTestContext");
        SEL makeContext = NSSelectorFromString(@"contextWithPoint:radius:");
        if ([contextClass respondsToSelector:makeContext]) {
            typedef id (*MakeContext)(id, SEL, CGPoint, CGFloat);
            MakeContext make = (MakeContext)[contextClass methodForSelector:makeContext];
            id context = make(contextClass, makeContext, point, 0);
            for (UIView *ancestor = view; context && ancestor; ancestor = ancestor.superview) {
                if (![ancestor respondsToSelector:@selector(_hitTestWithContext:)]) continue;
                id candidate = [ancestor _hitTestWithContext:context];
                if (candidate) {
                    responder = candidate;
                    break;
                }
            }
        }
    }
    [touch setView:responder];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:responder];
    // UIControl tracking requires a first touch for this view, in addition to
    // the began phase used by gesture recognizers.
    [touch _setIsFirstTouchForView:YES];
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
    if (!hidEvent) {
        if (error) *error = LoupeSyntheticError(@"Could not allocate a digitizer event.");
        return NO;
    }
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
    if (!fingerEvent) {
        CFRelease(hidEvent);
        if (error) *error = LoupeSyntheticError(@"Could not allocate a finger event.");
        return NO;
    }
    LoupeMarkIntegratedDisplay(fingerEvent);
    IOHIDEventAppendEvent(hidEvent, fingerEvent, 0);
    if ([touch respondsToSelector:@selector(_setHidEvent:)]) {
        [touch _setHidEvent:fingerEvent];
    }

    BOOL succeeded = NO;
    @try {
        [event _clearTouches];
        [event _addTouch:touch forDelayedDelivery:NO];
        [event _setHIDEvent:hidEvent];
        [UIApplication.sharedApplication sendEvent:event];
        succeeded = YES;
    } @catch (NSException *exception) {
        if (error) *error = LoupeSyntheticError([NSString stringWithFormat:@"Synthetic touch delivery failed: %@", exception.reason]);
    } @finally {
        [event _setHIDEvent:NULL];
        CFRelease(fingerEvent);
        CFRelease(hidEvent);
    }
    return succeeded;
}

@interface LoupeTouchSession : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UITouch *touch;
@property(nonatomic) CGPoint point;
@property(nonatomic) BOOL active;
@end
@implementation LoupeTouchSession
@end

static BOOL LoupeTouchAPIsAvailable(void)
{
    if (!IOHIDEventCreateDigitizerEvent || !IOHIDEventCreateDigitizerFingerEvent ||
        !IOHIDEventAppendEvent || !IOHIDEventSetIntegerValue) return NO;
    UIApplication *app = UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(_touchesEvent)]) return NO;
    UIEvent *event = [app _touchesEvent];
    UITouch *touch = [[UITouch alloc] init];
    return event && [event respondsToSelector:@selector(_addTouch:forDelayedDelivery:)] &&
        [event respondsToSelector:@selector(_clearTouches)] && [event respondsToSelector:@selector(_setHIDEvent:)] &&
        [touch respondsToSelector:@selector(setWindow:)] && [touch respondsToSelector:@selector(setView:)] &&
        [touch respondsToSelector:@selector(setTapCount:)] && [touch respondsToSelector:@selector(setPhase:)] &&
        [touch respondsToSelector:@selector(_setIsFirstTouchForView:)] &&
        [touch respondsToSelector:@selector(setTimestamp:)] && [touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)];
}

BOOL LoupeGestureHasTargets(NSObject *gesture)
{
    @try { return [[gesture valueForKey:@"_targets"] count] > 0; }
    @catch (NSException *exception) { return NO; }
}

NSObject *LoupeSyntheticTouchBegin(CGPoint point, CGSize screenSize, NSError **error)
{
    return LoupeSyntheticTouchBeginWithTapCount(point, screenSize, 1, error);
}

NSObject *LoupeSyntheticTouchBeginWithTapCount(CGPoint point, CGSize screenSize, NSUInteger tapCount, NSError **error)
{
    NSCAssert(NSThread.isMainThread, @"Touch delivery requires the main thread");
    @try {
        UIWindow *window = LoupeKeyWindow();
        if (!window || !LoupeTouchAPIsAvailable()) {
            if (error) *error = LoupeSyntheticError(@"A foreground key window and supported private touch APIs are required.");
            return nil;
        }
        CGSize actual = window.screen.bounds.size;
        if (fabs(actual.width - screenSize.width) > 0.5 || fabs(actual.height - screenSize.height) > 0.5) {
            if (error) *error = LoupeSyntheticError(@"Screen size changed; resolve the target again before touching.");
            return nil;
        }
        CGPoint local = [window convertPoint:point fromCoordinateSpace:window.screen.coordinateSpace];
        if (!CGRectContainsPoint(window.bounds, local) || ![window hitTest:local withEvent:nil]) {
            if (error) *error = LoupeSyntheticError(@"Touch point does not hit the foreground window.");
            return nil;
        }
        LoupeTouchSession *session = [LoupeTouchSession new];
        session.window = window;
        session.point = local;
        session.touch = LoupeTouchForPoint(local, window, [UIApplication.sharedApplication _touchesEvent], tapCount);
        session.active = YES;
        if (!LoupeSendTouch(session.touch, local, UITouchPhaseBegan, window, error)) {
            LoupeSyntheticTouchCancel(session);
            return nil;
        }
        return session;
    } @catch (NSException *exception) {
        if (error) *error = LoupeSyntheticError([NSString stringWithFormat:@"Touch setup failed: %@", exception.reason]);
        return nil;
    }
}

BOOL LoupeSyntheticTouchMove(NSObject *object, CGPoint point, NSError **error)
{
    LoupeTouchSession *session = (LoupeTouchSession *)object;
    @try {
        if (!session.active || LoupeKeyWindow() != session.window) {
            if (error) *error = LoupeSyntheticError(@"Foreground window changed during touch delivery.");
            return NO;
        }
        session.point = [session.window convertPoint:point fromCoordinateSpace:session.window.screen.coordinateSpace];
        return LoupeSendTouch(session.touch, session.point, UITouchPhaseMoved, session.window, error);
    } @catch (NSException *exception) {
        if (error) *error = LoupeSyntheticError([NSString stringWithFormat:@"Touch movement failed: %@", exception.reason]);
        return NO;
    }
}

BOOL LoupeSyntheticTouchEnd(NSObject *object, NSError **error)
{
    LoupeTouchSession *session = (LoupeTouchSession *)object;
    @try {
        if (!session.active || LoupeKeyWindow() != session.window) {
            if (error) *error = LoupeSyntheticError(@"Foreground window changed during touch delivery.");
            return NO;
        }
        BOOL result = LoupeSendTouch(session.touch, session.point, UITouchPhaseEnded, session.window, error);
        if (result) session.active = NO;
        return result;
    } @catch (NSException *exception) {
        if (error) *error = LoupeSyntheticError([NSString stringWithFormat:@"Touch ending failed: %@", exception.reason]);
        return NO;
    }
}

void LoupeSyntheticTouchCancel(NSObject *object)
{
    LoupeTouchSession *session = (LoupeTouchSession *)object;
    if (!session.active) return;
    @try {
        LoupeSendTouch(session.touch, session.point, UITouchPhaseCancelled, session.window, nil);
    } @catch (__unused NSException *exception) {
    }
    session.active = NO;
}

#else

static void LoupeUnavailable(NSError **error)
{
    if (error) *error = [NSError errorWithDomain:@"dev.loupe.synthetic-events" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Touch input requires an iOS Debug build of LoupeInjector."}];
}
BOOL LoupeGestureHasTargets(NSObject *gesture) { return NO; }
NSObject *LoupeSyntheticTouchBegin(CGPoint point, CGSize screenSize, NSError **error)
{
    return LoupeSyntheticTouchBeginWithTapCount(point, screenSize, 1, error);
}

NSObject *LoupeSyntheticTouchBeginWithTapCount(CGPoint point, CGSize screenSize, NSUInteger tapCount, NSError **error)
{
    LoupeUnavailable(error);
    return nil;
}
BOOL LoupeSyntheticTouchMove(NSObject *session, CGPoint point, NSError **error)
{
    LoupeUnavailable(error);
    return NO;
}
BOOL LoupeSyntheticTouchEnd(NSObject *session, NSError **error)
{
    LoupeUnavailable(error);
    return NO;
}
void LoupeSyntheticTouchCancel(NSObject *session) {}
#endif
