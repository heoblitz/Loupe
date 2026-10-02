#ifndef LOUPE_SIMULATOR_OBSERVATION_H
#define LOUPE_SIMULATOR_OBSERVATION_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 0: PNG copied, 1: capture failed, 2: framebuffer API unavailable.
// Caller owns both returned buffers. Observation does not write files or input.
int LoupeSimulatorCopyPNG(const char *udid, void **bytes, size_t *count, char **errorMessage);
void LoupeSimulatorFreeBuffer(void *bytes);
int LoupeSimulatorBootStatus(const char *udid, uint32_t *status, int *state, char **errorMessage);
#ifdef __cplusplus
}
#endif
#endif
