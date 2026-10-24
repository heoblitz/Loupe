#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Host-side connection to the HID service supplied by modern CoreSimulator.
@interface LoupeDTUHIDClient : NSObject
+ (instancetype)clientForDevice:(id)device unsupported:(BOOL *)unsupported error:(NSError **)error;
- (BOOL)sendTouchAtRatio:(CGPoint)ratio direction:(int)direction error:(NSError **)error;
- (BOOL)sendKeyCode:(uint32_t)keyCode direction:(int)direction error:(NSError **)error;
- (BOOL)finishWithError:(NSError **)error;
@end
