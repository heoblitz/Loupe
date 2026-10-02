#ifndef LOUPE_HID_H
#define LOUPE_HID_H

#include "LoupeSimulatorObservation.h"

#ifdef __cplusplus
extern "C" {
#endif

// Resolve the host connection without sending input. Actions reuse this client.
int LoupeHIDInitialize(const char *udid, char **errorMessage);
int LoupeHIDTapCount(const char *udid, double x, double y, double width, double height, int count, char **errorMessage);
int LoupeHIDTap(const char *udid, double x, double y, double width, double height, char **errorMessage);
int LoupeHIDDragWithHold(const char *udid, double startX, double startY, double endX, double endY, double width, double height, double duration, double holdDuration, char **errorMessage);
int LoupeHIDDrag(
    const char *udid,
    double startX,
    double startY,
    double endX,
    double endY,
    double width,
    double height,
    double duration,
    char **errorMessage
);
int LoupeHIDType(const char *udid, const char *text, char **errorMessage);
int LoupeHIDPress(const char *udid, const char *button, char **errorMessage);
void LoupeHIDFreeCString(char *string);

#ifdef __cplusplus
}
#endif

#endif
