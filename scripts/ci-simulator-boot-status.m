#import <Foundation/Foundation.h>
#import "LoupeSimulatorObservation.h"
#import "LoupeHID.h"
#include <mach/mach_time.h>
#include <pthread/qos.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

static uint64_t monotonicNS(void) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    return (uint64_t)(((__uint128_t)mach_absolute_time() * timebase.numer) / timebase.denom);
}

// CI observation helper, compiled for the runner host. It never builds or
// replaces the bottled CLI/injector and never synthesizes input.
int main(int argc, const char *argv[]) {
    if (argc != 2) return 2;
    if (getenv("LOUPE_CI_OBSERVER_QOS") && strcmp(getenv("LOUPE_CI_OBSERVER_QOS"), "interactive") == 0) {
        if (pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) != 0) return 3;
    }
    fprintf(stdout, "observer actual_qos=%u mode=%s\n", qos_class_self(), getenv("LOUPE_CI_OBSERVER_QOS") ?: "inherited");
    fflush(stdout);
    @autoreleasepool {
        id activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep reason:@"Observe owned CI simulator boot"];
        uint32_t previous = UINT32_MAX - 1;
        int previousState = -1;
        uint64_t lastDiagnostic = 0;
        while (true) {
            @autoreleasepool {
                uint32_t status = 0;
                int state = 0;
                char *error = NULL;
                uint64_t callStart = monotonicNS();
                BOOL diagnose = lastDiagnostic == 0 || callStart - lastDiagnostic >= 15000000000ULL;
                if (diagnose) {
                    fprintf(stdout, "observer read.begin observed_ns=%llu qos=%u\n", (unsigned long long)callStart, qos_class_self());
                    fflush(stdout);
                    lastDiagnostic = callStart;
                }
                if (LoupeSimulatorBootStatus(argv[1], &status, &state, &error) != 0) {
                    fprintf(stderr, "%s\n", error ?: "Could not read simulator boot status");
                    LoupeHIDFreeCString(error); return 1;
                }
                if (diagnose) {
                    struct rusage usage;
                    getrusage(RUSAGE_SELF, &usage);
                    fprintf(stdout, "observer read.end observed_ns=%llu status=%u state=%d user_s=%ld.%06d system_s=%ld.%06d\n", (unsigned long long)monotonicNS(), status, state, usage.ru_utime.tv_sec, usage.ru_utime.tv_usec, usage.ru_stime.tv_sec, usage.ru_stime.tv_usec);
                    fflush(stdout);
                }
                BOOL finished = status == UINT32_MAX && state == 3;
                if (status != previous || state != previousState) {
                    uint64_t observed = monotonicNS();
                    NSDictionary *record = @{@"udid":[NSString stringWithUTF8String:argv[1]],
                        @"status":@(status), @"state":@(state), @"finished":@(finished),
                        @"observedMonotonicNS":@(observed)};
                    NSError *failure = nil;
                    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:&failure];
                    if (!data) {
                        fprintf(stderr, "%s\n", failure.description.UTF8String); return 1;
                    }
                    // Publish completion directly to the parent. Foundation's
                    // atomic file replacement can stall on the hosted disk even
                    // after CoreSimulator has completed within its deadline.
                    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (fprintf(stdout, "%s\n", line.UTF8String) < 0 || fflush(stdout) != 0) return 1;
                    previous = status; previousState = state;
                }
                if (status == 3) { fprintf(stderr, "Simulator data migration failed\n"); return 1; }
                if (finished) { [NSProcessInfo.processInfo endActivity:activity]; return 0; }
                // Permit CoreSimulator's state notifications to run on main.
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
            }
        }
    }
}
