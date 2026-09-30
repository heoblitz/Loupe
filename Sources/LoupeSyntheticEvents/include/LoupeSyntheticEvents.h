#ifndef LOUPE_SYNTHETIC_EVENTS_H
#define LOUPE_SYNTHETIC_EVENTS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

NSObject * _Nullable LoupeSyntheticTouchBegin(CGPoint point, CGSize screenSize, NSError * _Nullable * _Nullable error);
BOOL LoupeSyntheticTouchMove(NSObject *session, CGPoint point, NSError * _Nullable * _Nullable error);
BOOL LoupeSyntheticTouchEnd(NSObject *session, NSError * _Nullable * _Nullable error);
void LoupeSyntheticTouchCancel(NSObject *session);

NS_ASSUME_NONNULL_END
#endif
