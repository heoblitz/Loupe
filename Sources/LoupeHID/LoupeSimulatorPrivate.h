#import <Foundation/Foundation.h>

// Shared host connection; observation never sends HID input.
bool LoupeHIDLoadFrameworks(char **errorMessage);
bool LoupeSimulatorLoadCoreSimulator(char **errorMessage);
id LoupeHIDDeviceForUDID(NSString *udid, char **errorMessage);
