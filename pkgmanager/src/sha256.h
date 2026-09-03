#ifndef LPM_SHA256_H
#define LPM_SHA256_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];
} lpm_sha256_ctx;

void lpm_sha256_init(lpm_sha256_ctx *ctx);
void lpm_sha256_update(lpm_sha256_ctx *ctx, const void *data, size_t len);
void lpm_sha256_final(lpm_sha256_ctx *ctx, uint8_t hash[32]);

/* Helper to compute hex string for a buffer */
void lpm_sha256_buffer(const void *data, size_t len, char hex_out[65]);

/* Helper to compute hex string for a file. Returns 0 on success, -1 on error */
int lpm_sha256_file(const char *filepath, char hex_out[65]);

#endif
