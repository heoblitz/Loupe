#ifndef LOUPE_SYNTHETIC_EVENTS_H
#define LOUPE_SYNTHETIC_EVENTS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

BOOL LoupeSyntheticTap(CGPoint point, NSError **error);
BOOL LoupeSyntheticDrag(CGPoint startPoint, CGPoint endPoint, NSTimeInterval duration, NSError **error);

NS_ASSUME_NONNULL_END

#endif
