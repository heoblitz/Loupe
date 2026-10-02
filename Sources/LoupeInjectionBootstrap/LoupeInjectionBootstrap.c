#include <dlfcn.h>
#include <stdlib.h>
#include <TargetConditionals.h>

typedef void (*LoupeInjectorStartFunction)(void);

__attribute__((constructor))
static void LoupeInjectionBootstrap(void) {
#if (DEBUG || TARGET_OS_SIMULATOR) && TARGET_OS_IOS && !TARGET_OS_TV && !TARGET_OS_VISION && !TARGET_OS_WATCH
    // SwiftUI records concrete gesture/layout declarations only when enabled
    // before hosting views are created. Preserve an explicit caller setting.
    setenv("SWIFTUI_VIEW_DEBUG", "27", 0);
#endif
    void *symbol = dlsym(RTLD_DEFAULT, "LoupeInjectorStart");
    if (symbol == 0) {
        return;
    }

    LoupeInjectorStartFunction start = (LoupeInjectorStartFunction)symbol;
    start();
}
